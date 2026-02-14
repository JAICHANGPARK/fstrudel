import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:strudel_dart/strudel_dart.dart';
import 'control_support.dart';
import 'sample_manager.dart';
import 'wavetable_manager.dart';

/// Audio Engine using flutter_soloud for audio playback with DSP effects
class AudioEngine {
  static const int _sampleRate = 44100;
  static const String _soLoudTempDirName = 'SoLoudLoader-Temp-Files';

  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _loadedSources = {};
  final SampleManager _sampleManager = SampleManager();
  final SynthEngine _synthEngine = SynthEngine(sampleRate: _sampleRate);
  final WavetableManager _wavetableManager = WavetableManager();
  final LinkedHashMap<String, Uint8List> _synthCache = LinkedHashMap();
  final List<SoundHandle> _activeHandles = [];
  final Map<int, List<SoundHandle>> _cutGroups = {};
  bool _initialized = false;
  int _currentSessionId = 0;
  ControlGateMode _controlGateMode = ControlGateMode.warn;
  final Set<String> _warnedUnsupportedControls = {};
  final Set<String> _warnedPartialControls = {};

  static const int _maxSynthCacheEntries = 64;

  AudioEngine() {
    StrudelResources.onSamples = _handleSamples;
    StrudelResources.onTables = _handleTables;
  }

  void setControlGateMode(ControlGateMode mode) {
    _controlGateMode = mode;
    _warnedUnsupportedControls.clear();
    _warnedPartialControls.clear();
  }

  // Track active filter states
  bool _echoActive = false;
  bool _reverbActive = false;
  bool _lofiActive = false;
  bool _biquadActive = false;
  bool _bassboostActive = false;
  bool _flangerActive = false;
  bool _waveshapeActive = false;
  bool _robotizeActive = false;
  bool _compressorActive = false;
  bool _limiterActive = false;

  Future<void> _ensureSoLoudTempDir() async {
    final systemTempDir = await getTemporaryDirectory();
    final tempDirPath = path.join(systemTempDir.path, _soLoudTempDirName);
    await Directory(tempDirPath).create(recursive: true);
  }

