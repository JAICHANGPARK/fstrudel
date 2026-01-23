import 'dart:async';
import 'package:strudel_dart/strudel_dart.dart';

class StrudelScheduler {
  double cps = 0.5; // Cycles per second (default 0.5 = 120bpm for 4/4)
  Pattern? _pattern;
  DateTime? _startTime;
  DateTime? _lastCpsChangeTime;
  double _baseCycle = 0;

  final _hapController = StreamController<Hap>.broadcast();
  Stream<Hap> get haps => _hapController.stream;

  Timer? _timer;
  double _lastQueryEndCycle = 0;
  final double lookahead = 0.1; // 100ms lookahead

  void play(Pattern pattern) {
    _pattern = pattern;
    _startTime = DateTime.now();
    _lastCpsChangeTime = _startTime;
    _baseCycle = 0;
    _lastQueryEndCycle = 0;
    _startTimer();
  }

  void setCps(double newCps) {
    if (newCps == cps) return;

    final now = DateTime.now();
    if (_startTime != null && _lastCpsChangeTime != null) {
      // Calculate cycle reached at old tempo
      final elapsedSinceChange =
          now.difference(_lastCpsChangeTime!).inMicroseconds / 1000000.0;
      _baseCycle += elapsedSinceChange * cps;
    }
    _lastCpsChangeTime = now;
    cps = newCps;

    // We don't reset _lastQueryEndCycle because we want to continue from where we are
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _tick();
    });
  }

  void _tick() {
    if (_startTime == null || _pattern == null) return;

    final now = DateTime.now();
    final elapsedSinceChange =
        now.difference(_lastCpsChangeTime!).inMicroseconds / 1000000.0;
    final currentCycle = _baseCycle + (elapsedSinceChange * cps);

    final queryEndCycle = currentCycle + (lookahead * cps);

    if (queryEndCycle > _lastQueryEndCycle) {
      final haps = _pattern!.onsetsOnly().queryArc(
        _lastQueryEndCycle,
        queryEndCycle,
      );
      for (final hap in haps) {
        final onsetCycleDouble = hap.whole!.begin.toDouble();

        // Calculate the time this cycle occurs, relative to the last tempo change
        final cycleOffset = onsetCycleDouble - _baseCycle;
        final onsetElapsedSecondsSinceChange = cycleOffset / cps;
        final scheduledTime = _lastCpsChangeTime!.add(
          Duration(
            microseconds: (onsetElapsedSecondsSinceChange * 1000000).toInt(),
          ),
        );

        final timedHap = Hap(
          hap.whole,
          hap.part,
          hap.value,
          context: hap.context,
          stateful: hap.stateful,
          scheduledTime: scheduledTime,
        );
        final trigger = timedHap.context['onTrigger'];
        if (trigger is Function) {
          final nowSeconds =
              DateTime.now().millisecondsSinceEpoch / 1000.0;
          final targetSeconds =
              scheduledTime.millisecondsSinceEpoch / 1000.0;
          Function.apply(trigger, [timedHap, nowSeconds, cps, targetSeconds]);
        }
        _hapController.add(timedHap);
      }
      _lastQueryEndCycle = queryEndCycle;
    }
  }

  void dispose() {
    stop();
    _hapController.close();
  }
}
