import 'package:petitparser/petitparser.dart';
import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';
import 'pattern.dart';
import 'signal.dart' as s;
import 'tonal.dart';

class MiniNode {
  final String type;
  const MiniNode(this.type);
}

class MiniAtom extends MiniNode {
  final String source;
  const MiniAtom(this.source) : super('atom');
}

class MiniPattern extends MiniNode {
  final List<MiniNode> source;
  final Map<String, dynamic> arguments;
  MiniPattern(this.source, String alignment, {int? seed, bool stepsSource = false})
      : arguments = {
          'alignment': alignment,
          '_steps': stepsSource,
          if (seed != null) 'seed': seed,
        },
        super('pattern');
}

class MiniOperator extends MiniNode {
  final String name;
  final Map<String, dynamic> arguments;
  final MiniNode source;
  MiniOperator(this.name, this.arguments, this.source) : super(name);
}

class MiniElement extends MiniNode {
  final MiniNode source;
  final MiniOptions options;
  MiniElement(this.source, this.options) : super('element');
}

class MiniCommand extends MiniNode {
  final String name;
  final Map<String, dynamic> options;
  MiniCommand(this.name, this.options) : super('command');
}

class MiniOptions {
  f.Fraction weight;
  int reps;
  final List<MiniOp> ops;
  MiniOptions({f.Fraction? weight, this.reps = 1, List<MiniOp>? ops})
      : weight = weight ?? fraction(1),
        ops = ops ?? [];
}

class MiniOp {
  final String type;
  final Map<String, dynamic> arguments;
  MiniOp(this.type, this.arguments);
}

typedef _OpAction = void Function(MiniOptions options);

class KrillParserDefinition extends GrammarDefinition {
  Parser ws() => (ref0(comment) | whitespace()).star();
  Parser ws1() => (ref0(comment) | whitespace()).plus();

  Parser comment() =>
      (string('//') & any().starLazy(char('\n').or(endOfInput())));

  Parser _token(Parser parser) => parser.trim(ref0(ws1));

  @override
  Parser start() => ref0(statement).end();

  Parser statement() => ref0(miniDefinition) | ref0(command);

  Parser miniDefinition() => ref0(sequOrOperatorOrComment);

  Parser sequOrOperatorOrComment() => ref0(miniOrOperator) | ref0(comment);

  Parser miniOrGroup() => ref0(cat) | ref0(mini);

  Parser miniOrOperator() =>
      (ref0(miniOrGroup).trim(ref0(ws1)).map((v) => v)) |
      (ref0(operatorRule)
              .trim(ref0(ws1))
              .seq(_token(char('\$')))
              .seq(ref0(miniOrOperator))
              .map((values) {
        final op = values[0] as Map<String, dynamic>;
        final target = (values[2] as MiniNode);
        return MiniOperator(op['name'] as String, op['args'] as Map<String, dynamic>, target);
      }));

  Parser mini() =>
      _token(ref0(quote)).seq(ref0(stackOrChoose)).seq(_token(ref0(quote))).map(
    (values) {
      return values[1] as MiniNode;
    },
  );

  Parser cat() => _token(string('cat'))
      .seq(_token(char('[')))
      .seq(ref0(miniOrOperator))
      .seq((ref0(comma).seq(ref0(miniOrOperator))).star())
      .seq(_token(char(']')))
      .map((values) {
    final head = values[2] as MiniNode;
    final tail = (values[3] as List)
        .map((v) => v[1] as MiniNode)
        .toList();
    final list = [head, ...tail];
    return MiniPattern(list, 'slowcat');
  });

  Parser quote() => char('"') | char("'");

  Parser stackOrChoose() => ref0(sequenceRule)
      .seq((ref0(stackTail) | ref0(chooseTail) | ref0(dotTail)).optional())
      .map(
    (values) {
      final head = values[0] as MiniNode;
      final tail = values[1];
      if (tail == null) return head;
      final Map<String, dynamic> tailMap = tail as Map<String, dynamic>;
      final List<MiniNode> list = tailMap['list'] as List<MiniNode>;
      return MiniPattern([head, ...list], tailMap['alignment'] as String, seed: tailMap['seed'] as int?);
    },
  );

  Parser polymeterStack() => ref0(sequenceRule).seq(ref0(stackTail).optional()).map(
    (values) {
      final head = values[0] as MiniNode;
      final tail = values[1] as Map<String, dynamic>?;
      final list = tail == null ? [head] : [head, ...(tail['list'] as List<MiniNode>)];
      return MiniPattern(list, 'polymeter');
    },
  );

