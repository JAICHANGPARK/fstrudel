import 'package:flutter_test/flutter_test.dart';
import 'package:strudel_dart/strudel_dart.dart';
import 'package:flutter_strudel/src/scheduler.dart';
import 'dart:async';

void main() {
  test('Scheduler emits haps for a simple pattern', () async {
    final scheduler = StrudelScheduler();
    final pattern = mini('bd sd');

    // Direct query test
    final directHaps = pattern.queryArc(0, 0.1);
    print('Direct query haps: ${directHaps.length}');
    for (final h in directHaps) print('  Hap: ${h.value} at ${h.part}');

    final haps = <Hap>[];

    final subscription = scheduler.haps.listen((hap) {
      print('Scheduler emitted: ${hap.value}');
      haps.add(hap);
    });

    scheduler.play(pattern);

    // Wait for a bit to collect haps
    await Future.delayed(const Duration(milliseconds: 500));

    scheduler.stop();
    subscription.cancel();

    print('Total haps: ${haps.length}');
    expect(haps.length, greaterThan(0));
    expect(haps.any((h) => h.value == 'bd'), isTrue);
  });
}
