import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:strudel_dart/strudel_dart.dart';
import 'sample_manager.dart';

class AudioEngine {
  final Map<String, String> _samplePaths = {};
  bool _initialized = false;
  final SampleManager _sampleManager = SampleManager();
  int _currentSessionId = 0;

  // Player Pool to handle polyphony efficiently and avoid platform channel limits
  final List<AudioPlayer> _playerPool = [];
  final Set<AudioPlayer> _busyPlayers = {};
  static const int _maxPoolSize = 16;

  Future<void> init() async {
    if (_initialized) return;
    print('AudioEngine: Initializing (just_audio)...');
    try {
      await _generateSamplesToFiles();
      _initialized = true;
      print(
        'AudioEngine: Initialized successfully. Synthetic samples: ${_samplePaths.keys}',
      );
    } catch (e) {
      print('AudioEngine: Initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _generateSamplesToFiles() async {
    final tempDir = await getTemporaryDirectory();
    final strudelDir = Directory(p.join(tempDir.path, 'strudel_samples'));
    if (!await strudelDir.exists()) {
      await strudelDir.create(recursive: true);
    }

    _samplePaths['bd'] = await _writeSample(strudelDir, 'bd', _generateKick());
    _samplePaths['sd'] = await _writeSample(strudelDir, 'sd', _generateSnare());
    _samplePaths['hh'] = await _writeSample(strudelDir, 'hh', _generateHiHat());
    _samplePaths['oh'] = await _writeSample(
      strudelDir,
      'oh',
      _generateOpenHat(),
    );
    _samplePaths['cp'] = await _writeSample(strudelDir, 'cp', _generateClap());
  }

  Future<String> _writeSample(
    Directory dir,
    String name,
    Uint8List data,
  ) async {
    final file = File(p.join(dir.path, '$name.wav'));
    await file.writeAsBytes(data);
    return file.path;
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

    final sound = params['s']?.toString().trim();
    if (sound == null) return;

    final bank = params['bank']?.toString();
    final nVal = params['n'];
    final int n = nVal is num ? nVal.toInt() : 0;

    String? path;

    // 1. Try remote/bank samples first if bank is provided
    if (bank != null && bank.isNotEmpty) {
      path = await _sampleManager.getSamplePath(sound, bank: bank, n: n);
    }

    // 2. Try generic remote mapping
    path ??= await _sampleManager.getSamplePath(sound, n: n);

    // 3. Fallback to synthetic samples
    path ??= _samplePaths[sound];

    if (path == null) {
      print('AudioEngine: No sample found for sound "$sound" (bank: $bank)');
      return;
    }

    try {
      final player = _getOrCreatePlayer();
      _busyPlayers.add(player);

      try {
        if (_currentSessionId != sessionId) return;

        final gain = params['gain'] is num
            ? (params['gain'] as num).toDouble()
            : 1.0;
        final speed = params['speed'] is num
            ? (params['speed'] as num).toDouble()
            : 1.0;

        await player.setVolume(gain);
        await player.setSpeed(speed);

        // Pre-load immediately
        await player.setFilePath(path);

        // Precise sync: Wait for the scheduled onset time
        if (hap.scheduledTime != null) {
          final now = DateTime.now();
          final delay = hap.scheduledTime!.difference(now);
          if (delay.isNegative) {
            // Already late (or very close), play immediately
            if (_currentSessionId != sessionId) return;
            await player.play();
          } else {
            // Wait for the exact moment
            // Subtract a small buffer (e.g., 2ms) for platform/switching overhead
            final waitMicros = delay.inMicroseconds - 2000;
            if (waitMicros > 0) {
              await Future.delayed(Duration(microseconds: waitMicros));
            }
            if (_currentSessionId != sessionId) return;
            await player.play();
          }
        } else {
          if (_currentSessionId != sessionId) return;
          await player.play();
        }
      } finally {
        // Release player after it finishes or starts
        _busyPlayers.remove(player);
      }
    } catch (e) {
      print('AudioEngine: Error playing sample "$sound": $e');
    }
  }

  AudioPlayer _getOrCreatePlayer() {
    // Try to find a player that is not playing and not currently busy
    for (final player in _playerPool) {
      if (!player.playing && !_busyPlayers.contains(player)) {
        return player;
      }
    }

    // If pool is not full, create new
    if (_playerPool.length < _maxPoolSize) {
      print(
        'AudioEngine: Creating new AudioPlayer instance (Pool size: ${_playerPool.length + 1})',
      );
      final player = AudioPlayer();
      _playerPool.add(player);
      return player;
    }

    // fallback: reuse the oldest player (circular)
    // We move it to the end of the list to keep it as "most recently used"
    final player = _playerPool.removeAt(0);
    player.stop();
    _playerPool.add(player);
    print('AudioEngine: Reusing AudioPlayer from pool');
    return player;
  }

  Uint8List _generateKick() {
    const int sampleRate = 44100;
    const double duration = 0.2;
    final int numSamples = (sampleRate * duration).toInt();
    final Int16List data = Int16List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double freq = 100 * exp(-15 * t) + 40;
      final double envelope = exp(-10 * t);
      final double sample = sin(2 * pi * freq * t) * envelope;
      data[i] = (sample * 32767).clamp(-32768, 32767).toInt();
    }
    return _toWav(data, sampleRate);
  }

  Uint8List _generateSnare() {
    const int sampleRate = 44100;
    const double duration = 0.15;
    final int numSamples = (sampleRate * duration).toInt();
    final Int16List data = Int16List(numSamples);
    final Random rand = Random();

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double noise = rand.nextDouble() * 2 - 1;
      final double tone = sin(2 * pi * 180 * t) * 0.5;
      final double envelope = exp(-15 * t);
      final double sample = (noise + tone) * 0.5 * envelope;
      data[i] = (sample * 32767).clamp(-32768, 32767).toInt();
    }
    return _toWav(data, sampleRate);
  }