  Parser stackTail() => (ref0(comma).seq(ref0(sequenceRule)).plus()).map((values) {
    final list = values.map((v) => v[1] as MiniNode).toList();
    return {'alignment': 'stack', 'list': list};
  });

  Parser chooseTail() => (ref0(pipe).seq(ref0(sequenceRule)).plus()).map((values) {
    final list = values.map((v) => v[1] as MiniNode).toList();
    return {'alignment': 'rand', 'list': list, 'seed': _seed++};
  });

  Parser dotTail() => (ref0(dot).seq(ref0(sequenceRule)).plus()).map((values) {
    final list = values.map((v) => v[1] as MiniNode).toList();
    return {'alignment': 'feet', 'list': list, 'seed': _seed++};
  });

  Parser sequenceRule() => (ref0(caret).optional()).seq(ref0(sliceWithOps).plus()).map((values) {
    final stepsSource = values[0] != null;
    final List<MiniNode> items = (values[1] as List).cast<MiniNode>();
    return MiniPattern(items, 'fastcat', stepsSource: stepsSource);
  });

  Parser sliceWithOps() => ref0(slice).seq(ref0(sliceOp).star()).map((values) {
    final MiniNode base = values[0] as MiniNode;
    final List<_OpAction> ops = (values[1] as List).cast<_OpAction>();
    final options = MiniOptions();
    for (final op in ops) {
      op(options);
    }
    return MiniElement(base, options);
  });

  Parser slice() => ref0(step) | ref0(subCycle) | ref0(polymeter) | ref0(slowSequence);

  Parser subCycle() => _token(char('['))
      .seq(ref0(stackOrChoose))
      .seq(_token(char(']')))
      .map((values) => values[1] as MiniNode);

  Parser polymeter() => _token(char('{'))
      .seq(ref0(polymeterStack))
      .seq(_token(char('}')))
      .seq(ref0(polymeterSteps).optional())
      .map((values) {
    final MiniPattern pattern = values[1] as MiniPattern;
    final steps = values[3];
    if (steps != null) {
      pattern.arguments['stepsPerCycle'] = steps as MiniNode;
    }
    return pattern;
  });

  Parser polymeterSteps() => _token(char('%')).seq(ref0(slice)).map((values) => values[1] as MiniNode);

  Parser slowSequence() => _token(char('<'))
      .seq(ref0(polymeterStack))
      .seq(_token(char('>')))
      .map((values) {
    final MiniPattern pattern = values[1] as MiniPattern;
    pattern.arguments['alignment'] = 'polymeter_slowcat';
    return pattern;
  });

  Parser step() => _token(ref0(stepChars)).map((value) {
    final text = value as String;
    if (text == '.' || text == '_') {
      throw Exception('MiniNotation parse error: invalid step "$text"');
    }
    return MiniAtom(text);
  });

  Parser stepChars() => ref0(stepChar).plus().flatten();

  Parser stepChar() =>
      letter() | digit() | char('#') | char('.') | char('-') | char('^') | char('_') | char('~');

  Parser sliceOp() => ref0(opWeight) |
      ref0(opBjorklund) |
      ref0(opSlow) |
      ref0(opFast) |
      ref0(opReplicate) |
      ref0(opDegrade) |
      ref0(opTail) |
      ref0(opRange);

  Parser opWeight() => ref0(ws).seq(pattern('@_')).seq(ref0(number).optional()).map((values) {
    final num? amount = values[2] as num?;
    return (MiniOptions options) {
      final f.Fraction add = fraction(amount ?? 2);
      options.weight = options.weight + (add - fraction(1));
    };
  });

  Parser opReplicate() => ref0(ws).seq(char('!')).seq(ref0(number).optional()).map((values) {
    final num? amount = values[2] as num?;
    return (MiniOptions options) {
      final reps = (options.reps) + ((amount ?? 2).toInt() - 1);
      options.reps = reps;
      options.weight = fraction(reps);
      options.ops.removeWhere((op) => op.type == 'replicate');
      options.ops.add(MiniOp('replicate', {'amount': reps}));
    };
  });

