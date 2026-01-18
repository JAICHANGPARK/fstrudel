import 'package:strudel_dart/strudel_dart.dart';
import 'package:test/test.dart';
import 'package:strudel_dart/src/repl.dart';

void main() {
  group('New Features', () {
    test('Euclidean Rhythms', () {
      final p = euclid(3, 8);
      final haps = p.queryArc(0, 1);
      expect(haps.where((h) => h.value == 1).length, 3);
    });

    test('Struct', () {
      final s = sequence([1, 0, 1]);
      final target = pure("a");
      final structured = target.struct(s);
      final haps = structured.queryArc(0, 1);
      expect(haps.length, 2);
    });

    test('REPL Multiline', () {
      final repl = StrudelREPL();
      // Case 1: Multiple expressions without prefix
      // Use escaped quotes for better Dart string literal safety or single quotes
      final p1 = repl.evaluate('setcpm(100)\ns("bd")');
      final haps1 = p1.queryArc(0, 1);
      expect(haps1.length, 1);
      expect(haps1[0].value['s'], "bd");

      // Case 2: Expressions with whitespace
      final p2 = repl.evaluate('s("bd")\ns("sn")');
      final haps2 = p2.queryArc(0, 1);
      expect(haps2.length, 2);
    });

    test("Numeric Arithmetic", () {
      final repl = StrudelREPL();
      final p = repl.evaluate('s("bd").gain(1/2)');
      final haps = p.queryArc(0, 1);
      expect(haps.first.value["gain"], 0.5);

      final p2 = repl.evaluate('s("bd") * 2');
      final haps2 = p2.queryArc(0, 1);
      expect(haps2.isNotEmpty, true);
    });

    test("Backtick Strings", () {
      final repl = StrudelREPL();
      // Use raw string for backticks to make it easier to write the test
      final p = repl.evaluate(r"s(`bd sd`)");
      final haps = p.queryArc(0, 1);
      // Should parse as s("bd sd") -> sequence of 2 events
      expect(haps.length, 2);
      expect(haps[0].value["s"], "bd");
      expect(haps[1].value["s"], "sd");
    });
  });
}
