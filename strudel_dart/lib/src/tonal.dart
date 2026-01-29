import 'hap.dart';
import 'logger.dart';
import 'pattern.dart';
import 'util.dart';

const Map<String, List<int>> _scaleIntervals = {
  'major': [0, 2, 4, 5, 7, 9, 11],
  'ionian': [0, 2, 4, 5, 7, 9, 11],
  'minor': [0, 2, 3, 5, 7, 8, 10],
  'aeolian': [0, 2, 3, 5, 7, 8, 10],
  'dorian': [0, 2, 3, 5, 7, 9, 10],
  'phrygian': [0, 1, 3, 5, 7, 8, 10],
  'lydian': [0, 2, 4, 6, 7, 9, 11],
  'mixolydian': [0, 2, 4, 5, 7, 9, 10],
  'locrian': [0, 1, 3, 5, 6, 8, 10],
  'harmonic minor': [0, 2, 3, 5, 7, 8, 11],
  'melodic minor': [0, 2, 3, 5, 7, 9, 11],
  'major pentatonic': [0, 2, 4, 7, 9],
  'pentatonic major': [0, 2, 4, 7, 9],
  'minor pentatonic': [0, 3, 5, 7, 10],
  'pentatonic minor': [0, 3, 5, 7, 10],
  'blues': [0, 3, 5, 6, 7, 10],
  'chromatic': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
  'whole tone': [0, 2, 4, 6, 8, 10],
  'whole-half': [0, 2, 3, 5, 6, 8, 9, 11],
  'half-whole': [0, 1, 3, 4, 6, 7, 9, 10],
  'diminished': [0, 2, 3, 5, 6, 8, 9, 11],
};

const Map<String, String> _scaleAliases = {
  'maj': 'major',
  'min': 'minor',
  'ion': 'ionian',
  'aeo': 'aeolian',
  'mixolyd': 'mixolydian',
  'loc': 'locrian',
  'pentatonic': 'major pentatonic',
  'minor blues': 'blues',
};

class _ScaleSpec {
  final String name;
  final String root;
  final String rootPc;
  final int rootMidi;
  final List<int> intervals;

  const _ScaleSpec({
    required this.name,
    required this.root,
    required this.rootPc,
    required this.rootMidi,
    required this.intervals,
  });
}

class _StepSpec {
  final num step;
  final int offset;

  const _StepSpec(this.step, this.offset);
}

final Map<String, _ScaleSpec> _scaleCache = {};

extension PatternTonalExtension<T> on Pattern<T> {
  Pattern<dynamic> scale(dynamic scaleName) {
    if (scaleName is Pattern) {
      return scaleName.bind((value) => scale(value)).cast<dynamic>();
    }

    final normalizedName = _normalizeScaleName(scaleName);
    final spec = _getScaleSpec(normalizedName);

    return Pattern((state) {
      final haps = query(state);
      final updated = <Hap<dynamic>>[];
      for (final hap in haps) {
        final value = hap.value;
        final isObject = value is Map;
        final map = _coerceToMap(value);
        final noteOrStep = map['note'] ?? map['n'] ?? map['value'];

        if (noteOrStep == null) {
          logger(
            '[tonal] Invalid value format for scale. Expected n, note, '
            'or value keys.',
          );
          updated.add(hap);
          continue;
        }

        String scaleNote;
        if (noteOrStep is String && isNote(noteOrStep)) {
          scaleNote = _nearestScaleNote(spec, noteOrStep);
        } else {
          try {
            final stepSpec = _convertStepToNumberAndOffset(noteOrStep);
            final anchor = map['anchor'];
            final midi = anchor == null
                ? _scaleStepMidi(stepSpec.step, spec)
                : _stepInScaleWithAnchor(stepSpec.step, spec, anchor);
            final adjustedMidi = midi + stepSpec.offset;
            scaleNote = midi2note(adjustedMidi);
          } catch (error) {
            errorLogger(error, origin: 'tonal');
            continue;
          }
        }

        final nextMap = Map<String, dynamic>.from(map);
        nextMap.remove('n');
        nextMap.remove('value');
        nextMap['note'] = scaleNote;

        final nextValue = isObject ? nextMap : scaleNote;
        updated.add(
          hap
              .withValue((_) => nextValue)
              .setContext({...hap.context, 'scale': normalizedName}),
        );
      }
      return updated;
    }, steps: steps);
  }
}

Map<String, dynamic> _coerceToMap(dynamic value) {
  final map = <String, dynamic>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        map[key] = entry.value;
      }
    }
    return map;
  }
  map['n'] = value;
  return map;
}

_ScaleSpec _getScaleSpec(String scaleName) {
  final cached = _scaleCache[scaleName];
  if (cached != null) {
    return cached;
  }
  final spec = _parseScaleSpec(scaleName);
  _scaleCache[scaleName] = spec;
  return spec;
}

