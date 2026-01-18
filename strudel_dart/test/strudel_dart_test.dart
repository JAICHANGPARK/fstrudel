import 'package:test/test.dart';
import 'package:strudel_dart/strudel_dart.dart';
import 'package:fraction/fraction.dart' as f;

void main() {
  group('Fraction', () {
    test('sam() returns floor', () {
      expect(fraction(1.5).sam(), equals(fraction(1)));
      expect(fraction(0.9).sam(), equals(fraction(0)));
      expect(fraction(2).sam(), equals(fraction(2)));
    });

    test('nextSam() returns next cycle start', () {
      expect(fraction(1.5).nextSam(), equals(fraction(2)));
      expect(fraction(0.1).nextSam(), equals(fraction(1)));
    });

    test('cyclePos() returns position within cycle', () {
      expect(fraction(1.25).cyclePos(), equals(fraction(0.25)));
    });
  });

  group('TimeSpan', () {
    test('equals()', () {
      expect(TimeSpan(0, 4).equals(TimeSpan(0, 4)), isTrue);
      expect(TimeSpan(0, 4).equals(TimeSpan(0, 5)), isFalse);
    });

    test('intersection()', () {
      final a = TimeSpan(0, 2);
      final b = TimeSpan(1, 3);
      final intersection = a.intersection(b);
      expect(intersection, isNotNull);
      expect(intersection!.begin, equals(fraction(1)));
      expect(intersection.end, equals(fraction(2)));
    });

    test('intersection() returns null for non-intersecting spans', () {
      final a = TimeSpan(0, 1);
      final b = TimeSpan(2, 3);
      expect(a.intersection(b), isNull);
    });
  });

  group('Hap', () {
    test('hasOnset() returns true if part starts at whole start', () {
      final hap = Hap(TimeSpan(0, 1), TimeSpan(0, 0.5), 'test');
      expect(hap.hasOnset(), isTrue);
    });

    test('hasOnset() returns false if part starts after whole start', () {
      final hap = Hap(TimeSpan(0, 1), TimeSpan(0.5, 1), 'test');
      expect(hap.hasOnset(), isFalse);
    });
  });

  group('Pattern', () {
    test('pure() returns a pattern that repeats the value', () {
      final pat = pure('hello');
      final haps = pat.queryArc(0.5, 2.5);
      expect(haps.length, equals(3));
      expect(haps[0].value, equals('hello'));
      expect(haps[0].part.begin, equals(fraction(0.5)));
      expect(haps[0].part.end, equals(fraction(1)));
      expect(haps[1].part.begin, equals(fraction(1)));
      expect(haps[1].part.end, equals(fraction(2)));
      expect(haps[2].part.begin, equals(fraction(2)));
      expect(haps[2].part.end, equals(fraction(2.5)));
    });

    test('map() transforms values', () {
      final pat = pure(3).map((x) => x + 4);
      final haps = pat.queryArc(0, 1);
      expect(haps[0].value, equals(7));
    });

    test('sequence() divides cycles', () {
      final pat = sequence(['bd', 'sd']);
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(2));
      expect(haps[0].value, equals('bd'));
      expect(haps[0].part.begin, equals(fraction(0)));
      expect(haps[0].part.end, equals(fraction(0.5)));
      expect(haps[1].value, equals('sd'));
      expect(haps[1].part.begin, equals(fraction(0.5)));
      expect(haps[1].part.end, equals(fraction(1)));
    });

    test('stack() layers patterns', () {
      final pat = stack(['bd', 'sd']);
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(2));
      // Both should start at 0 and end at 1
      expect(haps.any((h) => h.value == 'bd'), isTrue);
      expect(haps.any((h) => h.value == 'sd'), isTrue);
    });

    test('controls merge correctly', () {
      final pat = s('bd').gain(0.5);
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(1));
      expect(haps[0].value['s'], equals('bd'));
      expect(haps[0].value['gain'], equals(0.5));
    });

    test('mini() parses simple sequences', () {
      final pat = mini('bd hh');
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(2));
      expect(haps[0].value, equals('bd'));
      expect(haps[1].value, equals('hh'));
    });

    test('mini() parses nested cycles', () {
      final pat = mini('bd [hh sd]');
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(3));
      expect(haps[0].value, equals('bd'));
      expect(haps[1].value, equals('hh'));
      expect(haps[2].value, equals('sd'));
    });

    test('mini() parses stacks', () {
      final pat = mini('bd,hh');
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(2));
      expect(haps.any((h) => h.value == 'bd'), isTrue);
      expect(haps.any((h) => h.value == 'hh'), isTrue);
    });

    test('mini() handles multipliers', () {
      final pat = mini('bd*2'); // bd bd
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(2));
      expect(haps[0].value, equals('bd'));
      expect(haps[1].value, equals('bd'));
      expect(haps[0].part.duration, equals(fraction(0.5)));
    });

    test('mini() handles complex multipliers', () {
      final pat = mini('bd [hh sd]*2'); // bd hh sd hh sd
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(5));
      expect(haps[0].value, equals('bd'));
      expect(haps[1].value, equals('hh'));
      expect(haps[1].part.duration, equals(fraction(1 / 8)));
    });

    test('mini() handles replicates', () {
      final pat = mini('bd!3'); // bd bd bd
      final haps = pat.queryArc(0, 1);
      expect(haps.length, equals(3));
      expect(haps.every((h) => h.value == 'bd'), isTrue);
      expect(haps[0].part.duration, equals(fraction(1 / 3)));
    });

    test('mini() handles weights', () {
      final pat = mini('bd@2 sd'); // bd bd sd (bd takes 2/3, sd takes 1/3)
      final haps = pat.queryArc(0, 1);
      print('Weighted pattern haps: ${haps.length}');
      for (final h in haps) {
        print('  Hap: ${h.value} at ${h.part.show()}');
      }
      expect(haps.length, equals(2));
      expect(haps[0].value, equals('bd'));
      expect(haps[0].part.duration, equals(f.Fraction(2, 3)));
      expect(haps[1].value, equals('sd'));
      expect(haps[1].part.duration, equals(f.Fraction(1, 3)));
    });
  });
}
