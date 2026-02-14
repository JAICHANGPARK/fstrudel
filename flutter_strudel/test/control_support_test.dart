import 'package:flutter_strudel/src/control_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects unsupported controls', () {
    final report = ControlSupportMatrix.evaluate({
      'gain': 1.0,
      'vowel': 'a',
      '_cps': 0.5,
    });

    expect(report.unsupported, contains('vowel'));
    expect(report.partial, isEmpty);
  });

  test('detects partially supported controls', () {
    final report = ControlSupportMatrix.evaluate({
      'delay': 0.3,
      'duck': 0.8,
      'gain': 0.9,
    });

    expect(report.unsupported, isEmpty);
    expect(report.partial, contains('delay'));
    expect(report.partial, contains('duck'));
  });

  test('formats keys in sorted order', () {
    final formatted = ControlSupportMatrix.formatKeys({
      'duck',
      'delay',
      'bandf',
    });
    expect(formatted, 'bandf, delay, duck');
  });
}