  Parser opBjorklund() => _token(char('('))
      .seq(ref0(sliceWithOps))
      .seq(_token(char(',')))
      .seq(ref0(sliceWithOps))
      .seq(_token(char(','))
          .seq(ref0(sliceWithOps))
          .optional())
      .seq(_token(char(')')))
      .map((values) {
    final MiniNode pulse = values[1] as MiniNode;
    final MiniNode step = values[3] as MiniNode;
    final MiniNode? rotation = values[4] == null ? null : (values[4] as List)[1] as MiniNode?;
    return (MiniOptions options) {
      options.ops.add(MiniOp('bjorklund', {
        'pulse': pulse,
        'step': step,
        if (rotation != null) 'rotation': rotation,
      }));
    };
  });

  Parser opSlow() => _token(char('/')).seq(ref0(slice)).map((values) {
    final MiniNode amount = values[1] as MiniNode;
    return (MiniOptions options) {
      options.ops.add(MiniOp('stretch', {'amount': amount, 'type': 'slow'}));
    };
  });

  Parser opFast() => _token(char('*')).seq(ref0(slice)).map((values) {
    final MiniNode amount = values[1] as MiniNode;
    return (MiniOptions options) {
      options.ops.add(MiniOp('stretch', {'amount': amount, 'type': 'fast'}));
    };
  });

  Parser opDegrade() => _token(char('?')).seq(ref0(number).optional()).map((values) {
    final num? amount = values[1] as num?;
    return (MiniOptions options) {
      options.ops.add(MiniOp('degradeBy', {'amount': amount, 'seed': _seed++}));
    };
  });

  Parser opTail() => _token(char(':')).seq(ref0(slice)).map((values) {
    final MiniNode element = values[1] as MiniNode;
    return (MiniOptions options) {
      options.ops.add(MiniOp('tail', {'element': element}));
    };
  });

  Parser opRange() => _token(string('..')).seq(ref0(slice)).map((values) {
    final MiniNode element = values[1] as MiniNode;
    return (MiniOptions options) {
      options.ops.add(MiniOp('range', {'element': element}));
    };
  });

  Parser operatorRule() => ref0(opScale) | ref0(opSlowWord) | ref0(opFastWord) | ref0(opTarget) | ref0(opBjorklundWord) | ref0(opStruct) | ref0(opRotR) | ref0(opRotL);

  Parser opStruct() => _token(string('struct')).seq(ref0(miniOrOperator)).map((values) {
    return {'name': 'struct', 'args': {'mini': values[1]}};
  });

  Parser opTarget() => _token(string('target'))
      .seq(ref0(quote))
      .seq(ref0(step))
      .seq(ref0(quote))
      .map((values) {
    return {'name': 'target', 'args': {'name': values[2]}};
  });

  Parser opBjorklundWord() => _token(string('bjorklund'))
      .seq(ref0(number))
      .seq(ref0(number))
      .seq(ref0(number).optional())
      .map((values) {
    return {
      'name': 'bjorklund',
      'args': {'pulse': values[1], 'step': (values[2] as num).toInt()}
    };
  });

  Parser opSlowWord() => _token(string('slow')).seq(ref0(number)).map((values) {
    return {'name': 'stretch', 'args': {'amount': values[1], 'type': 'slow'}};
  });

  Parser opFastWord() => _token(string('fast')).seq(ref0(number)).map((values) {
    return {'name': 'stretch', 'args': {'amount': values[1], 'type': 'fast'}};
  });

  Parser opRotL() => _token(string('rotL')).seq(ref0(number)).map((values) {
    return {'name': 'shift', 'args': {'amount': '-${values[1]}'}};
  });

  Parser opRotR() => _token(string('rotR')).seq(ref0(number)).map((values) {
    return {'name': 'shift', 'args': {'amount': values[1]}};
  });

  Parser opScale() => _token(string('scale'))
      .seq(ref0(quote))
      .seq(ref0(stepChars))
      .seq(ref0(quote))
      .map((values) {
    return {'name': 'scale', 'args': {'scale': values[2]}};
  });

  Parser command() => ref0(setCps) | ref0(setBpm) | ref0(hush);

  Parser setCps() => _token(string('setcps')).seq(ref0(number)).map((values) {
    return MiniCommand('setcps', {'value': values[1]});
  });

  Parser setBpm() => _token(string('setbpm')).seq(ref0(number)).map((values) {
    final num bpm = values[1] as num;
    return MiniCommand('setcps', {'value': bpm / 120 / 2});
  });

  Parser hush() => _token(string('hush')).map((_) {
    return MiniCommand('hush', const {});
  });

  Parser comma() => _token(char(','));

  Parser pipe() => _token(char('|'));

  Parser dot() => _token(char('.'));

