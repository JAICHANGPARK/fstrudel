import 'package:petitparser/petitparser.dart';
import 'controls.dart' as c;
import 'pattern.dart' as p;

class StrudelREPL {
  late final Parser _parser;
  void Function(double)? onCpsChange;

  StrudelREPL({this.onCpsChange}) {
    _parser = StrudelGrammarDefinition(onCpsChange: onCpsChange).build();
  }

  p.Pattern evaluate(String input) {
    final lines = input.split('\n');
    final patterns = <p.Pattern>[];

    for (var line in lines) {
      line = line.trim();
      if (line.startsWith(
        r'$'
        ':',
      )) {
        final code = line.substring(2).trim();
        if (code.isNotEmpty) {
          final result = _parser.parse(code);
          if (result is Failure) {
            throw Exception(
              'Parse error in line "$line": ${result.message} at ${result.position}',
            );
          }
          patterns.add(result.value as p.Pattern);
        }
      }
    }

    if (patterns.isEmpty) {
      // If no $: prefix found, try parsing the whole input as a single expression
      // (maintaining backward compatibility or supporting single expression without prefix)
      String code = input.trim();
      if (code.startsWith(
        r'$'
        ':',
      )) {
        code = code.substring(2).trim();
      }
      if (code.isEmpty) return p.silence;
      final result = _parser.parse(code);
      if (result is Failure) {
        throw Exception('Parse error: ${result.message} at ${result.position}');
      }
      return result.value as p.Pattern;
    }

    if (patterns.length == 1) {
      return patterns[0];
    }

    return p.stack(patterns);
  }
}

class StrudelGrammarDefinition extends GrammarDefinition {
  final void Function(double)? onCpsChange;

  StrudelGrammarDefinition({this.onCpsChange});

  @override
  Parser start() => ref0(expression).end();

  Parser expression() => ref0(methodChain);

  Parser methodChain() => ref0(atom).seq(ref0(methodCall).star()).map((values) {
    var result = values[0];
    final calls = values[1] as List;
    for (final call in calls) {
      final methodName = call[0] as String;
      final args = call[1] as List;
      result = _invokeMethod(result, methodName, args);
    }
    return result;
  });

  Parser atom() =>
      ref0(functionCall) |
      ref0(parenthesizedExpression) |
      ref0(literal) |
      ref0(identifier).map((id) => _resolveIdentifier(id));

  Parser parenthesizedExpression() =>
      (char('(').trim() & ref0(expression) & char(')').trim()).map((v) => v[1]);

  Parser functionCall() => (ref0(identifier) & ref0(arguments)).map((values) {
    final name = values[0] as String;
    final args = values[1] as List;
    return _invokeFunction(name, args);
  });

  Parser methodCall() =>
      (char('.').trim() & ref0(identifier) & ref0(arguments)).map((values) {
        return [values[1], values[2]];
      });

  Parser arguments() =>
      (char('(').trim() & ref0(expressionList).optional() & char(')').trim())
          .map((values) => values[1] ?? []);

  Parser expressionList() => ref0(
    expression,
  ).plusSeparated(char(',').trim()).map((values) => values.elements);

  Parser literal() => ref0(stringLiteral) | ref0(numberLiteral);

  Parser stringLiteral() =>
      ((char("'") & any().starLazy(char("'")).flatten() & char("'")).pick(1) |
              (char('"') & any().starLazy(char('"')).flatten() & char('"'))
                  .pick(1))
          .trim();

  Parser numberLiteral() =>
      ((char('-').optional() &
                  ((digit().plus() & (char('.') & digit().plus()).optional()) |
                      (char('.') & digit().plus())))
              .flatten()
              .map(num.parse))
          .trim();

  Parser identifier() =>
      (letter() & (word() | char('_')).star()).flatten().trim();

  dynamic _resolveIdentifier(String name) {
    switch (name) {
      case 'rev':
        return (dynamic x) => (x as p.Pattern).rev() as dynamic;
      default:
        // fallback to string for things like bank names?
        // or throw? For now return string to be safe for reification
        return name;
    }
  }

  dynamic _invokeFunction(String name, List args) {
    switch (name) {
      case 's':
      case 'sound':
        return c.s(args.isEmpty ? '' : args[0]);
      case 'n':
        return c.n(args.isEmpty ? '' : args[0]);
      case 'note':
        return c.note(args.isEmpty ? '' : args[0]);
      case 'gain':
        return c.gain(args.isEmpty ? 1.0 : args[0]);
      case 'pan':
        return c.pan(args.isEmpty ? 0.5 : args[0]);
      case 'speed':
        return c.speed(args.isEmpty ? 1.0 : args[0]);
      case 'velocity':
        return c.velocity(args.isEmpty ? 1.0 : args[0]);
      case 'vowel':
        return c.vowel(args.isEmpty ? '' : args[0]);
      case 'lpf':
        return c.lpf(args.isEmpty ? 0.0 : args[0]);
      case 'hpf':
        return c.hpf(args.isEmpty ? 0.0 : args[0]);
      case 'bank':
        return c.bank(args.isEmpty ? '' : args[0]);
      case 'dec':
        return c.dec(args.isEmpty ? 0.0 : args[0]);
      case 'stack':
        return p.stack(args);
      case 'sequence':
        return p.sequence(args);
      case 'setcps':
      case 'cps':
        final val = args.isEmpty ? 0.5 : (args[0] as num).toDouble();
        onCpsChange?.call(val);
        return p.silence;
      case 'setbpm':
      case 'bpm':
        final val = args.isEmpty ? 120.0 : (args[0] as num).toDouble();
        onCpsChange?.call(val / 240.0);
        return p.silence;
      case 'attack':
        return c.attack(args[0]);
      case 'decay':
        return c.decay(args[0]);
      case 'sustain':
        return c.sustain(args[0]);
      case 'release':
        return c.release(args[0]);
      case 'lpq':
        return c.lpq(args[0]);
      case 'hpq':
        return c.hpq(args[0]);
      case 'bandf':
        return c.bandf(args[0]);
      case 'bandq':
        return c.bandq(args[0]);
      case 'room':
        return c.room(args[0]);
      case 'size':
        return c.size(args[0]);
      case 'dry':
        return c.dry(args[0]);
      case 'delay':
        return c.delay(args[0]);
      case 'delaytime':
        return c.delaytime(args[0]);
      case 'delayfeedback':
        return c.delayfeedback(args[0]);
      case 'crush':
        return c.crush(args[0]);
      case 'coarse':
        return c.coarse(args[0]);
      case 'shape':
        return c.shape(args[0]);
      case 'cutoff':
        return c.cutoff(args[0]);
      case 'resonance':
        return c.resonance(args[0]);
      default:
        throw Exception('Unknown function: $name');
    }
  }

