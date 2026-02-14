import 'dart:async';

import 'package:strudel_dart/strudel_dart.dart';

class StrudelScheduler {
  StrudelScheduler({double interval = 0.025, double latency = 0.1}) {
    _cyclist = Cyclist(
      interval: interval,
      latency: latency,
      getTime: _nowSeconds,
      onTrigger: _handleTrigger,
      onError: _onError,
    );
    _cyclist.setCps(cps);
  }

  static double _nowSeconds() {
    return DateTime.now().microsecondsSinceEpoch / 1000000.0;
  }

  static void _onError(Object error) {
    // Keep scheduler resilient; surface the error in logs.
    print('StrudelScheduler: Cyclist error: $error');
  }

  double cps = 0.5;
  late final Cyclist _cyclist;
  final _hapController = StreamController<Hap>.broadcast();
  Stream<Hap> get haps => _hapController.stream;

  bool _started = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();

  void play(Pattern pattern) {
    _enqueue(() async {
      await _cyclist.setPattern(pattern);
      if (_started) return;
      await _cyclist.start();
      _started = true;
    });
  }

  void setCps(double newCps) {
    if (newCps == cps) return;
    cps = newCps;
    _cyclist.setCps(newCps);
  }

  void stop() {
    _cyclist.stop();
    _started = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _hapController.close();
  }

  void _enqueue(Future<void> Function() action) {
    _queue = _queue
        .then((_) async {
          if (_disposed) return;
          await action();
        })
        .catchError((Object error, StackTrace stackTrace) {
          print('StrudelScheduler: Async error: $error');
        });
  }

  void _emitTriggeredHap(Hap hap, double triggerCps, double targetTime) {
    if (_disposed) return;

    final scheduledMicros = (targetTime * 1000000).round();
    final scheduledTime = DateTime.fromMicrosecondsSinceEpoch(scheduledMicros);
    final context = {...hap.context, 'cps': triggerCps};
    final timedHap = Hap(
      hap.whole,
      hap.part,
      hap.value,
      context: context,
      stateful: hap.stateful,
      scheduledTime: scheduledTime,
    );

    final trigger = timedHap.context['onTrigger'];
    if (trigger is Function) {
      final nowSeconds = _nowSeconds();
      Function.apply(trigger, [timedHap, nowSeconds, triggerCps, targetTime]);
    }
    _hapController.add(timedHap);
  }

  void _handleTrigger(
    Hap hap,
    double deadline,
    double duration,
    double triggerCps,
    double targetTime,
  ) {
    if (deadline.isNaN || duration.isNaN) {
      return;
    }
    _emitTriggeredHap(hap, triggerCps, targetTime);
  }
}