  Uint8List _generateHiHat() {
    const int sampleRate = 44100;
    const double duration = 0.05;
    final int numSamples = (sampleRate * duration).toInt();
    final Int16List data = Int16List(numSamples);
    final Random rand = Random();

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double noise = rand.nextDouble() * 2 - 1;
      final double envelope = exp(-40 * t);
      data[i] = (noise * 32767 * envelope).clamp(-32768, 32767).toInt();
    }
    return _toWav(data, sampleRate);
  }

  Uint8List _generateOpenHat() {
    const int sampleRate = 44100;
    const double duration = 0.3;
    final int numSamples = (sampleRate * duration).toInt();
    final Int16List data = Int16List(numSamples);
    final Random rand = Random();

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double noise = rand.nextDouble() * 2 - 1;
      final double envelope = exp(-5 * t);
      data[i] = (noise * 32767 * envelope).clamp(-32768, 32767).toInt();
    }
    return _toWav(data, sampleRate);
  }

  Uint8List _generateClap() {
    const int sampleRate = 44100;
    const double duration = 0.3;
    final int numSamples = (sampleRate * duration).toInt();
    final Int16List data = Int16List(numSamples);
    final Random rand = Random();

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double noise = rand.nextDouble() * 2 - 1;
      double env = 0;
      if (t < 0.01) {
        env = exp(-100 * t);
      } else if (t < 0.02) {
        env = exp(-100 * (t - 0.01));
      } else if (t < 0.03) {
        env = exp(-100 * (t - 0.02));
      } else {
        env = exp(-15 * (t - 0.03));
      }

      double sample = noise * env;
      data[i] = (sample * 32767).clamp(-32768, 32767).toInt();
    }
    return _toWav(data, sampleRate);
  }

  Uint8List _toWav(Int16List pcmData, int sampleRate) {
    int bytesPerSample = 2;
    int numChannels = 1;
    int byteRate = sampleRate * numChannels * bytesPerSample;
    int blockAlign = numChannels * bytesPerSample;
    final int dataSize = pcmData.length * bytesPerSample;
    final int fileSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    int offset = 0;

    void writeString(String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset++, s.codeUnitAt(i));
      }
    }

    writeString('RIFF');
    header.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    writeString('WAVE');
    writeString('fmt ');
    header.setUint32(offset, 16, Endian.little);
    offset += 4;
    header.setUint16(offset, 1, Endian.little);
    offset += 2;
    header.setUint16(offset, numChannels, Endian.little);
    offset += 2;
    header.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    header.setUint32(offset, byteRate, Endian.little);
    offset += 4;
    header.setUint16(offset, blockAlign, Endian.little);
    offset += 2;
    header.setUint16(offset, bytesPerSample * 8, Endian.little);
    offset += 2;
    writeString('data');
    header.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    final Uint8List wav = Uint8List(44 + dataSize);
    wav.setAll(0, header.buffer.asUint8List());
    wav.setAll(44, pcmData.buffer.asUint8List());
    return wav;
  }

  Future<void> stopAll() async {
    _currentSessionId++;
    for (var player in _playerPool) {
      await player.stop();
    }
  }

  void dispose() {
    for (final player in _playerPool) {
      player.dispose();
    }
    _playerPool.clear();
  }
}
