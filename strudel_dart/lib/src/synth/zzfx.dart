import 'dart:math' as math;
import 'dart:typed_data';

import '../util.dart' as util;

/// ZzFX sample generator ported from Strudel's zzfx_fork.mjs.
class ZzfxSynth {
  /// Creates a ZzFX renderer for a given sample rate.
  ZzfxSynth({required this.sampleRate, math.Random? random})
      : _random = random ?? math.Random();

  /// The sample rate used for rendering.
  final int sampleRate;

  final math.Random _random;

  /// Render a mono ZzFX buffer from the given parameters.
  Float32List render(Map<String, dynamic> params, double durationSeconds) {
    final sound = (params['s']?.toString() ?? '').replaceFirst('z_', '');

    final zrand = _doubleParam(params, 'zrand') ?? 0;
    final attack = _doubleParam(params, 'attack') ?? 0;
    final decay = _doubleParam(params, 'decay') ?? 0;
    final sustain = _doubleParam(params, 'sustain') ?? 0.8;
    final release = _doubleParam(params, 'release') ?? 0.1;
    final curve = _doubleParam(params, 'curve') ?? 1;
    final slide = _doubleParam(params, 'slide') ?? 0;
    final deltaSlide = _doubleParam(params, 'deltaSlide') ?? 0;
    final pitchJump = _doubleParam(params, 'pitchJump') ?? 0;
    final pitchJumpTime = _doubleParam(params, 'pitchJumpTime') ?? 0;
    final lfo = _doubleParam(params, 'lfo') ?? 0;
    final znoise = _doubleParam(params, 'znoise') ??
        _doubleParam(params, 'noise') ??
        0;
    final zmod = _doubleParam(params, 'zmod') ?? 0;
    final zcrush = _doubleParam(params, 'zcrush') ?? 0;
    final zdelay = _doubleParam(params, 'zdelay') ?? 0;
    final tremolo = _doubleParam(params, 'tremolo') ?? 0;

    final duration = _doubleParam(params, 'duration') ?? durationSeconds;
    final sustainTime = math.max(duration - attack - decay, 0).toDouble();

    var note = params['note'] ?? 36;
    final freqParam = params['freq'];
    double freq;
    if (freqParam is num) {
      freq = freqParam.toDouble();
    } else {
      if (note is String) {
        note = util.noteToMidi(note, defaultOctave: 3);
      }
      freq = util.midiToFreq(note is num ? note.toDouble() : 36);
    }

    final shapeNames = ['sine', 'triangle', 'sawtooth', 'tan', 'noise'];
    final shape = shapeNames.indexOf(sound);

    var shapeCurve = curve;
    if (sound == 'square') {
      shapeCurve = 0;
    }

    final zzfx = params['zzfx'];
    if (zzfx is List) {
      return buildSamplesFromList(zzfx);
    }

    return buildSamples(
      volume: 0.25,
      randomness: zrand,
      frequency: freq,
      attack: attack,
      sustain: sustainTime,
      release: release,
      shape: shape,
      shapeCurve: shapeCurve,
      slide: slide,
      deltaSlide: deltaSlide,
      pitchJump: pitchJump,
      pitchJumpTime: pitchJumpTime,
      repeatTime: lfo,
      noise: znoise,
      modulation: zmod,
      bitCrush: zcrush,
      delay: zdelay,
      sustainVolume: sustain,
      decay: decay,
      tremolo: tremolo,
    );
  }