_ScaleSpec _parseScaleSpec(String scaleName) {
  if (scaleName.isEmpty) {
    throw StateError('Scale name is empty.');
  }
  final parts = scaleName.split(' ');
  final root = parts.first;
  final type =
      _normalizeScaleType(parts.length > 1 ? parts.sublist(1).join(' ') : '');

  if (!isNote(root) || type.isEmpty) {
    throw StateError(
      'Scale name "$scaleName" is incomplete. Use "C:major" or '
      '"C minor".',
    );
  }

  final intervals = _scaleIntervals[type];
  if (intervals == null) {
    throw StateError('Invalid scale name "$scaleName".');
  }

  final rootMidi = noteToMidi(root, defaultOctave: 3);
  final rootPc = _noteToPc(root);
  return _ScaleSpec(
    name: scaleName,
    root: root,
    rootPc: rootPc,
    rootMidi: rootMidi,
    intervals: intervals,
  );
}

String _noteToPc(String note) {
  final tokens = tokenizeNote(note);
  if (tokens.isEmpty) {
    return note;
  }
  final pc = tokens[0] as String;
  final acc = tokens[1] as String;
  return '$pc$acc';
}

String _normalizeScaleName(dynamic scaleName) {
  if (scaleName == null) {
    return '';
  }
  final parts = _flattenScaleParts(scaleName);
  final raw = parts.isEmpty ? scaleName.toString() : parts.join(' ');
  return raw
      .replaceAll(':', ' ')
      .replaceAll('_', ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizeScaleType(String type) {
  final normalized = type
      .replaceAll('_', ' ')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  return _scaleAliases[normalized] ?? normalized;
}

List<String> _flattenScaleParts(dynamic value) {
  final parts = <String>[];
  void visit(dynamic node) {
    if (node is List) {
      for (final item in node) {
        visit(item);
      }
      return;
    }
    if (node != null) {
      parts.add(node.toString());
    }
  }

  visit(value);
  return parts;
}

_StepSpec _convertStepToNumberAndOffset(dynamic step) {
  if (step is num) {
    return _StepSpec(step, 0);
  }
  final stepString = step.toString();
  final asNumber = num.tryParse(stepString);
  if (asNumber != null) {
    return _StepSpec(asNumber, 0);
  }
  final match = RegExp(r'^(-?\d+)([#bsf]*)$').firstMatch(stepString);
  if (match == null) {
    throw StateError(
      'Invalid scale step "$stepString", expected number with optional '
      '# or b suffix.',
    );
  }
  final number = num.parse(match.group(1)!);
  final accidentals = match.group(2) ?? '';
  final offset = getAccidentalsOffset(accidentals);
  return _StepSpec(number, offset);
}

int _scaleStepMidi(num step, _ScaleSpec spec) {
  final stepNum = step.ceil();
  final length = spec.intervals.length;
  final octaveOffset = (stepNum / length).floor();
  final index = mod(stepNum, length).toInt();
  final interval = spec.intervals[index];
  return spec.rootMidi + interval + (12 * octaveOffset);
}

int _stepInScaleWithAnchor(num step, _ScaleSpec spec, dynamic anchor) {
  final stepNum = step.ceil();
  final anchorMidi = _anchorToMidi(anchor);
  if (anchorMidi == null) {
    return _scaleStepMidi(stepNum, spec);
  }
  final rootChroma = mod(spec.rootMidi, 12).toInt();
  final anchorChroma = mod(anchorMidi, 12).toInt();
  final anchorDiff = mod(anchorChroma - rootChroma, 12).toInt();
  final zeroIndex = _nearestNumberIndex(
    anchorDiff,
    spec.intervals,
    true,
  );
  final adjustedStep = stepNum + zeroIndex;
  final length = spec.intervals.length;
  final octaveOffset = (adjustedStep / length).floor();
  final index = mod(adjustedStep, length).toInt();
  final target = spec.intervals[index] + (12 * octaveOffset);
  return target + (anchorMidi - anchorDiff);
}

int? _anchorToMidi(dynamic anchor) {
  if (anchor == null) {
    return null;
  }
  if (anchor is num) {
    return anchor.round();
  }
  if (anchor is String) {
    return noteToMidi(anchor, defaultOctave: 3);
  }
  if (anchor is Map) {
    final value = anchor['note'] ?? anchor['n'] ?? anchor['value'];
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return noteToMidi(value, defaultOctave: 3);
    }
  }
  return null;
}

String _nearestScaleNote(
  _ScaleSpec spec,
  dynamic note, {
  bool preferHigher = true,
}) {
  final noteMidi = note is num
      ? note.round()
      : noteToMidi(note.toString(), defaultOctave: 3);
  final rootMidi = noteToMidi('${spec.rootPc}0', defaultOctave: 0);
  final scaleMidis = <int>[
    for (final interval in spec.intervals) rootMidi + interval,
    rootMidi + 12,
  ];
  final octaveDiff = ((noteMidi - rootMidi) / 12).floor();
  final aligned = scaleMidis.map((m) => m + 12 * octaveDiff).toList();
  final index = _nearestNumberIndex(noteMidi, aligned, preferHigher);
  return midi2note(aligned[index]);
}

int _nearestNumberIndex(
  num target,
  List<num> values,
  bool preferHigher,
) {
  var bestIndex = 0;
  var bestDiff = double.infinity;
  for (var i = 0; i < values.length; i++) {
    final diff = (values[i] - target).abs();
    if ((!preferHigher && diff < bestDiff) ||
        (preferHigher && diff <= bestDiff)) {
      bestIndex = i;
      bestDiff = diff.toDouble();
    }
  }
  return bestIndex;
}
