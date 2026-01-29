import 'dart:convert';
import 'dart:math' as math;
import 'package:fraction/fraction.dart' as f;
import 'hap.dart';
import 'logger.dart';

/// Modulo that works with negative numbers e.g. mod(-1, 3) = 2.
num mod(num n, num m) => ((n % m) + m) % m;

/// Rational version of mod.
f.Fraction modFraction(f.Fraction n, f.Fraction m) {
  final div = n / m;
  final floor = f.Fraction(div.numerator ~/ div.denominator);
  final res = n - (m * floor);
  return res.isNegative ? res + m : res;
}

List<T> flatten<T>(Iterable<Iterable<T>> list) =>
    list.expand((element) => element).toList();

bool isNoteWithOctave(String name) =>
    RegExp(r'^[a-gA-G][#bsf]*[0-9]*$').hasMatch(name);
bool isNote(String name) => RegExp(r'^[a-gA-G][#bsf]*-?[0-9]*$').hasMatch(name);

List<dynamic> tokenizeNote(String note) {
  final match = RegExp(r'^([a-gA-G])([#bsf]*)(-?[0-9]*)$').firstMatch(note);
  if (match == null) return [];
  final pc = match.group(1);
  final acc = match.group(2) ?? '';
  final oct = match.group(3);
  if (pc == null) return [];
  return [pc, acc, oct != null && oct.isNotEmpty ? int.parse(oct) : null];
}

const Map<String, int> _chromas = {
  'c': 0,
  'd': 2,
  'e': 4,
  'f': 5,
  'g': 7,
  'a': 9,
  'b': 11,
};
const Map<String, int> _accs = {'#': 1, 'b': -1, 's': 1, 'f': -1};

int getAccidentalsOffset(String? accidentals) {
  if (accidentals == null || accidentals.isEmpty) return 0;
  return accidentals
      .split('')
      .fold<int>(0, (sum, char) => sum + (_accs[char] ?? 0));
}

int noteToMidi(String note, {int defaultOctave = 3}) {
  final tokens = tokenizeNote(note);
  if (tokens.isEmpty) {
    throw StateError('not a note: "$note"');
  }
  final pc = (tokens[0] as String).toLowerCase();
  final acc = tokens[1] as String;
  final oct = tokens[2] as int? ?? defaultOctave;
  final chroma = _chromas[pc];
  if (chroma == null) {
    throw StateError('not a note: "$note"');
  }
  final offset = getAccidentalsOffset(acc);
  return (oct + 1) * 12 + chroma + offset;
}

double midiToFreq(num n) => math.pow(2, (n - 69) / 12).toDouble() * 440.0;

double freqToMidi(num freq) => (12 * (math.log(freq / 440) / math.ln2)) + 69;

num valueToMidi(Map<String, dynamic> value, {num? fallbackValue}) {
  final freq = value['freq'];
  final note = value['note'];
  if (freq is num) {
    return freqToMidi(freq);
  }
  if (note is String) {
    return noteToMidi(note);
  }
  if (note is num) {
    return note;
  }
  if (fallbackValue == null) {
    throw StateError('valueToMidi: expected freq or note to be set');
  }
  return fallbackValue;
}

double getEventOffsetMs(double targetTimeSeconds, double currentTimeSeconds) =>
    (targetTimeSeconds - currentTimeSeconds) * 1000;

double getFreq(dynamic noteOrMidi) {
  if (noteOrMidi is num) {
    return midiToFreq(noteOrMidi);
  }
  return midiToFreq(noteToMidi(noteOrMidi.toString()));
}

const List<String> _pcs = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

String midi2note(int n) {
  final oct = (n ~/ 12) - 1;
  final pc = _pcs[n % 12];
  return '$pc$oct';
}

double averageArray(List<num> arr) => arr.reduce((a, b) => a + b) / arr.length;

num nanFallback(dynamic value, num fallback) {
  if (value is num) return value;
  final asNumber = num.tryParse(value.toString());
  if (asNumber == null) {
    logger(
      '"$value" is not a number, falling back to $fallback',
      type: 'warning',
    );
    return fallback;
  }
  return asNumber;
}

int getSoundIndex(num n, int numSounds) {
  return mod(nanFallback(n, 0).round(), numSounds).toInt();
}

dynamic getPlayableNoteValue(Hap hap) {
  var note = hap.value;
  if (note is Map) {
    note = note['note'] ?? note['n'] ?? note['value'];
    if (note == null) {
      throw StateError('cannot find a playable note for ${hap.value}');
    }
  }
  if (note is num && hap.context['type'] != 'frequency') {
    return midiToFreq(note);
  }
  if (note is num && hap.context['type'] == 'frequency') {
    return note;
  }
  if (note is! String || !isNote(note)) {
    throw StateError('not a note: $note');
  }
  return note;
}

