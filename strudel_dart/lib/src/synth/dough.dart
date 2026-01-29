import 'dart:math' as math;
import 'dart:typed_data';

import '../util.dart' as util;
import 'wavetable_registry.dart';

/// Lightweight DSP primitives for Strudel synth rendering.
///
/// Ported from `strudel/packages/supradough/dough.mjs`.
const double _defaultSampleRate = 48000.0;
final math.Random _random = math.Random();

const double _maxDelaySeconds = 10.0;
const double _twoPi = 2 * math.pi;

const Map<String, Object> _defaultValues = {
  'chorus': 0,
  'note': 48,
  's': 'triangle',
  'bank': '',
  'gain': 1,
  'postgain': 1,
  'velocity': 1,
  'density': '.03',
  'ftype': '12db',
  'fanchor': 0,
  'resonance': 0,
  'hresonance': 0,
  'bandq': 0,
  'channels': [1, 2],
  'phaserdepth': 0.75,
  'shapevol': 1,
  'distortvol': 1,
  'delay': 0,
  'byteBeatExpression': '0',
  'delayfeedback': 0.5,
  'delayspeed': 1,
  'delaytime': 0.25,
  'orbit': 1,
  'i': 1,
  'fft': 8,
  'z': 'triangle',
  'pan': 0.5,
  'fmh': 1,
  'fmenv': 0,
  'speed': 1,
  'pw': 0.5,
};

const Map<String, int> _warpModes = {
  'NONE': 0,
  'ASYM': 1,
  'MIRROR': 2,
  'BENDP': 3,
  'BENDM': 4,
  'BENDMP': 5,
  'SYNC': 6,
  'QUANT': 7,
  'FOLD': 8,
  'PWM': 9,
  'ORBIT': 10,
  'SPIN': 11,
  'CHAOS': 12,
  'PRIMES': 13,
  'BINARY': 14,
  'BROWNIAN': 15,
  'RECIPROCAL': 16,
  'WORMHOLE': 17,
  'LOGISTIC': 18,
  'SIGMOID': 19,
  'FRACTAL': 20,
  'FLIP': 21,
};

Object? _defaultValue(String key) => _defaultValues[key];