  Future<void> init() async {
    if (_initialized) return;
    print('AudioEngine: Initializing flutter_soloud...');
    try {
      await _ensureSoLoudTempDir();
      await _soloud.init(sampleRate: _sampleRate);
      print('AudioEngine: Loading default sample packs...');
      await _sampleManager.initializeDefaults();
      _initialized = true;
      print('AudioEngine: Initialized successfully with flutter_soloud');
    } catch (e) {
      print('AudioEngine: Initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _handleSamples(
    dynamic sampleMap, {
    String? baseUrl,
    Map<String, dynamic>? options,
  }) async {
    await _sampleManager.addSampleMap(sampleMap, baseUrl: baseUrl);
    await _wavetableManager.registerWavetablesFromSampleMap(
      sampleMap,
      baseUrl: baseUrl,
    );
  }

  Future<void> _handleTables(
    dynamic source, {
    int? frameLen,
    dynamic json,
    Map<String, dynamic>? options,
  }) async {
    final effectiveFrameLen = frameLen ?? 2048;
    if (json is Map<String, dynamic>) {
      _wavetableManager.registerTablesFromJson(
        json,
        baseUrl: source is String ? source : null,
        frameLen: effectiveFrameLen,
      );
      return;
    }
    if (source is String) {
      await _wavetableManager.registerTablesFromUrl(
        source,
        frameLen: effectiveFrameLen,
      );
      return;
    }
    print('AudioEngine: tables() expects a URL string.');
  }

  Future<void> play(Hap hap) async {
    if (!_initialized) {
      print('AudioEngine: Cannot play - not initialized');
      return;
    }

    final sessionId = _currentSessionId;
    final params = hap.value;
    if (params is! Map) {
      print('AudioEngine: Hap value is not a Map: ${hap.value}');
      return;
    }

    final paramsMap = Map<String, dynamic>.from(params);
    _normalizeControlAliases(paramsMap);
    if (!_enforceControlGate(paramsMap)) {
      return;
    }

    final sound = paramsMap['s']?.toString().trim();
    if (sound == null || sound.isEmpty) return;

    final soundLower = sound.toLowerCase();
    if (_synthEngine.supportsSound(soundLower, paramsMap)) {
      await _playSynth(hap, paramsMap, soundLower, sessionId);
      return;
    }

    final bank = paramsMap['bank']?.toString();
    final nVal = paramsMap['n'];
    final int n = nVal is num ? nVal.toInt() : 0;
    final note = paramsMap['note'];
    final freq = paramsMap['freq'];

    // Get sample path
    String? path = await _sampleManager.getSamplePath(
      sound,
      bank: bank,
      n: n,
      note: note,
      freq: freq,
    );

    if (path == null) {
      print('AudioEngine: No sample found for sound "$sound" (bank: $bank)');
      return;
    }

    try {
      // Load or get cached source
      AudioSource source = await _getOrLoadSource(path);

      if (_currentSessionId != sessionId) return;

      // Extract audio parameters
      final gain = _getDouble(paramsMap['gain'], 1.0);
      final amp = _getDouble(paramsMap['amp'], 1.0);
      final velocity = _getDouble(paramsMap['velocity'], 1.0);
      final pan = _normalizePan(_getDouble(paramsMap['pan'], 0.0));
      final speed = _getDouble(paramsMap['speed'], 1.0);

      final cutGroup = _getInt(paramsMap['cut']);
      if (cutGroup != null && cutGroup > 0) {
        await _stopCutGroup(cutGroup);
      }

      // Apply global filters based on parameters
      await _applyGlobalFilters(paramsMap);

      // Wait for scheduled time if needed
      if (hap.scheduledTime != null) {
        final now = DateTime.now();
        final delayDuration = hap.scheduledTime!.difference(now);
        if (delayDuration.inMicroseconds > 2000) {
          await Future.delayed(
            Duration(microseconds: delayDuration.inMicroseconds - 2000),
          );
        }
      }

      if (_currentSessionId != sessionId) return;

      // Play sound with parameters
      final volume = (gain * amp * velocity).clamp(0.0, 2.0);
      final handle = await _soloud.play(
        source,
        volume: volume,
        pan: pan.clamp(-1.0, 1.0),
      );

      _applyPlaybackControls(handle, source, paramsMap, speed: speed);

      // Apply per-sound filters
      await _applyPerSoundFilters(handle, paramsMap, source);

      _activeHandles.add(handle);
      if (cutGroup != null && cutGroup > 0) {
        _cutGroups.putIfAbsent(cutGroup, () => []).add(handle);
      }

      // Clean up finished handles periodically
      if (_activeHandles.length > 50) {
        _cleanupFinishedHandles();
      }

      print(
        'AudioEngine: Playing $sound '
        '(gain:${gain.toStringAsFixed(2)}, '
        'pan:${pan.toStringAsFixed(2)})',
      );
    } catch (e) {
      print('AudioEngine: Error playing sample "$sound": $e');
    }
  }

  Future<void> _playSynth(
    Hap hap,
    Map<String, dynamic> params,
    String sound,
    int sessionId,
  ) async {
    final cps = _getDouble(hap.context['cps'], 0.0);
    final durationParam = _getDouble(params['duration'], double.nan);
    final durationSeconds = durationParam.isNaN
        ? (cps > 0 ? hap.duration.toDouble() / cps : 0.2)
        : durationParam;

    params['duration'] = durationSeconds;
    params['cps'] = cps;

    final shouldCache = _shouldCacheSynth(sound, params);
    final cacheKey = shouldCache
        ? _buildSynthCacheKey(sound, params, durationSeconds)
        : null;
    Uint8List? wavBytes = cacheKey != null ? _getSynthCache(cacheKey) : null;

    final isWavetable = _wavetableManager.isWavetableSound(sound);
    if (wavBytes == null && isWavetable) {
      final ready = await _wavetableManager.prepare(sound, params);
      if (!ready) {
        print('AudioEngine: Wavetable not ready for "$sound"');
        return;
      }
      if (_currentSessionId != sessionId) return;
    }

    if (wavBytes == null) {
      if (!isWavetable) {
        try {
          wavBytes = await compute(_renderSynthIsolate, {
            'params': Map<String, dynamic>.from(params),
            'duration': durationSeconds,
            'sampleRate': _sampleRate,
          });
        } catch (e) {
          print('AudioEngine: Isolate render failed: $e');
        }
      }
      wavBytes ??= _synthEngine.render(params, durationSeconds).wavBytes;
      if (cacheKey != null) {
        _putSynthCache(cacheKey, wavBytes);
      }
    }

    if (_currentSessionId != sessionId) return;

    final cutGroup = _getInt(params['cut']);
    if (cutGroup != null && cutGroup > 0) {
      await _stopCutGroup(cutGroup);
    }
    await _applyGlobalFilters(params);

    final key =
        'synth:$sound:${DateTime.now().microsecondsSinceEpoch.toString()}';

    try {
      final source = await _soloud.loadMem(key, wavBytes);
      if (_currentSessionId != sessionId) {
        await _soloud.disposeSource(source);
        return;
      }

      // Wait for scheduled time if needed
      if (hap.scheduledTime != null) {
        final now = DateTime.now();
        final delayDuration = hap.scheduledTime!.difference(now);
        if (delayDuration.inMicroseconds > 2000) {
          await Future.delayed(
            Duration(microseconds: delayDuration.inMicroseconds - 2000),
          );
        }
      }

      if (_currentSessionId != sessionId) {
        await _soloud.disposeSource(source);
        return;
      }

      final gain = _getDouble(params['gain'], 1.0);
      final amp = _getDouble(params['amp'], 1.0);
      final velocity = _getDouble(params['velocity'], 1.0);
      final pan = _normalizePan(_getDouble(params['pan'], 0.0));
      final volume = (gain * amp * velocity).clamp(0.0, 2.0);
      final handle = await _soloud.play(
        source,
        volume: volume,
        pan: pan.clamp(-1.0, 1.0),
      );

      _activeHandles.add(handle);
      if (cutGroup != null && cutGroup > 0) {
        _cutGroups.putIfAbsent(cutGroup, () => []).add(handle);
      }

      source.allInstancesFinished.first.then((_) async {
        try {
          await _soloud.disposeSource(source);
        } catch (_) {}
      });

      if (_activeHandles.length > 50) {
        _cleanupFinishedHandles();
      }
    } catch (e) {
      print('AudioEngine: Error playing synth \"$sound\": $e');
    }
  }

  Future<void> evalCode(String code) async {
    throw UnsupportedError('evalCode is only supported on web.');
  }

  Future<void> _applyPerSoundFilters(
    SoundHandle handle,
    Map params,
    AudioSource source,
  ) async {
    // Per-sound filters are not fully supported on Web
    // TODO: Add Web platform check when API is available
    // if (_soloud.kIsWeb) return;

    // Check if source has filters available
    // Per-sound filters are not fully supported - skip for now
    return;

    // Apply per-sound distortion/waveshape if specified
    // This would require using source.filters but not fully implemented
  }

  void _applyPlaybackControls(
    SoundHandle handle,
    AudioSource source,
    Map params, {
    required double speed,
  }) {
    final safeSpeed = _coerceSpeed(speed);
    if (safeSpeed != 1.0) {
      try {
        _soloud.setRelativePlaySpeed(handle, safeSpeed);
      } catch (e) {
        print('AudioEngine: Error setting speed: $e');
      }
    }

    final length = _soloud.getLength(source);
    if (length.inMicroseconds <= 0) return;

    final begin = _clamp01(_getDouble(params['begin'], 0.0));
    final end = _resolveEnd(params);
    final loop = _getBool(params['loop']);
    final loopBegin = params.containsKey('loopBegin')
        ? _clamp01(_getDouble(params['loopBegin'], begin))
        : begin;

    if (begin > 0) {
      _safeSeek(handle, length, begin);
    }

    if (loop) {
      try {
        _soloud.setLooping(handle, true);
        if (loopBegin > 0) {
          _soloud.setLoopPoint(
            handle,
            Duration(microseconds: (length.inMicroseconds * loopBegin).round()),
          );
        }
      } catch (e) {
        print('AudioEngine: Error setting loop: $e');
      }
      return;
    }

    if (end < 1.0 && end > begin) {
      final playFraction = end - begin;
      final durationMicros = (length.inMicroseconds * playFraction / safeSpeed)
          .round();
      if (durationMicros > 0) {
        try {
          _soloud.scheduleStop(handle, Duration(microseconds: durationMicros));
        } catch (e) {
          print('AudioEngine: Error scheduling stop: $e');
        }
      }
    }
  }

  Future<void> _applyGlobalFilters(Map params) async {
    final filters = _soloud.filters;

    // Echo/Delay effect
    final delay = _getDouble(params['delay'], 0.0);
    if (delay > 0 && !_echoActive) {
      try {
        filters.echoFilter.activate();
        _echoActive = true;
      } catch (e) {
        print('AudioEngine: Error activating echo filter: $e');
      }
    }
    if (_echoActive && delay > 0) {
      final echoWet = delay.clamp(0.0, 1.0);
      _setFilterParam(FilterType.echoFilter, 0, echoWet);
      final delaytime = _getDouble(params['delaytime'], 0.25);
      _setFilterParam(FilterType.echoFilter, 1, delaytime.clamp(0.01, 2.0));
      final feedback = _getDouble(params['delayfeedback'], 0.5);
      _setFilterParam(FilterType.echoFilter, 2, feedback.clamp(0.0, 1.0));
    }

    // Reverb effect
    final room = _getDouble(params['room'], 0.0);
    if (room > 0 && !_reverbActive) {
      try {
        filters.freeverbFilter.activate();
        _reverbActive = true;
      } catch (e) {
        print('AudioEngine: Error activating freeverb filter: $e');
      }
    }
    if (_reverbActive) {
      final reverbWet = room.clamp(0.0, 1.0);
      _setFilterParam(FilterType.freeverbFilter, 0, reverbWet);
      final roomsize = _getDouble(params['roomsize'], 0.5);
      _setFilterParam(FilterType.freeverbFilter, 2, roomsize.clamp(0.0, 1.0));
      final roomfade = _getDouble(params['roomfade'], 0.5);
      _setFilterParam(FilterType.freeverbFilter, 3, roomfade.clamp(0.0, 1.0));
      final roomdim = _getDouble(params['roomdim'], 0.0);
      _setFilterParam(FilterType.freeverbFilter, 4, roomdim.clamp(0.0, 1.0));
    }

    // Lo-fi effect (bit crusher / sample rate reduction)
    final crush = _getDouble(params['crush'], 0.0);
    final coarse = _getDouble(params['coarse'], 0.0);
    if ((crush > 0 || coarse > 0) && !_lofiActive) {
      try {
        filters.lofiFilter.activate();
        _lofiActive = true;
      } catch (e) {
        print('AudioEngine: Error activating lofi filter: $e');
      }
    }
    if (_lofiActive) {
      final lofiWet = _getDouble(params['lofiwet'], 1.0);
      _setFilterParam(FilterType.lofiFilter, 0, lofiWet.clamp(0.0, 1.0));
      if (coarse > 0) {
        final sr = 44100 / coarse.clamp(1, 100);
        _setFilterParam(FilterType.lofiFilter, 1, sr);
      }
      if (crush > 0) {
        final bits = (16 - crush.clamp(0, 15)).toDouble();
        _setFilterParam(FilterType.lofiFilter, 2, bits);
      }
    }

    // Highpass filter
    final hpf = _getDouble(params['hpf'], 20000.0);
    if (hpf < 19999 && !_biquadActive) {
      try {
        filters.biquadResonantFilter.activate();
        _biquadActive = true;
      } catch (e) {
        print('AudioEngine: Error activating biquad filter: $e');
      }
    }
    if (_biquadActive && hpf < 19999) {
      _setFilterParam(FilterType.biquadResonantFilter, 1, 1.0);
      _setFilterParam(
        FilterType.biquadResonantFilter,
        2,
        hpf.clamp(20.0, 20000.0),
      );
      final hpq = _getDouble(params['hpq'], 1.0);
      _setFilterParam(FilterType.biquadResonantFilter, 3, hpq.clamp(0.5, 20.0));
    }

    // Bandpass filter
    final bandf = _getDouble(params['bandf'], 1000.0);
    if (bandf > 0 && !_biquadActive) {
      if (!_biquadActive) {
        try {
          filters.biquadResonantFilter.activate();
          _biquadActive = true;
        } catch (e) {
          print('AudioEngine: Error activating biquad filter: $e');
        }
      }
    }
    if (_biquadActive && bandf > 0) {
      _setFilterParam(FilterType.biquadResonantFilter, 1, 2.0);
      _setFilterParam(
        FilterType.biquadResonantFilter,
        2,
        bandf.clamp(20.0, 20000.0),
      );
      final bandq = _getDouble(params['bandq'], 1.0);
      _setFilterParam(
        FilterType.biquadResonantFilter,
        3,
        bandq.clamp(0.5, 20.0),
      );
    }

    // Lowpass filter
    final lpf = _getDouble(params['lpf'], 20000.0);
    if (lpf < 19999 && !_biquadActive) {
      try {
        filters.biquadResonantFilter.activate();
        _biquadActive = true;
      } catch (e) {
        print('AudioEngine: Error activating biquad filter: $e');
      }
    }
    if (_biquadActive && lpf < 19999) {
      _setFilterParam(FilterType.biquadResonantFilter, 1, 0.0);
      _setFilterParam(
        FilterType.biquadResonantFilter,
        2,
        lpf.clamp(20.0, 20000.0),
      );
      final lpq = _getDouble(params['lpq'], 1.0);
      _setFilterParam(FilterType.biquadResonantFilter, 3, lpq.clamp(0.5, 20.0));
    }

    // Filter type
    final ftypeVal = params['ftype'];
    if (ftypeVal != null) {
      final ftypeStr = ftypeVal.toString().toLowerCase();
      if (!_biquadActive) {
        try {
          filters.biquadResonantFilter.activate();
          _biquadActive = true;
        } catch (e) {
          print('AudioEngine: Error activating biquad filter: $e');
        }
      }
      if (_biquadActive) {
        int typeValue = 0;
        switch (ftypeStr) {
          case 'lowpass':
          case '12db':
            typeValue = 0;
            break;
          case 'highpass':
            typeValue = 1;
            break;
          case 'bandpass':
            typeValue = 2;
            break;
        }
        _setFilterParam(
          FilterType.biquadResonantFilter,
          1,
          typeValue.toDouble(),
        );
      }
    }

    // Bassboost filter
    final bassboost = _getDouble(params['bassboost'], 0.0);
    if (bassboost > 0 && !_bassboostActive) {
      try {
        filters.bassBoostFilter.activate();
        _bassboostActive = true;
      } catch (e) {
        print('AudioEngine: Error activating bassboost filter: $e');
      }
    }
    if (_bassboostActive) {
      _setFilterParam(FilterType.bassboostFilter, 0, 1.0);
      _setFilterParam(
        FilterType.bassboostFilter,
        1,
        bassboost.clamp(0.0, 10.0),
      );
    }

    // Flanger/Phaser effect
    final phaser = _getDouble(params['phaser'], 0.0);
    final phasersweep = _getDouble(params['phasersweep'], 0.1);
    final phaserdepth = _getDouble(params['phaserdepth'], 0.01);
    if (phaser > 0 && !_flangerActive) {
      try {
        filters.flangerFilter.activate();
        _flangerActive = true;
      } catch (e) {
        print('AudioEngine: Error activating flanger filter: $e');
      }
    }
    if (_flangerActive && phaser > 0) {
      _setFilterParam(FilterType.flangerFilter, 0, phaser.clamp(0.0, 1.0));
      _setFilterParam(FilterType.flangerFilter, 1, phaserdepth.clamp(0.0, 3.0));
      _setFilterParam(
        FilterType.flangerFilter,
        2,
        phasersweep.clamp(-48.0, 48.0),
      );
    }

    // Tremolo (placeholder)
    final tremolo = _getDouble(params['tremolo'], 0.0);
    if (tremolo > 0) {
      // Tremolo would require per-sound volume oscillator
      // Not implemented directly - would require custom DSP
    }

    // Distortion/Waveshape effects
    final distort = _getDouble(params['distort'], 0.0);
    final shape = _getDouble(params['shape'], 0.0);
    if ((distort > 0 || shape > 0) && !_waveshapeActive) {
      try {
        filters.waveShaperFilter.activate();
        _waveshapeActive = true;
      } catch (e) {
        print('AudioEngine: Error activating waveShaper filter: $e');
      }
    }
    if (_waveshapeActive) {
      _setFilterParam(FilterType.waveShaperFilter, 0, 1.0);
      final distortAmount = distort > 0 ? distort : shape;
      _setFilterParam(
        FilterType.waveShaperFilter,
        1,
        distortAmount.clamp(-1.0, 1.0),
      );
    }

    // Compressor effect
    final compressor = _getDouble(params['compressor'], 0.0);
    if (compressor > 0 && !_compressorActive) {
      try {
        filters.compressorFilter.activate();
        _compressorActive = true;
      } catch (e) {
        print('AudioEngine: Error activating compressor filter: $e');
      }
    }
    if (_compressorActive) {
      _setFilterParam(FilterType.compressorFilter, 0, 1.0);
      _setFilterParam(FilterType.compressorFilter, 1, -6.0);
      _setFilterParam(FilterType.compressorFilter, 2, 4.0);
      _setFilterParam(FilterType.compressorFilter, 3, 0.0);
      _setFilterParam(FilterType.compressorFilter, 4, 10.0);
      _setFilterParam(FilterType.compressorFilter, 5, 100.0);
    }

    // Limiter effect
    final clip = _getDouble(params['clip'], 0.0);
    if (clip > 0 && !_limiterActive) {
      try {
        filters.limiterFilter.activate();
        _limiterActive = true;
      } catch (e) {
        print('AudioEngine: Error activating limiter filter: $e');
      }
    }
    if (_limiterActive) {
      _setFilterParam(FilterType.limiterFilter, 0, 1.0);
      _setFilterParam(FilterType.limiterFilter, 1, -1.0);
      _setFilterParam(FilterType.limiterFilter, 2, -0.1);
      _setFilterParam(FilterType.limiterFilter, 3, 5.0);
      _setFilterParam(FilterType.limiterFilter, 4, 10.0);
    }

    // Robotize effect
    final robotize = _getDouble(params['robotize'], 0.0);
    if (robotize > 0 && !_robotizeActive) {
      try {
        filters.robotizeFilter.activate();
        _robotizeActive = true;
      } catch (e) {
        print('AudioEngine: Error activating robotize filter: $e');
      }
    }
    if (_robotizeActive) {
      _setFilterParam(FilterType.robotizeFilter, 0, 1.0);
      _setFilterParam(FilterType.robotizeFilter, 1, 10.0);
      _setFilterParam(FilterType.robotizeFilter, 2, 1.0);
    }

    // Duck effect (placeholder)
    final duck = _getDouble(params['duck'], 0.0);
    if (duck > 0) {
      // Ducking requires side-chain - not implemented
    }

    // Postgain
    final postgain = _getDouble(params['postgain'], 0.0);
    final xfade = _getDouble(params['xfade'], 0.0);
    if (postgain != 0.0 || xfade != 0.0) {
      // Postgain and xfade would require per-sound control
      // Currently only global volume can be adjusted
    }
  }

  void _setFilterParam(FilterType type, int attributeId, double value) {
    try {
      _soloud.setGlobalFilterParameter(type, attributeId, value);
    } catch (e) {
      print('AudioEngine: Error setting filter parameter: $e');
    }
  }

  Future<AudioSource> _getOrLoadSource(String path) async {
    if (_loadedSources.containsKey(path)) {
      return _loadedSources[path]!;
    }

    print('AudioEngine: Loading source from $path');
    final source = await _soloud.loadFile(path);
    _loadedSources[path] = source;
    return source;
  }

  void _normalizeControlAliases(Map<String, dynamic> params) {
    if (!params.containsKey('roomsize') && params.containsKey('size')) {
      params['roomsize'] = params['size'];
    }
    if (!params.containsKey('decay') && params.containsKey('dec')) {
      params['decay'] = params['dec'];
    }
  }

  bool _enforceControlGate(Map<String, dynamic> params) {
    if (_controlGateMode == ControlGateMode.off) {
      return true;
    }

    final report = ControlSupportMatrix.evaluate(params);
    if (_controlGateMode == ControlGateMode.strict && report.hasUnsupported) {
      final unsupported = ControlSupportMatrix.formatKeys(report.unsupported);
      print('AudioEngine: Unsupported controls (strict gate): $unsupported');
      return false;
    }

    if (_controlGateMode == ControlGateMode.warn) {
      final newUnsupported = report.unsupported.where(
        (k) => !_warnedUnsupportedControls.contains(k),
      );
      final newPartial = report.partial.where(
        (k) => !_warnedPartialControls.contains(k),
      );

      if (newUnsupported.isNotEmpty) {
        final unsupported = ControlSupportMatrix.formatKeys(newUnsupported);
        print('AudioEngine: Unsupported controls (ignored): $unsupported');
        _warnedUnsupportedControls.addAll(newUnsupported);
      }
      if (newPartial.isNotEmpty) {
        final partial = ControlSupportMatrix.formatKeys(newPartial);
        print('AudioEngine: Partially supported controls: $partial');
        _warnedPartialControls.addAll(newPartial);
      }
    }
    return true;
  }

  double _getDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  int? _getInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _getBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes') return true;
      if (normalized == 'false' || normalized == 'no') return false;
      final parsed = double.tryParse(normalized);
      if (parsed != null) return parsed != 0;
    }
    return false;
  }