  Parser caret() => _token(char('^'));

  Parser number() => _token(ref0(numberLiteral));

  Parser numberLiteral() {
    final sign = char('-').optional();
    final intPart = digit().plus();
    final fracPart = (char('.') & digit().plus()).optional();
    final expPart =
        (pattern('eE') & pattern('+-').optional() & digit().plus()).optional();
    final leadDot = char('.') & digit().plus();

    return ((sign & intPart & fracPart & expPart) |
            (sign & leadDot & expPart))
        .flatten()
        .map(num.parse);
  }
}

final _krillParser = KrillParserDefinition().build();
int _seed = 0;

class _MiniMeta {
  f.Fraction weight;
  bool stepsSource;
  _MiniMeta({f.Fraction? weight, this.stepsSource = false})
      : weight = weight ?? fraction(1);
}

final Expando<_MiniMeta> _miniMeta = Expando<_MiniMeta>('miniMeta');

_MiniMeta _metaFor(Pattern pat) {
  return _miniMeta[pat] ??= _MiniMeta(weight: pat.steps ?? fraction(1));
}

void _setMeta(Pattern pat, {f.Fraction? weight, bool? stepsSource}) {
  final meta = _metaFor(pat);
  if (weight != null) meta.weight = weight;
  if (stepsSource != null) meta.stepsSource = stepsSource;
}

Pattern _patternify(MiniNode ast) {
  switch (ast.type) {
    case 'pattern':
      final MiniPattern patAst = ast as MiniPattern;
      final children = <Pattern>[];
      for (final child in patAst.source) {
        final childPattern = _patternify(child);
        if (child is MiniElement) {
          children.add(_applyOptions(child, childPattern));
        } else {
          children.add(childPattern);
        }
      }
      final alignment = patAst.arguments['alignment'] as String;
      final withSteps = children.where((c) => _metaFor(c).stepsSource).toList();
      Pattern result;
      switch (alignment) {
        case 'stack':
          result = stack(children);
          if (withSteps.isNotEmpty) {
            final lcmSteps = lcmMany(withSteps.map((p) => p.steps)) ?? fraction(1);
            result = result.setSteps(lcmSteps);
          }
          break;
        case 'polymeter_slowcat':
          result = stack(children.map((child) {
            final weight = _metaFor(child).weight;
            return child.slow(weight);
          }).toList());
          if (withSteps.isNotEmpty) {
            final lcmSteps = lcmMany(withSteps.map((p) => p.steps)) ?? fraction(1);
            result = result.setSteps(lcmSteps);
          }
          break;
        case 'polymeter':
          final stepsNode = patAst.arguments['stepsPerCycle'] as MiniNode?;
          final Pattern stepsPerCycle = stepsNode != null
              ? _patternify(stepsNode).map((x) => fraction(x))
              : pure(fraction(children.isNotEmpty ? _metaFor(children.first).weight : fraction(1)));
          final aligned = children.map((child) {
            final weight = _metaFor(child).weight;
            return child.fast(stepsPerCycle.map((x) => (x as f.Fraction) / weight));
          }).toList();
          result = stack(aligned);
          break;
        case 'rand':
          result = s.chooseInWith(
            s.rand.early(0.0003 * (patAst.arguments['seed'] as int? ?? 0)).segment(1),
            children,
          );
          if (withSteps.isNotEmpty) {
            final lcmSteps = lcmMany(withSteps.map((p) => p.steps)) ?? fraction(1);
            result = result.setSteps(lcmSteps);
          }
          break;
        case 'feet':
          result = fastcat(children);
          break;
        default:
          final weightedChildren = patAst.source.any((child) {
            if (child is MiniElement) {
              return child.options.weight != fraction(1);
            }
            return false;
          });
          if (weightedChildren) {
            var weightSum = fraction(0);
            final weightedList = <List<dynamic>>[];
            for (var i = 0; i < patAst.source.length; i++) {
              final child = patAst.source[i];
              final weight = child is MiniElement ? child.options.weight : fraction(1);
              weightSum += weight;
              weightedList.add([weight.toDouble(), children[i]]);
            }
            result = timeCat(weightedList);
            result = result.setSteps(weightSum);
            _setMeta(result, weight: weightSum);
            if (withSteps.isNotEmpty) {
              final lcmSteps = lcmMany(withSteps.map((p) => p.steps)) ?? fraction(1);
              result = result.setSteps(weightSum * lcmSteps);
            }
          } else {
            result = sequence(children);
            result = result.setSteps(fraction(children.length));
            _setMeta(result, weight: result.steps ?? fraction(1));
          }
          if (patAst.arguments['_steps'] == true) {
            _setMeta(result, stepsSource: true);
          }
          break;
      }
      if (withSteps.isNotEmpty) {
        _setMeta(result, stepsSource: true);
      }
      return result;
    case 'element':
      return _patternify((ast as MiniElement).source);
    case 'atom':
      final source = (ast as MiniAtom).source;
      if (source == '~' || source == '-') {
        final result = silence;
        _setMeta(result, weight: fraction(1));
        return result;
      }
      final numValue = num.tryParse(source);
      final value = numValue ?? source;
      final result = pure(value);
      _setMeta(result, weight: fraction(1));
      return result;
    case 'stretch':
      final op = ast as MiniOperator;
      final amount = op.arguments['amount'];
      final amountPat = amount is MiniNode ? _patternify(amount) : pure(amount);
      return _patternify(op.source).slow(amountPat);
    case 'scale':
      final op = ast as MiniOperator;
      final sourcePat = _patternify(op.source);
      final scaleValue = op.arguments['scale'];
      final scalePat =
          scaleValue is MiniNode ? _patternify(scaleValue) : pure(scaleValue);
      return scalePat.bind((value) => sourcePat.scale(value));
    default:
      return silence;
  }
}