  /// Low-level ZzFX algorithm (mono) used by Strudel.
  Float32List buildSamples({
    double volume = 1,
    double randomness = 0.05,
    double frequency = 220,
    double attack = 0,
    double sustain = 0,
    double release = 0.1,
    int shape = 0,
    double shapeCurve = 1,
    double slide = 0,
    double deltaSlide = 0,
    double pitchJump = 0,
    double pitchJumpTime = 0,
    double repeatTime = 0,
    double noise = 0,
    double modulation = 0,
    double bitCrush = 0,
    double delay = 0,
    double sustainVolume = 1,
    double decay = 0,
    double tremolo = 0,
  }) {
    final pi2 = math.pi * 2;
    final sr = sampleRate.toDouble();

    double sign(double value) => value > 0 ? 1 : -1;

    slide *= (500 * pi2) / sr / sr;
    final startSlide = slide;

    frequency *=
        ((1 + randomness * 2 * _random.nextDouble() - randomness) * pi2) /
            sr;
    final startFrequency = frequency;

    attack = attack * sr + 9;
    decay = decay * sr;
    sustain = sustain * sr;
    release = release * sr;
    delay = delay * sr;
    deltaSlide *= (500 * pi2) / math.pow(sr, 3).toDouble();
    modulation *= pi2 / sr;
    pitchJump *= pi2 / sr;
    pitchJumpTime *= sr;
    final repeatSamples = (repeatTime * sr).floor();

    final length = (attack + decay + sustain + release + delay).floor();
    final buffer = Float32List(length);

    var t = 0.0;
    var tm = 0.0;
    var j = 1;
    var r = 0;
    var c = 0;
    var s = 0.0;

    final crushSamples = (bitCrush * 100).floor();

    for (var i = 0; i < length; i++) {
      if (crushSamples == 0 || (++c % crushSamples == 0)) {
        if (shape != 0) {
          if (shape > 1) {
            if (shape > 2) {
              if (shape > 3) {
                s = math.sin(math.pow(t % pi2, 3).toDouble());
              } else {
                s = _clamp(math.tan(t), -1, 1);
              }
            } else {
              s = 1 - (((2 * t / pi2) % 2 + 2) % 2);
            }
          } else {
            s = 1 - 4 * (t / pi2 - (t / pi2).round()).abs();
          }
        } else {
          s = math.sin(t);
        }

        final trem = repeatSamples > 0
            ? 1 - tremolo + tremolo * math.sin((pi2 * i) / repeatSamples)
            : 1.0;

        final env = i < attack
            ? i / attack
            : i < attack + decay
                ? 1 - ((i - attack) / decay) * (1 - sustainVolume)
                : i < attack + decay + sustain
                    ? sustainVolume
                    : i < length - delay
                        ? ((length - i - delay) / release) * sustainVolume
                        : 0;

        s = trem *
            sign(s) *
            math.pow(s.abs(), shapeCurve).toDouble() *
            volume *
            env;

        if (delay > 0) {
          s = s / 2 +
              (delay > i
                  ? 0
                  : ((i < length - delay ? 1 : (length - i) / delay) *
                          buffer[(i - delay).floor()]) /
                      2);
        }
      }

      final mod = (frequency += slide += deltaSlide) *
          math.cos(modulation * tm++);
      t += mod - mod * noise * (1 - (((math.sin(i) + 1) * 1e9) % 2));

      if (j > 0 && ++j > pitchJumpTime) {
        frequency += pitchJump;
        j = 0;
      }

      if (repeatSamples > 0 && (++r % repeatSamples == 0)) {
        frequency = startFrequency;
        slide = startSlide;
        if (j == 0) j = 1;
      }

      buffer[i] = s;
    }

    return buffer;
  }

  /// Builds samples from a raw ZzFX parameter list.
  Float32List buildSamplesFromList(List<dynamic> params) {
    final list = params
        .map((entry) => entry is num ? entry.toDouble() : 0.0)
        .toList();
    while (list.length < 20) {
      list.add(0);
    }
    return buildSamples(
      volume: list[0],
      randomness: list[1],
      frequency: list[2],
      attack: list[3],
      sustain: list[4],
      release: list[5],
      shape: list[6].toInt(),
      shapeCurve: list[7],
      slide: list[8],
      deltaSlide: list[9],
      pitchJump: list[10],
      pitchJumpTime: list[11],
      repeatTime: list[12],
      noise: list[13],
      modulation: list[14],
      bitCrush: list[15],
      delay: list[16],
      sustainVolume: list[17],
      decay: list[18],
      tremolo: list[19],
    );
  }
}

double? _doubleParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double _clamp(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