double _defaultDouble(String key, double fallback) {
  final value = _defaultValue(key);
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double _clamp(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

double _applyGainCurve(double value) => value * value;

double _frac(double value) => value - value.floorToDouble();
int _ffloor(double value) => value.floor();
int _fround(double value) => (value + 0.5).floor();

double _crossfade(double a, double b, double mix) {
  final aGain = math.sin((1 - mix) * 0.5 * math.pi);
  final bGain = math.sin(mix * 0.5 * math.pi);
  return (a * aGain) + (b * bGain);
}

double _polyBlep(double t, double dt) {
  if (t < dt) {
    final x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    final x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

double _lerp(double x, double y0, double y1, double exponent) {
  if (x <= 0) return y0;
  if (x >= 1) return y1;

  double curvedX;
  if (exponent == 0) {
    curvedX = x;
  } else if (exponent > 0) {
    curvedX = math.pow(x, exponent).toDouble();
  } else {
    curvedX = 1 - math.pow(1 - x, -exponent).toDouble();
  }
  return y0 + (y1 - y0) * curvedX;
}

int _hash32(int value) {
  var u = value & 0xFFFFFFFF;
  u = (u + 0x7ed55d16 + ((u << 12) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  u = (u ^ 0xc761c23c ^ (u >> 19)) & 0xFFFFFFFF;
  u = (u + 0x165667b1 + ((u << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  u = (u + 0xd3a2646c) ^ ((u << 9) & 0xFFFFFFFF);
  u = (u + 0xfd7046c5 + ((u << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  u = (u ^ 0xb55a4f09 ^ (u >> 16)) & 0xFFFFFFFF;
  return u & 0xFFFFFFFF;
}

double _hash01(int i) {
  return ((_hash32(i) >> 8) & 0x00FFFFFF) / 0x01000000;
}

int _bitReverse(int value, int bits) {
  var r = 0;
  var v = value;
  for (var b = 0; b < bits; b++) {
    r = (r << 1) | (v & 1);
    v >>= 1;
  }
  return r;
}

double _noise(double x) {
  final i = x.floor();
  final f = x - i;
  final a = _hash01(i);
  final b = _hash01(i + 1);
  return a + (b - a) * f;
}

double _brownian(double x, int octaves) {
  var amp = 0.5;
  var sum = 0.0;
  var norm = 0.0;
  var freq = 1.0;
  for (var o = 0; o < octaves; o++) {
    sum += amp * _noise(x * freq);
    norm += amp;
    amp *= 0.5;
    freq *= 2;
  }
  return (sum / norm) * 2 - 1;
}

List<double> _getAdsr(
  List<double?> params, {
  List<double>? defaultValues,
}) {
  const double envMin = 0.001;
  const double envMax = 1;
  const double releaseMin = 0.01;

  final attack = params.length > 0 ? params[0] : null;
  final decay = params.length > 1 ? params[1] : null;
  final sustain = params.length > 2 ? params[2] : null;
  final release = params.length > 3 ? params[3] : null;

  if (attack == null && decay == null && sustain == null && release == null) {
    return defaultValues ?? [envMin, envMin, envMax, releaseMin];
  }

  final sustainValue = sustain ??
      ((attack != null && decay == null) ||
              (attack == null && decay == null)
          ? envMax
          : envMin);

  return [
    math.max(attack ?? 0, envMin),
    math.max(decay ?? 0, envMin),
    math.min(sustainValue, envMax),
    math.max(release ?? 0, releaseMin),
  ];
}

double _noteToFreq([dynamic note]) {
  if (note == null) {
    return util.midiToFreq(48);
  }
  if (note is num) {
    return util.midiToFreq(note);
  }
  if (note is String) {
    return util.midiToFreq(util.noteToMidi(note, defaultOctave: 3));
  }
  return util.midiToFreq(48);
}

double _resolveFreq(Map<String, dynamic> params) {
  final freq = params['freq'];
  if (freq is num) return freq.toDouble();

  final note = params['note'];
  return _noteToFreq(note);
}

double? _doubleParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _intParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _stringParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value == null) return null;
  return value.toString();
}

List<double>? _doubleListParam(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! List) return null;
  final result = <double>[];
  for (final entry in value) {
    if (entry is num) {
      result.add(entry.toDouble());
      continue;
    }
    if (entry is String) {
      final parsed = double.tryParse(entry);
      if (parsed != null) {
        result.add(parsed);
      }
    }
  }
  return result.isEmpty ? null : result;
}

int _parseWarpMode(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) {
    final upper = value.trim().toUpperCase();
    return _warpModes[upper] ?? 0;
  }
  return 0;
}

String _parseLfoShape(dynamic value) {
  if (value == null) return 'sine';
  final text = value.toString().toLowerCase();
  switch (text) {
    case 'tri':
    case 'triangle':
      return 'tri';
    case 'saw':
    case 'sawtooth':
      return 'saw';
    case 'ramp':
      return 'ramp';
    case 'square':
      return 'square';
    default:
      return 'sine';
  }
}

class _SoundSelection {
  const _SoundSelection({required this.sound, required this.index});

  final String sound;
  final int? index;
}

_SoundSelection _parseSoundSelection(String sound) {
  final trimmed = sound.trim();
  final colonIndex = trimmed.lastIndexOf(':');
  if (colonIndex <= 0) {
    return _SoundSelection(sound: trimmed, index: null);
  }
  final base = trimmed.substring(0, colonIndex);
  final indexText = trimmed.substring(colonIndex + 1);
  final index = int.tryParse(indexText);
  return _SoundSelection(sound: base, index: index);
}

class _SineOsc {
  _SineOsc({double sampleRate = _defaultSampleRate})
      : _sampleRate = sampleRate;

  final double _sampleRate;
  double _phase = 0;

  double update(double freq) {
    final value = math.sin(_phase * 2 * math.pi);
    _phase = (_phase + (freq / _sampleRate)) % 1;
    return value;
  }
}

class _ZawOsc {
  _ZawOsc({double sampleRate = _defaultSampleRate})
      : _invSampleRate = 1 / sampleRate;

  final double _invSampleRate;
  double _phase = 0;

  double update(double freq) {
    _phase += _invSampleRate * freq;
    return (_phase % 1) * 2 - 1;
  }
}

class _SawOsc {
  _SawOsc({double sampleRate = _defaultSampleRate, double? phase})
      : _sampleRate = sampleRate,
        _phase = phase ?? 0;

  final double _sampleRate;
  double _phase;

  double update(double freq) {
    final dt = freq / _sampleRate;
    final p = _polyBlep(_phase, dt);
    final s = 2 * _phase - 1 - p;
    _phase += dt;
    if (_phase > 1) {
      _phase -= 1;
    }
    return s;
  }
}

double _getUnisonDetune(int unison, double detune, int voiceIndex) {
  if (unison < 2) return 0;
  final lerpValue = voiceIndex / (unison - 1);
  return lerpValue * (detune * 0.5) + (-detune * 0.5);
}

double _applySemitoneDetune(double frequency, double detune) {
  return frequency * math.pow(2, detune / 12).toDouble();
}

class _SupersawOsc {
  _SupersawOsc({
    double sampleRate = _defaultSampleRate,
    int voices = 5,
    double freqspread = 0.2,
    double panspread = 0.4,
  })  : _sampleRate = sampleRate,
        _voices = voices,
        _freqspread = freqspread,
        _panspread = panspread,
        _phases = List<double>.generate(
          voices,
          (_) => _random.nextDouble(),
        );

  final double _sampleRate;
  final int _voices;
  final double _freqspread;
  final double _panspread;
  final List<double> _phases;

  double update(double freq) {
    final gain1 = math.sqrt(1 - _panspread);
    final gain2 = math.sqrt(_panspread);
    var sl = 0.0;
    var sr = 0.0;
    for (var i = 0; i < _voices; i++) {
      final detuned = _applySemitoneDetune(
        freq,
        _getUnisonDetune(_voices, _freqspread, i),
      );
      final dt = detuned / _sampleRate;
      final isOdd = (i & 1) == 1;
      var gainL = gain1;
      var gainR = gain2;
      if (isOdd) {
        gainL = gain2;
        gainR = gain1;
      }
      final p = _polyBlep(_phases[i], dt);
      final s = 2 * _phases[i] - 1 - p;
      sl += s * gainL;
      sr += s * gainL;
      _phases[i] += dt;
      if (_phases[i] > 1) {
        _phases[i] -= 1;
      }
    }
    return sl + sr;
  }
}

class _TriOsc {
  _TriOsc({double sampleRate = _defaultSampleRate})
      : _invSampleRate = 1 / sampleRate;

  final double _invSampleRate;
  double _phase = 0;

  double update(double freq) {
    _phase += _invSampleRate * freq;
    final phase = _phase % 1;
    final value = phase < 0.5 ? 2 * phase : 1 - 2 * (phase - 0.5);
    return value * 2 - 1;
  }
}

class _PulseOsc {
  _PulseOsc({double sampleRate = _defaultSampleRate, double? phase})
      : _sampleRate = sampleRate,
        _phase = phase ?? 0;

  final double _sampleRate;
  double _phase;

  double _saw(double offset, double dt) {
    final phase = (_phase + offset) % 1;
    final p = _polyBlep(phase, dt);
    return 2 * phase - 1 - p;
  }

  double update(double freq, double pw) {
    final dt = freq / _sampleRate;
    final pulse = _saw(0, dt) - _saw(pw, dt);
    _phase = (_phase + dt) % 1;
    return pulse + pw * 2 - 1;
  }
}

class _PulzeOsc {
  _PulzeOsc({double sampleRate = _defaultSampleRate})
      : _invSampleRate = 1 / sampleRate;

  final double _invSampleRate;
  double _phase = 0;

  double update(double freq, double duty) {
    _phase += _invSampleRate * freq;
    final cyclePos = _phase % 1;
    return cyclePos < duty ? 1 : -1;
  }
}

class _Dust {
  _Dust({double sampleRate = _defaultSampleRate})
      : _invSampleRate = 1 / sampleRate;

  final double _invSampleRate;

  double update(double density) {
    return _random.nextDouble() < density * _invSampleRate
        ? _random.nextDouble()
        : 0;
  }
}

class _WhiteNoise {
  double update() => _random.nextDouble() * 2 - 1;
}

class _BrownNoise {
  double _out = 0;

  double update() {
    final white = _random.nextDouble() * 2 - 1;
    _out = (_out + 0.02 * white) / 1.02;
    return _out;
  }
}

class _PinkNoise {
  double _b0 = 0;
  double _b1 = 0;
  double _b2 = 0;
  double _b3 = 0;
  double _b4 = 0;
  double _b5 = 0;
  double _b6 = 0;

  double update() {
    final white = _random.nextDouble() * 2 - 1;
    _b0 = 0.99886 * _b0 + white * 0.0555179;
    _b1 = 0.99332 * _b1 + white * 0.0750759;
    _b2 = 0.969 * _b2 + white * 0.153852;
    _b3 = 0.8665 * _b3 + white * 0.3104856;
    _b4 = 0.55 * _b4 + white * 0.5329522;
    _b5 = -0.7616 * _b5 - white * 0.016898;

    final pink = _b0 +
        _b1 +
        _b2 +
        _b3 +
        _b4 +
        _b5 +
        _b6 +
        white * 0.5362;
    _b6 = white * 0.115926;
    return pink * 0.11;
  }
}

class _Impulse {
  _Impulse({double sampleRate = _defaultSampleRate})
      : _invSampleRate = 1 / sampleRate;

  final double _invSampleRate;
  double _phase = 1;

  double update(double freq) {
    _phase += _invSampleRate * freq;
    final value = _phase >= 1 ? 1.0 : 0.0;
    _phase = _phase % 1;
    return value;
  }
}

class _TwoPoleFilter {
  _TwoPoleFilter({double sampleRate = _defaultSampleRate})
      : _piDivSampleRate = math.pi / sampleRate,
        _sampleRate = sampleRate;

  final double _piDivSampleRate;
  final double _sampleRate;
  double s0 = 0;
  double s1 = 0;

  double update(double input, double cutoff, double resonance) {
    final safeRes = math.max(resonance, 0);
    final safeCutoff = math.min(cutoff, _sampleRate / 2 - 1);

    var c = 2 * math.sin(safeCutoff * _piDivSampleRate);
    c = _clamp(c, 0, 1.14);

    final r = math.pow(0.5, (safeRes + 0.125) / 0.125).toDouble();
    final mrc = 1 - r * c;

    s0 = mrc * s0 - c * s1 + c * input;
    s1 = mrc * s1 + c * s0;
    return s1;
  }
}

enum _AdsrState { off, attack, decay, sustain, release }

class _ADSR {
  _ADSR({this.decayCurve = 1});

  final double decayCurve;
  _AdsrState _state = _AdsrState.off;
  double _startTime = 0;
  double _startVal = 0;

  double update(
    double time,
    double gate,
    double attack,
    double decay,
    double sustain,
    double release,
  ) {
    switch (_state) {
      case _AdsrState.off:
        if (gate > 0) {
          _state = _AdsrState.attack;
          _startTime = time;
          _startVal = 0;
        }
        return 0;
      case _AdsrState.attack:
        if (attack <= 0) {
          _state = _AdsrState.decay;
          _startTime = time;
          return 1;
        }
        final elapsed = time - _startTime;
        if (elapsed > attack) {
          _state = _AdsrState.decay;
          _startTime = time;
          return 1;
        }
        return _lerp(elapsed / attack, _startVal, 1, 1);
      case _AdsrState.decay:
        if (decay <= 0) {
          _state = _AdsrState.sustain;
          _startTime = time;
          return sustain;
        }
        final elapsed = time - _startTime;
        final current = _lerp(elapsed / decay, 1, sustain, -decayCurve);
        if (gate <= 0) {
          _state = _AdsrState.release;
          _startTime = time;
          _startVal = current;
          return current;
        }
        if (elapsed > decay) {
          _state = _AdsrState.sustain;
          _startTime = time;
          return sustain;
        }
        return current;
      case _AdsrState.sustain:
        if (gate <= 0) {
          _state = _AdsrState.release;
          _startTime = time;
          _startVal = sustain;
        }
        return sustain;
      case _AdsrState.release:
        if (release <= 0) {
          _state = _AdsrState.off;
          return 0;
        }
        final elapsed = time - _startTime;
        if (elapsed > release) {
          _state = _AdsrState.off;
          return 0;
        }
        final current =
            _lerp(elapsed / release, _startVal, 0, -decayCurve);
        if (gate > 0) {
          _state = _AdsrState.attack;
          _startTime = time;
          _startVal = current;
        }
        return current;
    }
  }
}

class _Delay {
  _Delay({double sampleRate = _defaultSampleRate})
      : _buffer = Float32List((sampleRate * _maxDelaySeconds).floor());

  final Float32List _buffer;
  int _writeIdx = 0;
  int _readIdx = 0;

  void write(double input, double delayTime, double sampleRate) {
    _writeIdx = (_writeIdx + 1) % _buffer.length;
    _buffer[_writeIdx] = input.toDouble();

    final numSamples = math.min(
      (sampleRate * delayTime).floor(),
      _buffer.length - 1,
    );
    _readIdx = _writeIdx - numSamples;
    if (_readIdx < 0) _readIdx += _buffer.length;
  }

  double update(double input, double delayTime, double sampleRate) {
    write(input, delayTime, sampleRate);
    return _buffer[_readIdx];
  }
}

class _Chorus {
  _Chorus({double sampleRate = _defaultSampleRate})
      : _delay = _Delay(sampleRate: sampleRate),
        _modulator = _TriOsc(sampleRate: sampleRate);

  final _Delay _delay;
  final _TriOsc _modulator;

  double update(
    double input,
    double mix,
    double delayTime,
    double modulationFreq,
    double modulationDepth,
    double sampleRate,
  ) {
    final m = _modulator.update(modulationFreq) * modulationDepth;
    final c = _delay.update(input, delayTime * (1 + m), sampleRate);
    return _crossfade(input, c, mix);
  }
}

class _Coarse {
  double _hold = 0;
  int _t = 0;

  double update(double input, int coarse) {
    if (_t++ % coarse == 0) {
      _t = 0;
      _hold = input;
    }
    return _hold;
  }
}

class _Crush {
  double update(double input, int crush) {
    final safeCrush = math.max(1, crush);
    final x = math.pow(2, safeCrush - 1).toDouble();
    return (input * x).roundToDouble() / x;
  }
}

class _Distort {
  double update(double input, double distort, double postgain) {
    final safePost = _clamp(postgain, 0.001, 1);
    final shape = math.exp(distort) - 1;
    return (((1 + shape) * input) / (1 + shape * input.abs())) * safePost;
  }
}

class _BufferSample {
  _BufferSample(this.channels, this.sampleRate);

  final List<Float32List> channels;
  final int sampleRate;
}

class _BufferPlayer {
  _BufferPlayer(
    this.buffer,
    this.sampleRate,
    this.normalize, {
    required double engineSampleRate,
  })  : _engineSampleRate = engineSampleRate,
        _sampleFreq = _noteToFreq();

  static final Map<String, _BufferSample> samples = {};

  final Float32List buffer;
  final int sampleRate;
  final bool normalize;
  final double _engineSampleRate;
  final double _sampleFreq;

  double _pos = 0;

  double update(double freq) {
    if (_pos >= buffer.length) return 0;

    final duration = buffer.length / sampleRate;
    var speed = _engineSampleRate / sampleRate;
    if (normalize) {
      speed *= duration;
    }

    final target = (freq / _sampleFreq) * speed;
    final value = buffer[_pos.floor()];
    _pos = _pos + target;
    return value;
  }
}

class _WavetableOsc {
  _WavetableOsc(this.table, {double sampleRate = _defaultSampleRate})
      : _sampleRate = sampleRate;

  final Float32List table;
  final double _sampleRate;
  double _phase = 0;

  double update(double freq) {
    final index = _phase * table.length;
    final i0 = index.floor() % table.length;
    final i1 = (i0 + 1) % table.length;
    final frac = index - i0;
    final value = table[i0] + (table[i1] - table[i0]) * frac;
    _phase = (_phase + (freq / _sampleRate)) % 1;
    return value;
  }
}

class _Lfo {
  _Lfo({required double sampleRate, required String shape})
      : _sampleRate = sampleRate,
        _shape = shape;

  final double _sampleRate;
  final String _shape;
  double _phase = 0;

  double update(double frequency, double skew) {
    final safeSkew = _clamp(skew, 0.01, 0.99);
    double value;
    switch (_shape) {
      case 'tri':
        final x = 1 - safeSkew;
        if (_phase >= safeSkew) {
          value = 1 / x - _phase / x;
        } else {
          value = _phase / safeSkew;
        }
        break;
      case 'saw':
        value = 1 - _phase;
        break;
      case 'ramp':
        value = _phase;
        break;
      case 'square':
        value = _phase >= safeSkew ? 0 : 1;
        break;
      case 'sine':
      default:
        value = math.sin(_twoPi * _phase) * 0.5 + 0.5;
        break;
    }
    if (frequency > 0) {
      _phase = (_phase + (frequency / _sampleRate)) % 1;
    }
    return value;
  }
}

class _WavetableSource {
  _WavetableSource(
    this.frames, {
    required double sampleRate,
  })  : _sampleRate = sampleRate,
        _numFrames = frames.length;

  final List<Float32List> frames;
  final double _sampleRate;
  final int _numFrames;
  final List<double> _phases = [];
  final List<double> _out = [0, 0];

  List<double> update({
    required double frequency,
    required double freqSpread,
    required double position,
    required double warp,
    required int warpMode,
    required int voices,
    required double panSpread,
    required double phaseRand,
  }) {
    final voiceCount = voices < 1 ? 1 : voices;
    final tablePos = _clamp(position, 0, 1);
    final idx = tablePos * (_numFrames - 1);
    final fIdx = idx.floor();
    final interpT = idx - fIdx;
    final warpAmount = _clamp(warp, 0, 1);
    final pan = voiceCount > 1 ? _clamp(panSpread, 0, 1) : 0;
    final gain1 = math.sqrt(0.5 - 0.5 * pan);
    final gain2 = math.sqrt(0.5 + 0.5 * pan);
    final normalizer = 1 / math.sqrt(voiceCount);
    final lastFrame = math.max(0, _numFrames - 1);

    _out[0] = 0;
    _out[1] = 0;

    for (var n = 0; n < voiceCount; n++) {
      if (_phases.length <= n) {
        _phases.add(_random.nextDouble() * phaseRand);
      }
      final phase = _warpPhase(_phases[n], warpAmount, warpMode);
      final s0 = _sampleFrame(frames[fIdx], phase);
      final s1 = _sampleFrame(frames[math.min(lastFrame, fIdx + 1)], phase);
      var sample = s0 + (s1 - s0) * interpT;
      if (warpMode == _warpModes['FLIP'] && _phases[n] < warpAmount) {
        sample = -sample;
      }

      final detune = _getUnisonDetune(voiceCount, freqSpread, n);
      final voiceFreq = _applySemitoneDetune(frequency, detune);
      final dPhase = voiceFreq / _sampleRate;

      final isOdd = (n & 1) == 1;
      var gainL = gain1;
      var gainR = gain2;
      if (isOdd) {
        gainL = gain2;
        gainR = gain1;
      }

      _out[0] += sample * gainL * normalizer;
      _out[1] += sample * gainR * normalizer;

      _phases[n] = _frac(_phases[n] + dPhase);
    }

    return _out;
  }

  double _sampleFrame(Float32List frame, double phase) {
    final len = frame.length;
    final pos = phase * len;
    var i = pos.floor();
    if (i >= len) i = 0;
    final frac = pos - i;
    final a = frame[i];
    var i1 = i + 1;
    if (i1 >= len) i1 = 0;
    final b = frame[i1];
    return a + (b - a) * frac;
  }

  double _warpPhase(double phase, double amt, int mode) {
    switch (mode) {
      case 0: // NONE
        return phase;
      case 1: // ASYM
        final a = 0.01 + 0.99 * amt;
        return phase < a
            ? (0.5 * phase) / a
            : 0.5 + (0.5 * (phase - a)) / (1 - a);
      case 2: // MIRROR
        return _mirror(_warpPhase(phase, amt, 1));
      case 3: // BENDP
        return math.pow(phase, 1 + 3 * amt).toDouble();
      case 4: // BENDM
        return math.pow(phase, 1 / (1 + 3 * amt)).toDouble();
      case 5: // BENDMP
        return amt < 0.5
            ? _warpPhase(phase, 1 - 2 * amt, 3)
            : _warpPhase(phase, 2 * amt - 1, 2);
      case 6: // SYNC
        final syncRatio = math.pow(16, amt * amt).toDouble();
        return (phase * syncRatio) % 1;
      case 7: // QUANT
        final bits = _toBits(amt, 2, 12);
        return _ffloor(phase * bits.n) / bits.n;
      case 8: // FOLD
        const kMax = 7;
        final k = 1 + math.max(1, _fround(kMax * amt));
        return (_frac(k * phase) - 0.5).abs() * 2;
      case 9: // PWM
        final w = _clamp(0.5 + 0.49 * (2 * amt - 1), 0, 1);
        if (phase < w) return (phase / w) * 0.5;
        return 0.5 + ((phase - w) / (1 - w)) * 0.5;
      case 10: // ORBIT
        final depth = 0.5 * amt;
        const n = 3;
        return _frac(phase + depth * math.sin(_twoPi * n * phase));
      case 11: // SPIN
        final depth = 0.5 * amt;
        final bits = _toBits(amt, 1, 6);
        return _frac(phase + depth * math.sin(_twoPi * bits.n * phase));
      case 12: // CHAOS
        final r = 3.7 + 0.3 * amt;
        final logistic = r * phase * (1 - phase);
        return _clamp((1 - amt) * phase + amt * logistic, 0, 1);
      case 13: // PRIMES
        var bits = _toBits(amt, 3, 12).n;
        while (!_isPrime(bits)) {
          bits += 1;
        }
        return _ffloor(phase * bits) / bits;
      case 14: // BINARY
        var bits = _toBits(amt, 3, 12).b;
        final b = _fround(bits);
        final n = 1 << b;
        final idx = _ffloor(phase * n);
        final ridx = _bitReverse(idx, b);
        return ridx / n;
      case 15: // BROWNIAN
        final disp = 0.25 * amt * _brownian(64 * phase, 4);
        return _frac(phase + disp);
      case 16: // RECIPROCAL
        final g = 2.0 + 4.0 * amt;
        final num = phase * g;
        final den = phase + (1 - phase) * g;
        final y = den > 1e-12 ? num / den : 0.0;
        return _clamp(y, 0, 1);
      case 17: // WORMHOLE
        final gap = _clamp(0.8 * amt, 0, 1);
        final a = 0.5 * (1 - gap);
        final b = 0.5 * (1 + gap);
        if (phase < a) return (phase / a) * 0.5;
        if (phase > b) return 0.5 * (1 + (phase - b) / (1 - b));
        return 0.5;
      case 18: // LOGISTIC
        var x = phase;
        final r = 3.6 + 0.4 * amt;
        final iters = 1 + _fround(2 * amt);
        for (var i = 0; i < iters; i++) {
          x = r * x * (1 - x);
        }
        return _clamp(x, 0, 1);
      case 19: // SIGMOID
        final k = 1 + 10 * amt;
        final x = phase - 0.5;
        final y = 1 / (1 + math.exp(-k * x));
        final y0 = 1 / (1 + math.exp(0.5 * k));
        final y1 = 1 / (1 + math.exp(-0.5 * k));
        return (y - y0) / (y1 - y0);
      case 20: // FRACTAL
        final d = 0.5 * math.sin(_twoPi * phase) * amt;
        return _frac(phase + d);
      case 21: // FLIP
        return phase;
      default:
        return phase;
    }
  }

  double _mirror(double x) {
    return 1 - (2 * x - 1).abs();
  }

  _Bits _toBits(double amt, int min, int max) {
    final b = max + (min - max) * amt;
    final n = _fround(math.pow(2, b).toDouble());
    return _Bits(b: b, n: n);
  }

  bool _isPrime(int n) {
    if (n < 2) return false;
    if (n % 2 == 0) return n == 2;
    var d = 3;
    while (d * d <= n) {
      if (n % d == 0) return false;
      d += 2;
    }
    return true;
  }
}

class _Bits {
  const _Bits({required this.b, required this.n});

  final double b;
  final int n;
}

Float32List _buildPartialTable(
  List<double> partials,
  List<double>? phases,
  int size,
) {
  final table = Float32List(size);
  var maxAbs = 0.0;

  for (var i = 0; i < size; i++) {
    final phase = i / size;
    var sum = 0.0;
    for (var h = 0; h < partials.length; h++) {
      final amp = partials[h];
      if (amp == 0) continue;
      final phaseOffset =
          phases != null && h < phases.length ? phases[h] : 0.0;
      final radians = 2 * math.pi * ((h + 1) * phase + phaseOffset);
      sum += amp * math.sin(radians);
    }
    table[i] = sum;
    maxAbs = math.max(maxAbs, sum.abs());
  }

  if (maxAbs > 0) {
    for (var i = 0; i < table.length; i++) {
      table[i] = (table[i] / maxAbs).toDouble();
    }
  }

  return table;
}

class _DoughVoice {
  _DoughVoice.fromMap(
    Map<String, dynamic> params, {
    required double sampleRate,
  })  : _sampleRate = sampleRate,
        out = Float32List(2) {
    _begin = _doubleParam(params, '_begin') ?? 0;
    _duration = _doubleParam(params, '_duration') ?? 0;

    freq = _resolveFreq(params);
    note = _stringParam(params, 'note');

    n = _intParam(params, 'n') ?? 0;

    final rawSound =
        _stringParam(params, 's') ?? _defaultValue('s')?.toString() ?? 'triangle';
    final selection = _parseSoundSelection(rawSound.toLowerCase());
    s = selection.sound;
    if (selection.index != null && n == 0) {
      n = selection.index!;
    }

    gain = _applyGainCurve(
      _doubleParam(params, 'gain') ?? _defaultDouble('gain', 1),
    );
    velocity = _applyGainCurve(
      _doubleParam(params, 'velocity') ?? _defaultDouble('velocity', 1),
    );
    postgain = _applyGainCurve(
      _doubleParam(params, 'postgain') ?? _defaultDouble('postgain', 1),
    );
    shapevol = _applyGainCurve(
      _doubleParam(params, 'shapevol') ?? _defaultDouble('shapevol', 1),
    );
    distortvol = _applyGainCurve(
      _doubleParam(params, 'distortvol') ?? _defaultDouble('distortvol', 1),
    );

    density = _doubleParam(params, 'density') ??
        _defaultDouble('density', 0.03);
    fanchor = _doubleParam(params, 'fanchor') ??
        _defaultDouble('fanchor', 0);
    drive = _doubleParam(params, 'drive') ?? 0.69;
    phaserdepth = _doubleParam(params, 'phaserdepth') ??
        _defaultDouble('phaserdepth', 0.75);
    i = _doubleParam(params, 'i') ?? _defaultDouble('i', 1);
    chorus = _doubleParam(params, 'chorus') ?? _defaultDouble('chorus', 0);
    fft = _doubleParam(params, 'fft') ?? _defaultDouble('fft', 8);
    pan = _doubleParam(params, 'pan') ?? _defaultDouble('pan', 0.5);
    orbit = _doubleParam(params, 'orbit') ?? _defaultDouble('orbit', 1);
    fmenv = _doubleParam(params, 'fmenv') ?? _defaultDouble('fmenv', 0);
    resonance =
        _doubleParam(params, 'resonance') ?? _defaultDouble('resonance', 0);
    hresonance = _doubleParam(params, 'hresonance') ??
        _defaultDouble('hresonance', 0);
    bandq = _doubleParam(params, 'bandq') ?? _defaultDouble('bandq', 0);
    speed = _doubleParam(params, 'speed') ?? _defaultDouble('speed', 1);
    pw = _doubleParam(params, 'pw') ?? _defaultDouble('pw', 0.5);

    cutoff = _doubleParam(params, 'cutoff');
    hcutoff = _doubleParam(params, 'hcutoff');
    bandf = _doubleParam(params, 'bandf');
    coarse = _intParam(params, 'coarse');
    crush = _intParam(params, 'crush');
    distort = _doubleParam(params, 'distort');
    noise = _doubleParam(params, 'noise');
    attack = _doubleParam(params, 'attack');
    decay = _doubleParam(params, 'decay');
    sustain = _doubleParam(params, 'sustain');
    release = _doubleParam(params, 'release') ?? 0;

    penv = _doubleParam(params, 'penv');
    pattack = _doubleParam(params, 'pattack');
    pdecay = _doubleParam(params, 'pdecay');
    psustain = _doubleParam(params, 'psustain');
    prelease = _doubleParam(params, 'prelease');

    vib = _doubleParam(params, 'vib');
    vibmod = _doubleParam(params, 'vibmod');

    fmh = _doubleParam(params, 'fmh');
    fmi = _doubleParam(params, 'fmi');
    fmattack = _doubleParam(params, 'fmattack');
    fmdecay = _doubleParam(params, 'fmdecay');
    fmsustain = _doubleParam(params, 'fmsustain');
    fmrelease = _doubleParam(params, 'fmrelease');

    lpenv = _doubleParam(params, 'lpenv');
    lpattack = _doubleParam(params, 'lpattack');
    lpdecay = _doubleParam(params, 'lpdecay');
    lpsustain = _doubleParam(params, 'lpsustain');
    lprelease = _doubleParam(params, 'lprelease');

    hpenv = _doubleParam(params, 'hpenv');
    hpattack = _doubleParam(params, 'hpattack');
    hpdecay = _doubleParam(params, 'hpdecay');
    hpsustain = _doubleParam(params, 'hpsustain');
    hprelease = _doubleParam(params, 'hprelease');

    bpenv = _doubleParam(params, 'bpenv');
    bpattack = _doubleParam(params, 'bpattack');
    bpdecay = _doubleParam(params, 'bpdecay');
    bpsustain = _doubleParam(params, 'bpsustain');
    bprelease = _doubleParam(params, 'bprelease');

    wt = _doubleParam(params, 'wt');
    wtenv = _doubleParam(params, 'wtenv');
    wtattack = _doubleParam(params, 'wtattack');
    wtdecay = _doubleParam(params, 'wtdecay');
    wtsustain = _doubleParam(params, 'wtsustain');
    wtrelease = _doubleParam(params, 'wtrelease');
    wtrate = _doubleParam(params, 'wtrate');
    wtsync = _doubleParam(params, 'wtsync');
    wtdepth = _doubleParam(params, 'wtdepth');
    wtdc = _doubleParam(params, 'wtdc');
    wtskew = _doubleParam(params, 'wtskew');
    wtshape = _parseLfoShape(params['wtshape']);

    final wtPhaseParam = params['wtphaserand'];
    if (wtPhaseParam is bool) {
      wtphaserand = wtPhaseParam ? 1 : 0;
    } else {
      wtphaserand = _doubleParam(params, 'wtphaserand');
    }

    warp = _doubleParam(params, 'warp');
    warpenv = _doubleParam(params, 'warpenv');
    warpattack = _doubleParam(params, 'warpattack');
    warpdecay = _doubleParam(params, 'warpdecay');
    warpsustain = _doubleParam(params, 'warpsustain');
    warprelease = _doubleParam(params, 'warprelease');
    warprate = _doubleParam(params, 'warprate');
    warpsync = _doubleParam(params, 'warpsync');
    warpdepth = _doubleParam(params, 'warpdepth');
    warpdc = _doubleParam(params, 'warpdc');
    warpskew = _doubleParam(params, 'warpskew');
    warpshape = _parseLfoShape(params['warpshape']);
    warpmode = _parseWarpMode(params['warpmode']);

    unison = _intParam(params, 'unison') ?? 1;
    detune =
        _doubleParam(params, 'detune') ?? _doubleParam(params, 'freqspread') ?? 0;
    spread =
        _doubleParam(params, 'spread') ?? _doubleParam(params, 'panspread') ?? 0;

    final adsr = _getAdsr([attack, decay, sustain, release]);
    attack = adsr[0];
    decay = adsr[1];
    sustain = adsr[2];
    release = adsr[3];

    _holdEnd = _begin + _duration;
    _end = _holdEnd + release + 0.01;

    if (fmi != null && (s == 'saw' || s == 'sawtooth')) {
      s = 'zaw';
    }

    final partials = _doubleListParam(params, 'partials');
    final phases = _doubleListParam(params, 'phases');
    if (partials != null) {
      final table = _buildPartialTable(partials, phases, 2048);
      _sound = _WavetableOsc(table, sampleRate: sampleRate);
      _channels = 1;
    } else {
      _initSound(params);
    }

    final cps = _doubleParam(params, 'cps');
    _wtBase = wt ?? 0;
    _warpBase = warp ?? 0;
    _warpMode = warpmode;

    final hasWtEnvParams = wtattack != null ||
        wtdecay != null ||
        wtsustain != null ||
        wtrelease != null;
    _wtEnvAmount = wtenv ?? (hasWtEnvParams ? 0.5 : 0);
    if (_wtEnvAmount != 0) {
      _wtEnv = _ADSR(decayCurve: 1);
      final wtValues = _getAdsr(
        [wtattack, wtdecay, wtsustain, wtrelease],
        defaultValues: [0, 0.5, 0, 0.1],
      );
      wtattack = wtValues[0];
      wtdecay = wtValues[1];
      wtsustain = wtValues[2];
      wtrelease = wtValues[3];
    }

    final hasWarpEnvParams = warpattack != null ||
        warpdecay != null ||
        warpsustain != null ||
        warprelease != null;
    _warpEnvAmount = warpenv ?? (hasWarpEnvParams ? 0.5 : 0);
    if (_warpEnvAmount != 0) {
      _warpEnv = _ADSR(decayCurve: 1);
      final warpValues = _getAdsr(
        [warpattack, warpdecay, warpsustain, warprelease],
        defaultValues: [0, 0.5, 0, 0.1],
      );
      warpattack = warpValues[0];
      warpdecay = warpValues[1];
      warpsustain = warpValues[2];
      warprelease = warpValues[3];
    }

    final hasWtLfoParams =
        wtrate != null ||
        wtsync != null ||
        wtdepth != null ||
        wtskew != null ||
        wtdc != null ||
        params['wtshape'] != null;
    _wtLfoDepth = wtdepth ?? (hasWtLfoParams ? 0.5 : 0);
    _wtLfoRate = wtrate ?? 0;
    if (wtsync != null) {
      _wtLfoRate = cps != null ? cps * wtsync! : _wtLfoRate;
    }
    _wtLfoSkew = wtskew ?? 0.5;
    _wtLfoDc = wtdc ?? 0;
    if (_wtLfoDepth != 0) {
      _wtLfo = _Lfo(sampleRate: sampleRate, shape: wtshape);
    }

    final hasWarpLfoParams =
        warprate != null ||
        warpsync != null ||
        warpdepth != null ||
        warpskew != null ||
        warpdc != null ||
        params['warpshape'] != null;
    _warpLfoDepth = warpdepth ?? (hasWarpLfoParams ? 0.5 : 0);
    _warpLfoRate = warprate ?? 0;
    if (warpsync != null) {
      _warpLfoRate = cps != null ? cps * warpsync! : _warpLfoRate;
    }
    _warpLfoSkew = warpskew ?? 0.5;
    _warpLfoDc = warpdc ?? 0;
    if (_warpLfoDepth != 0) {
      _warpLfo = _Lfo(sampleRate: sampleRate, shape: warpshape);
    }

    _wtVoices = unison < 1 ? 1 : unison;
    _wtFreqSpread = detune;
    _wtPanSpread = spread;
    final hasPhaseRand =
        (wtphaserand != null && wtphaserand! > 0) || _wtVoices > 1;
    _wtPhaseRand = hasPhaseRand ? 1 : 0;

    if (penv != null) {
      _penv = _ADSR(decayCurve: 4);
      final penvValues = _getAdsr([pattack, pdecay, psustain, prelease]);
      pattack = penvValues[0];
      pdecay = penvValues[1];
      psustain = penvValues[2];
      prelease = penvValues[3];
    }

    if (vib != null) {
      _vib = _SineOsc(sampleRate: sampleRate);
    }

    if (fmi != null) {
      _fm = _SineOsc(sampleRate: sampleRate);
      fmh ??= _defaultDouble('fmh', 1);
      if (fmenv != null && fmenv != 0) {
        _fmenv = _ADSR(decayCurve: 2);
        final fmenvValues =
            _getAdsr([fmattack, fmdecay, fmsustain, fmrelease]);
        fmattack = fmenvValues[0];
        fmdecay = fmenvValues[1];
        fmsustain = fmenvValues[2];
        fmrelease = fmenvValues[3];
      }
    }

    _adsr = _ADSR(decayCurve: 2);

    delay = _applyGainCurve(
      _doubleParam(params, 'delay') ?? _defaultDouble('delay', 0),
    );
    delayfeedback = _doubleParam(params, 'delayfeedback') ??
        _defaultDouble('delayfeedback', 0.5);
    delayspeed =
        _doubleParam(params, 'delayspeed') ?? _defaultDouble('delayspeed', 1);
    delaytime =
        _doubleParam(params, 'delaytime') ?? _defaultDouble('delaytime', 0.25);

    if (lpenv != null) {
      _lpenv = _ADSR(decayCurve: 4);
      final lpenvValues =
          _getAdsr([lpattack, lpdecay, lpsustain, lprelease]);
      lpattack = lpenvValues[0];
      lpdecay = lpenvValues[1];
      lpsustain = lpenvValues[2];
      lprelease = lpenvValues[3];
    }

    if (hpenv != null) {
      _hpenv = _ADSR(decayCurve: 4);
      final hpenvValues =
          _getAdsr([hpattack, hpdecay, hpsustain, hprelease]);
      hpattack = hpenvValues[0];
      hpdecay = hpenvValues[1];
      hpsustain = hpenvValues[2];
      hprelease = hpenvValues[3];
    }

    if (bpenv != null) {
      _bpenv = _ADSR(decayCurve: 4);
      final bpenvValues =
          _getAdsr([bpattack, bpdecay, bpsustain, bprelease]);
      bpattack = bpenvValues[0];
      bpdecay = bpenvValues[1];
      bpsustain = bpenvValues[2];
      bprelease = bpenvValues[3];
    }

    _chorus = chorus != null && chorus! > 0 ? [] : null;
    _lpf = cutoff != null ? [] : null;
    _hpf = hcutoff != null ? [] : null;
    _bpf = bandf != null ? [] : null;
    _coarse = coarse != null ? [] : null;
    _crush = crush != null ? [] : null;
    _distort = distort != null ? [] : null;

    for (var i = 0; i < _channels; i++) {
      _lpf?.add(_TwoPoleFilter(sampleRate: sampleRate));
      _hpf?.add(_TwoPoleFilter(sampleRate: sampleRate));
      _bpf?.add(_TwoPoleFilter(sampleRate: sampleRate));
      _chorus?.add(_Chorus(sampleRate: sampleRate));
      _coarse?.add(_Coarse());
      _crush?.add(_Crush());
      _distort?.add(_Distort());
    }

    if (noise != null && noise! > 0) {
      _noise = _PinkNoise();
    }
  }

  int id = 0;
  final Float32List out;

  double? attack;
  double? decay;
  double? sustain;
  double release = 0;

  double _begin = 0;
  double _duration = 0;
  double _holdEnd = 0;
  double _end = 0;

  String? note;
  int n = 0;
  late double freq;

  String s = 'triangle';
  double gain = 1;
  double velocity = 1;
  double postgain = 1;
  double shapevol = 1;
  double distortvol = 1;
  double density = 0.03;
  double fanchor = 0;
  double drive = 0.69;
  double phaserdepth = 0.75;
  double i = 1;
  double chorus = 0;
  double fft = 8;
  double pan = 0.5;
  double orbit = 1;
  double fmenv = 0;
  double resonance = 0;
  double hresonance = 0;
  double bandq = 0;
  double speed = 1;
  double pw = 0.5;

  double? cutoff;
  double? hcutoff;
  double? bandf;
  int? coarse;
  int? crush;
  double? distort;
  double? noise;

  double? penv;
  double? pattack;
  double? pdecay;
  double? psustain;
  double? prelease;

  double? vib;
  double? vibmod;

  double? fmh;
  double? fmi;
  double? fmattack;
  double? fmdecay;
  double? fmsustain;
  double? fmrelease;

  double? lpenv;
  double? lpattack;
  double? lpdecay;
  double? lpsustain;
  double? lprelease;

  double? hpenv;
  double? hpattack;
  double? hpdecay;
  double? hpsustain;
  double? hprelease;

  double? bpenv;
  double? bpattack;
  double? bpdecay;
  double? bpsustain;
  double? bprelease;

  double? wt;
  double? wtenv;
  double? wtattack;
  double? wtdecay;
  double? wtsustain;
  double? wtrelease;
  double? wtrate;
  double? wtsync;
  double? wtdepth;
  double? wtdc;
  double? wtskew;
  double? wtphaserand;
  String wtshape = 'sine';

  double? warp;
  double? warpenv;
  double? warpattack;
  double? warpdecay;
  double? warpsustain;
  double? warprelease;
  double? warprate;
  double? warpsync;
  double? warpdepth;
  double? warpdc;
  double? warpskew;
  String warpshape = 'sine';
  int warpmode = 0;

  int unison = 1;
  double detune = 0;
  double spread = 0;

  double delay = 0;
  double delayfeedback = 0.5;
  double delayspeed = 1;
  double delaytime = 0.25;

  final double _sampleRate;

  double _wtBase = 0;
  double _warpBase = 0;
  double _wtEnvAmount = 0;
  double _warpEnvAmount = 0;
  double _wtLfoDepth = 0;
  double _warpLfoDepth = 0;
  double _wtLfoRate = 0;
  double _warpLfoRate = 0;
  double _wtLfoSkew = 0.5;
  double _warpLfoSkew = 0.5;
  double _wtLfoDc = 0;
  double _warpLfoDc = 0;
  int _wtVoices = 1;
  double _wtFreqSpread = 0;
  double _wtPanSpread = 0;
  double _wtPhaseRand = 0;
  int _warpMode = 0;

  int _channels = 1;

  dynamic _sound;
  List<_BufferPlayer>? _buffers;
  _ADSR? _adsr;
  _ADSR? _penv;
  _ADSR? _fmenv;
  _ADSR? _lpenv;
  _ADSR? _hpenv;
  _ADSR? _bpenv;
  _ADSR? _wtEnv;
  _ADSR? _warpEnv;
  _SineOsc? _vib;
  _SineOsc? _fm;
  _Lfo? _wtLfo;
  _Lfo? _warpLfo;

  List<_TwoPoleFilter>? _lpf;
  List<_TwoPoleFilter>? _hpf;
  List<_TwoPoleFilter>? _bpf;
  List<_Chorus>? _chorus;
  List<_Coarse>? _coarse;
  List<_Crush>? _crush;
  List<_Distort>? _distort;

  _PinkNoise? _noise;

  double get end => _end;

  void _initSound(Map<String, dynamic> params) {
    final soundKey = s.toLowerCase();
    final wavetableDef = WavetableRegistry.definition(soundKey);
    if (wavetableDef != null) {
      final tableIndex = wavetableDef.urls.isEmpty
          ? 0
          : n % wavetableDef.urls.length;
      final tableData = WavetableRegistry.table(soundKey, tableIndex);
      if (tableData != null) {
        _sound = _WavetableSource(
          tableData.frames,
          sampleRate: _sampleRate,
        );
        _channels = 2;
      }
      return;
    }

    final directTable = WavetableRegistry.table(soundKey, n);
    if (directTable != null) {
      _sound = _WavetableSource(
        directTable.frames,
        sampleRate: _sampleRate,
      );
      _channels = 2;
      return;
    }

    if (soundKey.startsWith('wt_')) {
      return;
    }

    final factory = _shapeFactories[soundKey];
    if (factory != null) {
      _sound = factory(_sampleRate);
      _channels = 1;
      return;
    }

    final sample = _BufferPlayer.samples[soundKey];
    if (sample != null) {
      _buffers = [];
      _channels = sample.channels.length;
      final normalize = params['unit'] == 'c';
      for (var i = 0; i < _channels; i++) {
        _buffers!.add(
          _BufferPlayer(
            sample.channels[i],
            sample.sampleRate,
            normalize,
            engineSampleRate: _sampleRate,
          ),
        );
      }
      return;
    }
  }

  void update(double time) {
    if (_sound == null && _buffers == null) {
      out[0] = 0;
      out[1] = 0;
      return;
    }

    final gate = (time >= _begin && time <= _holdEnd) ? 1.0 : 0.0;

    var currentFreq = freq * speed;

    if (_fm != null && fmh != null && fmi != null) {
      var modIndex = fmi!;
      if (_fmenv != null) {
        final env = _fmenv!.update(
          time,
          gate,
          fmattack ?? 0,
          fmdecay ?? 0,
          fmsustain ?? 0,
          fmrelease ?? 0,
        );
        modIndex = fmenv * env * modIndex;
      }
      final modFreq = currentFreq * fmh!;
      final modGain = modFreq * modIndex;
      currentFreq = currentFreq + _fm!.update(modFreq) * modGain;
    }

    if (_vib != null && vib != null && vibmod != null) {
      currentFreq = currentFreq *
          math.pow(
            2,
            (_vib!.update(vib!) * vibmod!) / 12,
          )
              .toDouble();
    }

    if (_penv != null && penv != null) {
      final env = _penv!.update(
        time,
        gate,
        pattack ?? 0,
        pdecay ?? 0,
        psustain ?? 0,
        prelease ?? 0,
      );
      currentFreq = currentFreq + env * penv!;
    }

    var lpfValue = cutoff;
    if (lpfValue != null && _lpenv != null) {
      final env = _lpenv!.update(
        time,
        gate,
        lpattack ?? 0,
        lpdecay ?? 0,
        lpsustain ?? 0,
        lprelease ?? 0,
      );
      lpfValue = lpenv! * env * lpfValue + lpfValue;
    }

    var hpfValue = hcutoff;
    if (hpfValue != null && _hpenv != null && hpenv != null) {
      final env = _hpenv!.update(
        time,
        gate,
        hpattack ?? 0,
        hpdecay ?? 0,
        hpsustain ?? 0,
        hprelease ?? 0,
      );
      hpfValue = math.pow(2, hpenv!).toDouble() * env * hpfValue + hpfValue;
    }

    var bpfValue = bandf;
    if (bpfValue != null && _bpenv != null && bpenv != null) {
      final env = _bpenv!.update(
        time,
        gate,
        bpattack ?? 0,
        bpdecay ?? 0,
        bpsustain ?? 0,
        bprelease ?? 0,
      );
      bpfValue = math.pow(2, bpenv!).toDouble() * env * bpfValue + bpfValue;
    }

    final env = _adsr!.update(
      time,
      gate,
      attack ?? 0,
      decay ?? 0,
      sustain ?? 0,
      release,
    );

    List<double>? wavetableFrame;
    if (_sound is _WavetableSource) {
      var wtPosition = _wtBase;
      if (_wtEnv != null && _wtEnvAmount != 0) {
        final env = _wtEnv!.update(
          time,
          gate,
          wtattack ?? 0,
          wtdecay ?? 0,
          wtsustain ?? 0,
          wtrelease ?? 0,
        );
        wtPosition = wtPosition + _wtEnvAmount * env;
      }
      if (_wtLfo != null && _wtLfoDepth != 0) {
        final lfo = _wtLfo!.update(_wtLfoRate, _wtLfoSkew);
        wtPosition = wtPosition + (lfo + _wtLfoDc) * _wtLfoDepth;
      }

      var warpValue = _warpBase;
      if (_warpEnv != null && _warpEnvAmount != 0) {
        final env = _warpEnv!.update(
          time,
          gate,
          warpattack ?? 0,
          warpdecay ?? 0,
          warpsustain ?? 0,
          warprelease ?? 0,
        );
        warpValue = warpValue + _warpEnvAmount * env;
      }
      if (_warpLfo != null && _warpLfoDepth != 0) {
        final lfo = _warpLfo!.update(_warpLfoRate, _warpLfoSkew);
        warpValue = warpValue + (lfo + _warpLfoDc) * _warpLfoDepth;
      }

      wavetableFrame = (_sound as _WavetableSource).update(
        frequency: currentFreq,
        freqSpread: _wtFreqSpread,
        position: wtPosition,
        warp: warpValue,
        warpMode: _warpMode,
        voices: _wtVoices,
        panSpread: _wtPanSpread,
        phaseRand: _wtPhaseRand,
      );
    }

    for (var i = 0; i < _channels; i++) {
      double sample;
      if (_sound != null) {
        if (_sound is _PulseOsc) {
          sample = (_sound as _PulseOsc).update(currentFreq, pw);
        } else if (_sound is _PulzeOsc) {
          sample = (_sound as _PulzeOsc).update(currentFreq, pw);
        } else if (_sound is _Dust) {
          final densityValue = s == 'crackle'
              ? density * 0.01 * _sampleRate
              : density;
          sample = (_sound as _Dust).update(densityValue);
        } else if (_sound is _WavetableOsc) {
          sample = (_sound as _WavetableOsc).update(currentFreq);
        } else if (_sound is _WavetableSource && wavetableFrame != null) {
          sample = wavetableFrame[i];
        } else {
          sample = (_sound as dynamic).update(currentFreq) as double;
        }
      } else {
        sample = _buffers![i].update(currentFreq);
      }

      sample *= gain * velocity;

      if (_noise != null && noise != null) {
        final mix = _clamp(noise!, 0, 1);
        final noiseSample = _noise!.update();
        sample = sample * (1 - mix) + noiseSample * mix;
      }

      if (_chorus != null) {
        final c = _chorus![i].update(
          sample,
          chorus,
          0.03 + 0.05 * i,
          1,
          0.11,
          _sampleRate,
        );
        sample = c + sample;
      }

      if (_lpf != null && lpfValue != null) {
        _lpf![i].update(sample, lpfValue, resonance);
        sample = _lpf![i].s1;
      }
      if (_hpf != null && hpfValue != null) {
        _hpf![i].update(sample, hpfValue, hresonance);
        sample = sample - _hpf![i].s1;
      }
      if (_bpf != null && bpfValue != null) {
        _bpf![i].update(sample, bpfValue, bandq);
        sample = _bpf![i].s0;
      }
      if (_coarse != null && coarse != null && coarse! > 0) {
        sample = _coarse![i].update(sample, coarse!);
      }
      if (_crush != null && crush != null && crush! > 0) {
        sample = _crush![i].update(sample, crush!);
      }
      if (_distort != null && distort != null && distort != 0) {
        sample = _distort![i].update(sample, distort!, distortvol);
      }

      sample = sample * env;
      sample = sample * postgain;

      if (_buffers == null) {
        sample *= 0.2;
      }

      out[i] = sample.toDouble();
    }

    if (_channels == 1) {
      out[1] = out[0];
    }

    if (pan != 0.5) {
      final panPos = (pan * math.pi) / 2;
      out[0] = out[0] * math.cos(panPos);
      out[1] = out[1] * math.sin(panPos);
    }
  }
}

typedef _OscFactory = dynamic Function(double sampleRate);

/// Built-in sound names supported by the Dough oscillator set.
const Set<String> doughSoundNames = {
  'sine',
  'saw',
  'zaw',
  'sawtooth',
  'zawtooth',
  'supersaw',
  'tri',
  'triangle',
  'pulse',
  'square',
  'pulze',
  'dust',
  'crackle',
  'impulse',
  'white',
  'brown',
  'pink',
};

final Map<String, _OscFactory> _shapeFactories = {
  'sine': (sr) => _SineOsc(sampleRate: sr),
  'saw': (sr) => _SawOsc(sampleRate: sr),
  'zaw': (sr) => _ZawOsc(sampleRate: sr),
  'sawtooth': (sr) => _SawOsc(sampleRate: sr),
  'zawtooth': (sr) => _ZawOsc(sampleRate: sr),
  'supersaw': (sr) => _SupersawOsc(sampleRate: sr),
  'tri': (sr) => _TriOsc(sampleRate: sr),
  'triangle': (sr) => _TriOsc(sampleRate: sr),
  'pulse': (sr) => _PulseOsc(sampleRate: sr),
  'square': (sr) => _PulseOsc(sampleRate: sr),
  'pulze': (sr) => _PulzeOsc(sampleRate: sr),
  'dust': (sr) => _Dust(sampleRate: sr),
  'crackle': (sr) => _Dust(sampleRate: sr),
  'impulse': (sr) => _Impulse(sampleRate: sr),
  'white': (_) => _WhiteNoise(),
  'brown': (_) => _BrownNoise(),
  'pink': (_) => _PinkNoise(),
};

/// Core DSP voice scheduler and mixer used by the synth renderer.
class Dough {
  /// Creates a new DSP mixer at the given sample rate.
  Dough({double sampleRate = _defaultSampleRate, double currentTime = 0})
      : sampleRate = sampleRate,
        _delayL = _Delay(sampleRate: sampleRate),
        _delayR = _Delay(sampleRate: sampleRate) {
    _t = (currentTime * sampleRate).floor();
  }

  /// The sample rate used to render audio.
  final double sampleRate;
  final List<_DoughVoice> _voices = [];
  final List<_ScheduledMessage> _queue = [];

  /// The latest stereo output frame.
  final Float32List out = Float32List(2);
  final Float32List _delaySend = Float32List(2);

  final _Delay _delayL;
  final _Delay _delayR;

  int _voiceId = 0;
  int _t = 0;

  double delaytime = _defaultDouble('delaytime', 0.25);
  double delayfeedback = _defaultDouble('delayfeedback', 0.5);
  double delayspeed = _defaultDouble('delayspeed', 1);

  /// Registers a PCM sample for buffer playback.
  void loadSample(String name, List<Float32List> channels, int sampleRate) {
    _BufferPlayer.samples[name] = _BufferSample(channels, sampleRate);
  }

  /// Schedule a voice to be spawned based on its `_begin`/`_duration` params.
  void scheduleSpawn(Map<String, dynamic> value) {
    final begin = _doubleParam(value, '_begin');
    final duration = _doubleParam(value, '_duration');
    if (begin == null) {
      throw StateError('scheduleSpawn expected _begin to be set');
    }
    if (duration == null) {
      throw StateError('scheduleSpawn expected _duration to be set');
    }
    value['sampleRate'] = sampleRate;
    final time = (begin * sampleRate).floor();
    _schedule(_ScheduledMessage(time: time, type: 'spawn', arg: value));
  }

  void _spawn(Map<String, dynamic> value) {
    final voice = _DoughVoice.fromMap(
      value,
      sampleRate: sampleRate,
    );
    voice.id = _voiceId++;
    _voices.add(voice);
    final endTime = (voice.end * sampleRate).ceil();
    _schedule(_ScheduledMessage(time: endTime, type: 'despawn', arg: voice.id));
  }

  void _despawn(int id) {
    _voices.removeWhere((voice) => voice.id == id);
  }

  void _schedule(_ScheduledMessage message) {
    if (_queue.isEmpty) {
      _queue.add(message);
      return;
    }
    var i = 0;
    while (i < _queue.length && _queue[i].time < message.time) {
      i++;
    }
    _queue.insert(i, message);
  }

  /// Advances the DSP engine by one sample frame.
  void update() {
    while (_queue.isNotEmpty && _queue.first.time <= _t) {
      final message = _queue.removeAt(0);
      if (message.type == 'spawn') {
        _spawn(message.arg as Map<String, dynamic>);
      } else if (message.type == 'despawn') {
        _despawn(message.arg as int);
      }
    }

    out[0] = 0;
    out[1] = 0;

    for (final voice in _voices) {
      voice.update(_t / sampleRate);
      out[0] += voice.out[0];
      out[1] += voice.out[1];
      if (voice.delay > 0) {
        _delaySend[0] += voice.out[0] * voice.delay;
        _delaySend[1] += voice.out[1] * voice.delay;
        delaytime = voice.delaytime;
        delayspeed = voice.delayspeed;
        delayfeedback = voice.delayfeedback;
      }
    }

    final delayL = _delayL.update(_delaySend[0], delaytime, sampleRate);
    final delayR = _delayR.update(_delaySend[1], delaytime, sampleRate);

    _delaySend[0] = delayL * delayfeedback;
    _delaySend[1] = delayR * delayfeedback;

    out[0] += delayL;
    out[1] += delayR;

    _t += 1;
  }
}

class _ScheduledMessage {
  _ScheduledMessage({
    required this.time,
    required this.type,
    required this.arg,
  });

  final int time;
  final String type;
  final Object arg;
}