  bool _shouldCacheSynth(String sound, Map<String, dynamic> params) {
    final soundKey = _stripSoundIndex(sound.toLowerCase());
    if (_isNoiseSound(soundKey)) return false;
    if (_getDouble(params['noise'], 0.0) > 0) return false;
    if (_getDouble(params['zrand'], 0.0) > 0) return false;
    return true;
  }

  bool _isNoiseSound(String sound) {
    return sound == 'white' ||
        sound == 'pink' ||
        sound == 'brown' ||
        sound == 'crackle' ||
        sound == 'dust';
  }

  String _buildSynthCacheKey(
    String sound,
    Map<String, dynamic> params,
    double durationSeconds,
  ) {
    final entries =
        params.entries.where((entry) => !_ignoreCacheKey(entry.key)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final buffer = StringBuffer()
      ..write(sound.toLowerCase())
      ..write('|')
      ..write(durationSeconds.toStringAsFixed(6));
    for (final entry in entries) {
      buffer
        ..write('|')
        ..write(entry.key)
        ..write('=')
        ..write(_serializeValue(entry.value));
    }
    return buffer.toString();
  }

  bool _ignoreCacheKey(String key) {
    return key == 'amp' || key == 'cut';
  }

  String _stripSoundIndex(String sound) {
    final idx = sound.lastIndexOf(':');
    if (idx <= 0) return sound;
    return sound.substring(0, idx);
  }

  String _serializeValue(dynamic value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return value.toString();
    if (value is String) return value;
    if (value is List) {
      return '[${value.map(_serializeValue).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      final parts = entries
          .map((entry) => '${entry.key}:${_serializeValue(entry.value)}')
          .join(',');
      return '{${parts}}';
    }
    return value.toString();
  }

  Uint8List? _getSynthCache(String key) {
    final bytes = _synthCache.remove(key);
    if (bytes != null) {
      _synthCache[key] = bytes;
    }
    return bytes;
  }

  void _putSynthCache(String key, Uint8List bytes) {
    _synthCache.remove(key);
    _synthCache[key] = bytes;
    if (_synthCache.length > _maxSynthCacheEntries) {
      _synthCache.remove(_synthCache.keys.first);
    }
  }

  double _coerceSpeed(double speed) {
    final value = speed == 0 ? 1.0 : speed.abs();
    return value.clamp(0.05, 4.0);
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0);

  double _resolveEnd(Map params) {
    if (params.containsKey('end')) {
      return _clamp01(_getDouble(params['end'], 1.0));
    }
    if (params.containsKey('loopEnd')) {
      return _clamp01(_getDouble(params['loopEnd'], 1.0));
    }
    return 1.0;
  }

  double _normalizePan(double pan) {
    if (pan >= 0.0 && pan <= 1.0) {
      return (pan * 2.0) - 1.0;
    }
    return pan;
  }

  void _safeSeek(SoundHandle handle, Duration length, double position) {
    try {
      _soloud.seek(
        handle,
        Duration(microseconds: (length.inMicroseconds * position).round()),
      );
    } catch (e) {
      print('AudioEngine: Error seeking sample: $e');
    }
  }

  Future<void> _stopCutGroup(int group) async {
    final handles = _cutGroups.remove(group);
    if (handles == null || handles.isEmpty) return;
    for (final handle in handles) {
      try {
        if (_soloud.getIsValidVoiceHandle(handle)) {
          await _soloud.stop(handle);
        }
      } catch (_) {}
    }
    _activeHandles.removeWhere(handles.contains);
  }

  void _cleanupFinishedHandles() {
    final invalid = _activeHandles
        .where((handle) => !_soloud.getIsValidVoiceHandle(handle))
        .toSet();
    if (invalid.isEmpty) return;
    _activeHandles.removeWhere(invalid.contains);
    for (final entry in _cutGroups.entries.toList()) {
      entry.value.removeWhere(invalid.contains);
      if (entry.value.isEmpty) {
        _cutGroups.remove(entry.key);
      }
    }
  }

  Future<void> stopAll() async {
    _currentSessionId++;

    // Stop all active handles
    for (final handle in _activeHandles) {
      try {
        if (_soloud.getIsValidVoiceHandle(handle)) {
          await _soloud.stop(handle);
        }
      } catch (_) {}
    }
    _activeHandles.clear();
    _cutGroups.clear();

    // Deactivate all filters
    _deactivateAllFilters();
  }

  void _deactivateAllFilters() {
    final filters = _soloud.filters;
    if (_echoActive) {
      try {
        filters.echoFilter.deactivate();
        _echoActive = false;
      } catch (_) {}
    }
    if (_reverbActive) {
      try {
        filters.freeverbFilter.deactivate();
        _reverbActive = false;
      } catch (_) {}
    }
    if (_lofiActive) {
      try {
        filters.lofiFilter.deactivate();
        _lofiActive = false;
      } catch (_) {}
    }
    if (_biquadActive) {
      try {
        filters.biquadResonantFilter.deactivate();
        _biquadActive = false;
      } catch (_) {}
    }
    if (_bassboostActive) {
      try {
        filters.bassBoostFilter.deactivate();
        _bassboostActive = false;
      } catch (_) {}
    }
    if (_flangerActive) {
      try {
        filters.flangerFilter.deactivate();
        _flangerActive = false;
      } catch (_) {}
    }
    if (_waveshapeActive) {
      try {
        filters.waveShaperFilter.deactivate();
        _waveshapeActive = false;
      } catch (_) {}
    }
    if (_robotizeActive) {
      try {
        filters.robotizeFilter.deactivate();
        _robotizeActive = false;
      } catch (_) {}
    }
    if (_compressorActive) {
      try {
        filters.compressorFilter.deactivate();
        _compressorActive = false;
      } catch (_) {}
    }
    if (_limiterActive) {
      try {
        filters.limiterFilter.deactivate();
        _limiterActive = false;
      } catch (_) {}
    }
  }

  void dispose() {
    // Dispose all loaded sources
    for (final source in _loadedSources.values) {
      try {
        _soloud.disposeSource(source);
      } catch (_) {}
    }
    _loadedSources.clear();
    _cutGroups.clear();
    _soloud.deinit();
  }
}

Uint8List _renderSynthIsolate(Map<String, dynamic> message) {
  final params = Map<String, dynamic>.from(message['params'] as Map);
  final duration = message['duration'] as double;
  final sampleRate = message['sampleRate'] as int;
  final engine = SynthEngine(sampleRate: sampleRate);
  return engine.render(params, duration).wavBytes;
}
