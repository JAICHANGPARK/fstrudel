import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';
import 'hap.dart';
import 'pattern.dart';

String drawLine(Pattern pat, {int chars = 60}) {
  var cycle = 0;
  f.Fraction pos = fraction(0);
  var lines = <String>[''];
  var emptyLine = '';

  while (lines[0].length < chars) {
    final haps = pat.queryArc(cycle, cycle + 1);
    final durations = haps.where((hap) => hap.hasOnset()).map((hap) => hap.duration).toList();
    final charFraction = gcdMany(durations) ?? fraction(1);
    final totalSlots = charFraction.numerator == 0
        ? 0
        : (charFraction.denominator ~/ charFraction.numerator);

    lines = lines.map((line) => '$line|').toList();
    emptyLine += '|';

    for (var i = 0; i < totalSlots; i++) {
      final begin = pos;
      final end = pos + charFraction;
      final matches = haps.where((hap) {
        final whole = hap.whole ?? hap.part;
        return whole.begin.lte(begin) && whole.end.gte(end);
      }).toList();

      final missingLines = matches.length - lines.length;
      if (missingLines > 0) {
        lines = lines + List<String>.filled(missingLines, emptyLine);
      }

      lines = lines.asMap().entries.map((entry) {
        final lineIndex = entry.key;
        final line = entry.value;
        final hap = lineIndex < matches.length ? matches[lineIndex] : null;
        if (hap != null) {
          final whole = hap.whole ?? hap.part;
          final isOnset = whole.begin.eq(begin);
          final char = isOnset ? '${hap.value}' : '-';
          return '$line$char';
        }
        return '$line.';
      }).toList();

      emptyLine += '.';
      pos = pos + charFraction;
    }
    cycle++;
  }
  return lines.join('\n');
}
