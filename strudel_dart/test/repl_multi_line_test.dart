import 'package:test/test.dart';
import 'package:strudel_dart/strudel_dart.dart';
import 'package:strudel_dart/src/repl.dart';
import 'package:strudel_dart/src/pattern.dart';

void main() {
  group('StrudelREPL Multi-line Support', () {
    late StrudelREPL repl;

    setUp(() {
      repl = StrudelREPL();
    });

    test('evaluates single line with \$: prefix', () {
      final pattern = repl.evaluate(r'$: s("bd")');
      expect(pattern, isA<Pattern>());
    });

    test('evaluates multiple lines with \$: prefix', () {
      final input = r'''
$: s("bd")
$: s("hh")
''';
      final pattern = repl.evaluate(input);
      expect(pattern, isA<Pattern>());
      // Should be a stack of two patterns
      expect(
        pattern.toString(),
        contains('steps: 1'),
      ); // stack of 1-cycle patterns
    });

    test('supports sound() as alias for s()', () {
      final pattern = repl.evaluate(r'$: sound("jazz")');
      expect(pattern, isA<Pattern>());
    });

    test('supports sound() as method alias', () {
      final pattern = repl.evaluate(r'$: n("0 1").sound("jazz")');
      expect(pattern, isA<Pattern>());
    });

    test('backward compatibility for input without prefix', () {
      final pattern = repl.evaluate('s("bd")');
      expect(pattern, isA<Pattern>());
    });
  });
}
