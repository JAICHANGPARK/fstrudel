import 'package:petitparser/petitparser.dart';
import 'pattern.dart';

class MiniParserDefinition extends GrammarDefinition {
  @override
  Parser start() => ref0(statement).end();

  Parser statement() =>
      ref0(stackRule) | ref0(slowcatRule) | ref0(sequenceRule);

  Parser slowcatRule() =>
      (char('<').trim() & ref0(sliceWithOps).plus() & char('>').trim()).map((
        values,
      ) {
        return slowcat(values[1] as List);
      });

  Parser stackRule() =>
      (ref0(sequenceRule) & (char(',').trim() & ref0(sequenceRule)).plus()).map(
        (values) {
          final head = values[0];
          final rest = (values[1] as List).map((v) => v[1]).toList();
          return stack([head, ...rest]);
        },
      );

  Parser sequenceRule() => (ref0(sliceWithOps).plus()).map((values) {
    if (values.length == 1) {
      final first = values[0];
      return first is _WeightedPattern ? first.pattern : first as Pattern;
    }

    final patterns = values;
    final List<dynamic> weightedList = [];
    bool hasWeight = false;

    for (var p in patterns) {
      if (p is _WeightedPattern) {
        hasWeight = true;
        weightedList.add([p.weight, p.pattern]);
      } else {
        weightedList.add([1.0, p]);
      }
    }

    if (hasWeight) {
      print('Weighted sequence list: $weightedList');
      return timeCat(weightedList);
    }

    return sequence(patterns);
  });

  Parser stackOrSlowcat() =>
      ref0(stackRule) | ref0(slowcatRule) | ref0(sequenceRule);

  Pattern _extractPattern(dynamic p) =>
      p is _WeightedPattern ? p.pattern : p as Pattern;

  Parser sliceWithOps() => (ref0(slice) & ref0(op).star()).map((values) {
    dynamic pat = values[0];
    final ops = values[1] as List;
    for (final op in ops) {
      final type = op[0];
      final arg = op[1];

      if (type == '*') {
        pat = _extractPattern(pat).fast(_getFactor(arg));
      } else if (type == '/') {
        pat = _extractPattern(pat).slow(_getFactor(arg));
      } else if (type == '!') {
        final reps = _getFactor(arg).toInt();
        final patToRep = _extractPattern(pat);
        pat = sequence(List.filled(reps, patToRep));
      } else if (type == '@') {
        final weight = _getFactor(arg);
        pat = _WeightedPattern(_extractPattern(pat), weight);
      } else if (type == 'euclid') {
        final args = arg as List;
        pat = _extractPattern(pat).euclid(args[0].toInt(), args[1].toInt());
      }
    }
    return pat;
  });

  double _getFactor(dynamic arg) {
    Pattern p = _extractPattern(arg);
    final haps = p.queryArc(0, 1);
    if (haps.isNotEmpty && haps[0].value is num) {
      return (haps[0].value as num).toDouble();
    }
    return 1.0;
  }

  Parser slice() => ref0(subcycle) | ref0(slowcatRule) | ref0(atom);

  Parser op() =>
      ((char('*') | char('/') | char('!') | char('@')) & ref0(slice)) |
      ref0(euclidOp);

  Parser euclidOp() =>
      (char('(').trim() &
              ref0(numberLiteral) &
              char(',').trim() &
              ref0(numberLiteral) &
              char(')').trim())
          .map(
            (values) => [
              'euclid',
              [values[1], values[3]],
            ],
          );

  Parser subcycle() =>
      (char('[').trim() & ref0(stackOrSlowcat) & char(']').trim()).map((
        values,
      ) {
        return values[1];
      });

  Parser atom() => (ref0(token) | ref0(silenceToken)).map((value) {
    if (value == '~') return silence;
    final numValue = double.tryParse(value);
    if (numValue != null) return pure(numValue);
    return pure(value);
  });

  Parser numberLiteral() =>
      ((char('-').optional() &
                  digit().plus() &
                  (char('.') & digit().plus()).optional()) |
              (char('.') & digit().plus()))
          .flatten()
          .map(num.parse)
          .trim();

  Parser silenceToken() => char('~').flatten().trim();

  Parser token() => (letter() | digit() | char('#') | char('.') | char('-'))
      .plus()
      .flatten()
      .trim();
}

class _WeightedPattern {
  final Pattern pattern;
  final double weight;
  _WeightedPattern(this.pattern, this.weight);
}

final miniParser = MiniParserDefinition().build();

Pattern mini(String input) {
  final result = miniParser.parse(input);
  if (result is Failure) {
    throw Exception(
      'MiniNotation parse error: ${result.message} at ${result.position}',
    );
  }
  return result.value is _WeightedPattern
      ? result.value.pattern
      : result.value as Pattern;
}