double getFrequency(Hap hap) {
  var value = hap.value;
  if (value is Map) {
    if (value['freq'] is num) {
      return (value['freq'] as num).toDouble();
    }
    return getFreq(value['note'] ?? value['n'] ?? value['value']);
  }
  if (value is num && hap.context['type'] != 'frequency') {
    value = midiToFreq(value);
  } else if (value is String && isNote(value)) {
    value = midiToFreq(noteToMidi(value));
  } else if (value is! num) {
    throw StateError('not a note or frequency: $value');
  }
  return value.toDouble();
}

List<T> rotate<T>(List<T> arr, int n) => [...arr.skip(n), ...arr.take(n)];

T Function(dynamic) pipe<T>(List<Function> funcs) {
  return (dynamic x) => funcs.fold(x, (val, fn) => fn(val)) as T;
}

T Function(dynamic) compose<T>(List<Function> funcs) {
  return pipe<T>(funcs.reversed.toList());
}

List<T> removeUndefineds<T>(Iterable<T?> xs) => xs.whereType<T>().toList();

T id<T>(T a) => a;
T constant<T>(T a, dynamic _) => a;

List<int> listRange(int min, int max) =>
    List<int>.generate(max - min + 1, (i) => i + min);

Function curry(Function func, [int? arity]) {
  final targetArity = arity ?? 1;
  dynamic curried(List<dynamic> args) {
    if (args.length >= targetArity) {
      return Function.apply(func, args);
    }
    return (dynamic a) => curried([...args, a]);
  }

  return (dynamic a) => curried([a]);
}

num parseNumeral(dynamic numOrString) {
  final asNumber = num.tryParse(numOrString.toString());
  if (asNumber != null) return asNumber;
  if (numOrString is String && isNote(numOrString)) {
    return noteToMidi(numOrString);
  }
  throw StateError('cannot parse as numeral: "$numOrString"');
}

Function mapArgs(Function fn, num Function(dynamic) mapFn) {
  return (dynamic args) {
    final list = args is List ? args : [args];
    return Function.apply(fn, list.map(mapFn).toList());
  };
}

Function numeralArgs(Function fn) => mapArgs(fn, parseNumeral);

num parseFractional(dynamic numOrString) {
  final asNumber = num.tryParse(numOrString.toString());
  if (asNumber != null) return asNumber;
  const specialValue = <String, double>{
    'pi': math.pi,
    'w': 1,
    'h': 0.5,
    'q': 0.25,
    'e': 0.125,
    's': 0.0625,
    't': 1 / 3,
    'f': 0.2,
    'x': 1 / 6,
  };
  final val = specialValue[numOrString.toString()];
  if (val != null) return val;
  throw StateError('cannot parse as fractional: "$numOrString"');
}

Function fractionalArgs(Function fn) => mapArgs(fn, parseFractional);

List<dynamic> splitAt(int index, List<dynamic> value) => [
  value.sublist(0, index),
  value.sublist(index),
];

List<T> zipWith<T>(T Function(dynamic, dynamic) f, List xs, List ys) =>
    List<T>.generate(xs.length, (i) => f(xs[i], ys[i]));

List<List<T>> pairs<T>(List<T> xs) {
  final result = <List<T>>[];
  for (var i = 0; i < xs.length - 1; i++) {
    result.add([xs[i], xs[i + 1]]);
  }
  return result;
}

num clamp(num value, num min, num max) => math.min(math.max(value, min), max);

const List<String> _solfeggio = [
  'Do',
  'Reb',
  'Re',
  'Mib',
  'Mi',
  'Fa',
  'Solb',
  'Sol',
  'Lab',
  'La',
  'Sib',
  'Si',
];
const List<String> _indian = ['Sa', 'Re', 'Ga', 'Ma', 'Pa', 'Dha', 'Ni'];
const List<String> _german = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Hb',
  'H',
];
const List<String> _byzantine = [
  'Ni',
  'Pab',
  'Pa',
  'Voub',
  'Vou',
  'Ga',
  'Dib',
  'Di',
  'Keb',
  'Ke',
  'Zob',
  'Zo',
];
const List<String> _japanese = ['I', 'Ro', 'Ha', 'Ni', 'Ho', 'He', 'To'];
const List<String> _english = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