  dynamic _invokeMethod(dynamic receiver, String name, List args) {
    if (receiver is! p.Pattern) {
      // If it's a literal, we can't call methods on it in this simple REPL
      // unless we promote it to a Pattern.
      receiver = p.reify(receiver);
    }

    final dynamic pattern = receiver;

    switch (name) {
      case 's':
      case 'sound':
        return (pattern as p.Pattern<c.ControlMap>).s(args[0]);
      case 'n':
        return (pattern as p.Pattern<c.ControlMap>).n(args[0]);
      case 'note':
        return (pattern as p.Pattern<c.ControlMap>).note(args[0]);
      case 'gain':
        return (pattern as p.Pattern<c.ControlMap>).gain(args[0]);
      case 'pan':
        return (pattern as p.Pattern<c.ControlMap>).pan(args[0]);
      case 'speed':
        return (pattern as p.Pattern<c.ControlMap>).speed(args[0]);
      case 'velocity':
        return (pattern as p.Pattern<c.ControlMap>).velocity(args[0]);
      case 'vowel':
        return (pattern as p.Pattern<c.ControlMap>).vowel(args[0]);
      case 'lpf':
        return (pattern as p.Pattern<c.ControlMap>).lpf(args[0]);
      case 'hpf':
        return (pattern as p.Pattern<c.ControlMap>).hpf(args[0]);
      case 'bank':
        return (pattern as p.Pattern<c.ControlMap>).bank(args[0]);
      case 'dec':
        return (pattern as p.Pattern<c.ControlMap>).dec(args[0]);
      case 'fast':
        return pattern.fast(args[0]);
      case 'slow':
        return pattern.slow(args[0]);
      case 'rev':
        return pattern.rev();
      case 'overlay':
        return (pattern as p.Pattern<c.ControlMap>).overlay(args[0]);
      case 'cat':
        return (pattern as p.Pattern<c.ControlMap>).cat(args);
      case 'attack':
        return (pattern as p.Pattern<c.ControlMap>).attack(args[0]);
      case 'decay':
        return (pattern as p.Pattern<c.ControlMap>).decay(args[0]);
      case 'sustain':
        return (pattern as p.Pattern<c.ControlMap>).sustain(args[0]);
      case 'release':
        return (pattern as p.Pattern<c.ControlMap>).release(args[0]);
      case 'lpq':
        return (pattern as p.Pattern<c.ControlMap>).lpq(args[0]);
      case 'hpq':
        return (pattern as p.Pattern<c.ControlMap>).hpq(args[0]);
      case 'bandf':
        return (pattern as p.Pattern<c.ControlMap>).bandf(args[0]);
      case 'bandq':
        return (pattern as p.Pattern<c.ControlMap>).bandq(args[0]);
      case 'room':
        return (pattern as p.Pattern<c.ControlMap>).room(args[0]);
      case 'size':
        return (pattern as p.Pattern<c.ControlMap>).size(args[0]);
      case 'dry':
        return (pattern as p.Pattern<c.ControlMap>).dry(args[0]);
      case 'delay':
        return (pattern as p.Pattern<c.ControlMap>).delay(args[0]);
      case 'delaytime':
        return (pattern as p.Pattern<c.ControlMap>).delaytime(args[0]);
      case 'delayfeedback':
        return (pattern as p.Pattern<c.ControlMap>).delayfeedback(args[0]);
      case 'crush':
        return (pattern as p.Pattern<c.ControlMap>).crush(args[0]);
      case 'coarse':
        return (pattern as p.Pattern<c.ControlMap>).coarse(args[0]);
      case 'shape':
        return (pattern as p.Pattern<c.ControlMap>).shape(args[0]);
      case 'cutoff':
        return (pattern as p.Pattern<c.ControlMap>).cutoff(args[0]);
      case 'resonance':
        return (pattern as p.Pattern<c.ControlMap>).resonance(args[0]);
      case 'every':
        return (pattern as p.Pattern<c.ControlMap>).every(
          args[0] as int,
          (x) => (args[1] as Function)(x) as p.Pattern<c.ControlMap>,
        );
      case 'degradeBy':
        return pattern.degradeBy((args[0] as num).toDouble());
      case 'jux':
        // args[0] is function
        return (pattern as p.Pattern<c.ControlMap>).jux(
          (x) => (args[0] as Function)(x) as p.Pattern<c.ControlMap>,
        );
      default:
        throw Exception('Unknown method: $name');
    }
  }
}
