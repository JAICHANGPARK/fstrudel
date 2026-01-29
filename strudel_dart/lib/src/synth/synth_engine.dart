import 'dart:math' as math;
import 'dart:typed_data';

import 'dough.dart';
import 'wav.dart';
import 'wavetable_registry.dart';
import 'zzfx.dart';

/// Output from the synth renderer.
class SynthRenderResult {
  /// Creates a new render result.
  const SynthRenderResult({
    required this.wavBytes,
    required this.sampleRate,
    required this.frameCount,
    required this.duration,
  });

  /// The WAV-encoded audio bytes.
  final Uint8List wavBytes;

  /// The sample rate used for rendering.
  final int sampleRate;

  /// Total number of frames in the rendered buffer.
  final int frameCount;

  /// Total playback duration of the buffer.
  final Duration duration;
}

/// Renders Strudel synth voices into WAV buffers.
class SynthEngine {
  /// Creates a synth renderer with the given sample rate.
  SynthEngine({int sampleRate = 48000})
      : _sampleRate = sampleRate,
        _zzfx = ZzfxSynth(sampleRate: sampleRate);

  final int _sampleRate;
  final ZzfxSynth _zzfx;

  /// Returns true when the sound is supported by this engine.
  bool supportsSound(String sound, Map<String, dynamic> params) {
    final name = sound.toLowerCase();
    final baseName = _stripSoundIndex(name);
    if (_isZzfxSound(baseName)) return true;
    if (params.containsKey('partials') || params.containsKey('phases')) {
      return true;
    }
    if (WavetableRegistry.hasDefinition(baseName)) return true;
    if (baseName.startsWith('wt_')) return true;
    return doughSoundNames.contains(baseName) || baseName == 'user';
  }

  /// Render a sound into a WAV buffer.
  SynthRenderResult render(
    Map<String, dynamic> params,
    double durationSeconds,
  ) {
    final sound = (params['s']?.toString() ?? '').toLowerCase();

    if (_isZzfxSound(sound)) {
      return _renderZzfx(params, durationSeconds);
    }
    return _renderDough(params, durationSeconds);
  }

  SynthRenderResult _renderDough(
    Map<String, dynamic> params,
    double durationSeconds,
  ) {
    final value = Map<String, dynamic>.from(params);
    value['_begin'] = 0.0;
    value['_duration'] = durationSeconds;

    final release = _doubleParam(params, 'release') ?? 0.01;
    final delayAmount = _doubleParam(params, 'delay') ?? 0.0;
    final delayTime = _doubleParam(params, 'delaytime') ?? 0.25;
    final delayFeedback = _doubleParam(params, 'delayfeedback') ?? 0.5;

    var tail = 0.02 + release;
    if (delayAmount > 0) {
      final repeats = 1 + (delayFeedback.clamp(0.0, 0.98) * 2);
      tail += delayTime * repeats;
    }

    final totalSeconds = math.max(durationSeconds + tail, 0.01);
    final totalSamples = (totalSeconds * _sampleRate).ceil();

    final left = Float32List(totalSamples);
    final right = Float32List(totalSamples);

    final dough = Dough(sampleRate: _sampleRate.toDouble());
    dough.scheduleSpawn(value);

    for (var i = 0; i < totalSamples; i++) {
      dough.update();
      left[i] = dough.out[0];
      right[i] = dough.out[1];
    }

    final wavBytes = WavEncoder.encodePcm16Stereo(
      left: left,
      right: right,
      sampleRate: _sampleRate,
    );

    return SynthRenderResult(
      wavBytes: wavBytes,
      sampleRate: _sampleRate,
      frameCount: totalSamples,
      duration: Duration(
        milliseconds: (totalSeconds * 1000).round(),
      ),
    );
  }

  SynthRenderResult _renderZzfx(
    Map<String, dynamic> params,
    double durationSeconds,
  ) {
    final mono = _zzfx.render(params, durationSeconds);
    final right = Float32List(mono.length);
    right.setAll(0, mono);

    final wavBytes = WavEncoder.encodePcm16Stereo(
      left: mono,
      right: right,
      sampleRate: _sampleRate,
    );

    final duration = mono.isEmpty
        ? Duration.zero
        : Duration(
            milliseconds: (mono.length / _sampleRate * 1000).round(),
          );

    return SynthRenderResult(
      wavBytes: wavBytes,
      sampleRate: _sampleRate,
      frameCount: mono.length,
      duration: duration,
    );
  }

  bool _isZzfxSound(String sound) {
    if (sound == 'zzfx') return true;
    return sound.startsWith('z_');
  }
}

String _stripSoundIndex(String sound) {
  final idx = sound.lastIndexOf(':');
  if (idx <= 0) return sound;
  return sound.substring(0, idx);
}

double? _doubleParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