String sol2note(int n, {String notation = 'letters'}) {
  List<String> pc;
  switch (notation) {
    case 'solfeggio':
      pc = _solfeggio;
      break;
    case 'indian':
      pc = _indian;
      break;
    case 'german':
      pc = _german;
      break;
    case 'byzantine':
      pc = _byzantine;
      break;
    case 'japanese':
      pc = _japanese;
      break;
    default:
      pc = _english;
  }
  final note = pc[n % 12];
  final oct = (n ~/ 12) - 1;
  return '$note$oct';
}

List<T> uniq<T>(List<T> a) {
  final seen = <T, bool>{};
  return a.where((item) => seen.putIfAbsent(item, () => true) == true).toList();
}

List<T> uniqsort<T extends Comparable>(List<T> a) {
  a.sort();
  final out = <T>[];
  for (final item in a) {
    if (out.isEmpty || out.last.compareTo(item) != 0) {
      out.add(item);
    }
  }
  return out;
}

List<f.Fraction> uniqsortr(List<f.Fraction> a) {
  a.sort((x, y) => x.compareTo(y));
  final out = <f.Fraction>[];
  for (final item in a) {
    if (out.isEmpty || out.last != item) {
      out.add(item);
    }
  }
  return out;
}

String unicodeToBase64(String text) {
  final utf8Bytes = utf8.encode(text);
  return base64.encode(utf8Bytes);
}

String base64ToUnicode(String base64String) {
  final bytes = base64.decode(base64String);
  return utf8.decode(bytes);
}

String code2hash(String code) => Uri.encodeComponent(unicodeToBase64(code));

String hash2code(String hash) => base64ToUnicode(Uri.decodeComponent(hash));

dynamic objectMap(dynamic obj, dynamic Function(dynamic, dynamic, int) fn) {
  if (obj is List) {
    return obj.asMap().entries.map((e) => fn(e.value, e.key, e.key)).toList();
  }
  if (obj is Map) {
    final entries = obj.entries.toList();
    return Map.fromEntries(
      entries.asMap().entries.map(
        (entry) => MapEntry(
          entry.value.key,
          fn(entry.value.value, entry.value.key, entry.key),
        ),
      ),
    );
  }
  throw StateError('objectMap expects list or map');
}

double cycleToSeconds(num cycle, num cps) => cycle / cps;

class ClockCollator {
  final double Function() getTargetClockTime;
  final int weight;
  final double offsetDelta;
  final double checkAfterTime;
  final double resetAfterTime;

  double? _offsetTime;
  double? _timeAtPrevOffsetSample;
  final List<double> _prevOffsetTimes = [];

  ClockCollator({
    double Function()? getTargetClockTime,
    this.weight = 16,
    this.offsetDelta = 0.005,
    this.checkAfterTime = 2,
    this.resetAfterTime = 8,
  }) : getTargetClockTime = getTargetClockTime ?? _getUnixTimeSeconds;

  void reset() {
    _prevOffsetTimes.clear();
    _offsetTime = null;
    _timeAtPrevOffsetSample = null;
  }

  double calculateOffset(double currentTime) {
    final targetClockTime = getTargetClockTime();
    final offset = targetClockTime - currentTime;

    if (_timeAtPrevOffsetSample == null) {
      _timeAtPrevOffsetSample = currentTime;
      _offsetTime = offset;
      _prevOffsetTimes.add(offset);
      return offset;
    }

    if ((currentTime - (_timeAtPrevOffsetSample ?? 0)) > resetAfterTime) {
      reset();
      _timeAtPrevOffsetSample = currentTime;
      _offsetTime = offset;
      _prevOffsetTimes.add(offset);
      return offset;
    }

    if ((currentTime - (_timeAtPrevOffsetSample ?? 0)) > checkAfterTime) {
      final prevOffset = _offsetTime ?? offset;
      if ((offset - prevOffset).abs() > offsetDelta) {
        _prevOffsetTimes.add(offset);
        if (_prevOffsetTimes.length > weight) {
          _prevOffsetTimes.removeAt(0);
        }
        _offsetTime =
            _prevOffsetTimes.reduce((a, b) => a + b) / _prevOffsetTimes.length;
      }
      _timeAtPrevOffsetSample = currentTime;
    }

    return _offsetTime ?? offset;
  }
}

double _getUnixTimeSeconds() => DateTime.now().millisecondsSinceEpoch / 1000.0;

final Map<String, bool> _keyboardState = {};
final Map<String, String> keyAlias = {
  'Control': 'Control',
  'Ctrl': 'Control',
  'Alt': 'Alt',
  'Shift': 'Shift',
  'Meta': 'Meta',
};

Map<String, bool> getCurrentKeyboardState() => _keyboardState;

void setKeyboardKeyState(String key, bool isDown) {
  _keyboardState[key] = isDown;
}