Pattern _applyOptions(MiniElement element, Pattern pat) {
  final options = element.options;
  final ops = options.ops;
  final bool originalStepsSource = _metaFor(pat).stepsSource;

  for (final op in ops) {
    switch (op.type) {
      case 'replicate':
        final amount = op.arguments['amount'] as int;
        pat = pat.repeatCycles(amount).fast(amount);
        break;
      case 'stretch':
        final amount = op.arguments['amount'];
        final amountPat = amount is MiniNode ? _patternify(amount) : pure(amount);
        final type = op.arguments['type'] as String?;
        if (type == 'slow') {
          pat = pat.slow(amountPat);
        } else {
          pat = pat.fast(amountPat);
        }
        break;
      case 'bjorklund':
        final pulseNode = op.arguments['pulse'] as MiniNode;
        final stepNode = op.arguments['step'] as MiniNode;
        final pulsePat = _patternify(pulseNode);
        final stepPat = _patternify(stepNode);
        final base = pat;
        pat = pulsePat.bind((pulse) {
          return stepPat.map((step) {
            return base.euclid((pulse as num).toInt(), (step as num).toInt());
          });
        }).innerJoin();
        break;
      case 'degradeBy':
        final amount = op.arguments['amount'] as num? ?? 0.5;
        final seed = op.arguments['seed'] as int? ?? 0;
        pat = s.degradeByWith(s.rand.early(0.0003 * seed), amount, pat);
        break;
      case 'tail':
        final friend = _patternify(op.arguments['element'] as MiniNode);
        pat = pat
            .map((a) => (dynamic b) {
                  if (a is List) {
                    return [...a, b];
                  }
                  return [a, b];
                })
            .appLeft(friend);
        break;
      case 'range':
        final friend = _patternify(op.arguments['element'] as MiniNode);
        pat = _range(pat, friend);
        break;
      default:
        break;
    }
  }

  _setMeta(pat, stepsSource: _metaFor(pat).stepsSource || originalStepsSource);
  return pat;
}

Pattern _range(Pattern aPat, Pattern bPat) {
  List<num> _arrayRange(num start, num stop, [num step = 1]) {
    if (step == 0) return [start];
    final count = ((stop - start).abs() / step).floor() + 1;
    return List<num>.generate(
      count,
      (i) => start < stop ? start + i * step : start - i * step,
    );
  }

  return aPat.squeezeBind((a) {
    return bPat.bind((b) {
      final list = _arrayRange(a as num, b as num);
      return fastcat(list);
    });
  });
}

Pattern mini(String input) {
  _seed = 0;
  final quoted = '"$input"';
  final result = _krillParser.parse(quoted);
  if (result is Failure) {
    throw Exception(
      'MiniNotation parse error: ${result.message} at ${result.position}',
    );
  }
  final ast = result.value;
  if (ast is MiniNode) {
    return _patternify(ast);
  }
  if (ast is MiniCommand) {
    return silence;
  }
  if (ast is String) {
    return silence;
  }
  throw Exception('MiniNotation parse error: unexpected AST');
}
