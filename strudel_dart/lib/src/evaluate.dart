import 'pattern.dart';
import 'repl.dart';

final Map<String, dynamic> strudelScope = {};

Future<List<Map<String, dynamic>>> evalScope(
  Iterable<Future<Map<String, dynamic>>> modules,
) async {
  final results = await Future.wait(modules);
  for (final module in results) {
    strudelScope.addAll(module);
  }
  return results;
}

class EvaluateResult {
  final String mode;
  final Pattern pattern;
  final Map<String, dynamic> meta;

  const EvaluateResult({
    required this.mode,
    required this.pattern,
    this.meta = const {},
  });
}

Future<EvaluateResult> evaluate(String code, {StrudelREPL? repl}) async {
  final parser = repl ?? StrudelREPL();
  final pattern = parser.evaluate(code);
  return EvaluateResult(mode: 'strudel', pattern: pattern);
}
