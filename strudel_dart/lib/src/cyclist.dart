import 'package:fraction/fraction.dart' as f;
import 'hap.dart';
import 'logger.dart';
import 'pattern.dart';
import 'state.dart';
import 'timespan.dart';
import 'zyklus.dart';

typedef TriggerCallback =
    void Function(
      Hap hap,
      double deadline,
      double duration,
      double cps,
      double targetTime,
    );

class Cyclist {
  final double interval;
  final TriggerCallback? onTrigger;
  final void Function(bool)? onToggle;
  final void Function(Object)? onError;
  final double Function() getTime;
  final double latency;
  final Future<void> Function()? beforeStart;

  bool started = false;
  double cps = 0.5;
  int numTicksSinceCpsChange = 0;
  double lastTick = 0;
  double lastBegin = 0;
  double lastEnd = 0;
  double numCyclesAtCpsChange = 0;
  double? secondsAtCpsChange;

  late final Clock _clock;
  Pattern? _pattern;

  Cyclist({
    required this.interval,
    required this.getTime,
    this.onTrigger,
    this.onToggle,
    this.onError,
    this.latency = 0.1,
    this.beforeStart,
  }) {
    _clock = Clock(
      getTime: getTime,
      duration: interval,
      interval: 0.1,
      overlap: 0.1,
      callback: _onTick,
    );
  }

  void _onTick(double phase, double duration, int _, double now) {
    if (numTicksSinceCpsChange == 0) {
      numCyclesAtCpsChange = lastEnd;
      secondsAtCpsChange = phase;
    }
    numTicksSinceCpsChange++;
    final secondsSinceCpsChange = numTicksSinceCpsChange * duration;
    final numCyclesSinceCpsChange = secondsSinceCpsChange * cps;

    try {
      final begin = lastEnd;
      lastBegin = begin;
      final end = numCyclesAtCpsChange + numCyclesSinceCpsChange;
      lastEnd = end;
      lastTick = phase;

      if (phase < now) {
        return;
      }

      final pattern = _pattern;
      if (pattern == null) {
        return;
      }

      final haps = pattern.queryArc(
        begin,
        end,
        controls: {'_cps': cps, 'cyclist': 'cyclist'},
      );

      for (final hap in haps) {
        if (!hap.hasOnset()) continue;
        final targetTime =
            (hap.whole!.begin.toDouble() - numCyclesAtCpsChange) / cps +
            (secondsAtCpsChange ?? phase) +
            latency;
        final durationSeconds = hap.duration.toDouble() / cps;
        final deadline = targetTime - phase;
        onTrigger?.call(hap, deadline, durationSeconds, cps, targetTime);
        if (hap.value is Map && (hap.value as Map).containsKey('cps')) {
          final nextCps = (hap.value as Map)['cps'];
          if (nextCps is num && cps != nextCps.toDouble()) {
            cps = nextCps.toDouble();
            numTicksSinceCpsChange = 0;
          }
        }
      }
    } catch (e) {
      errorLogger(e);
      onError?.call(e);
    }
  }

  double now() {
    if (!started) return 0;
    final secondsSinceLastTick = getTime() - lastTick - _clock.duration;
    return lastBegin + secondsSinceLastTick * cps;
  }

  void _setStarted(bool value) {
    started = value;
    onToggle?.call(value);
  }

  Future<void> start() async {
    if (beforeStart != null) {
      await beforeStart!();
    }
    numTicksSinceCpsChange = 0;
    numCyclesAtCpsChange = 0;
    if (_pattern == null) {
      throw StateError('Scheduler: no pattern set! call setPattern first.');
    }
    logger('[cyclist] start');
    _clock.start();
    _setStarted(true);
  }

  void pause() {
    logger('[cyclist] pause');
    _clock.pause();
    _setStarted(false);
  }

  void stop() {
    logger('[cyclist] stop');
    _clock.stop();
    lastEnd = 0;
    _setStarted(false);
  }

  Future<void> setPattern(Pattern pat, {bool autostart = false}) async {
    _pattern = pat;
    if (autostart && !started) {
      await start();
    }
  }

  void setCps([double nextCps = 0.5]) {
    if (cps == nextCps) return;
    cps = nextCps;
    numTicksSinceCpsChange = 0;
  }

  void log(double begin, double end, List<Hap> haps) {
    final onsets = haps.where((h) => h.hasOnset()).length;
    logger(
      '${begin.toStringAsFixed(4)} - ${end.toStringAsFixed(4)} '
      '${'I' * onsets}',
    );
  }
}
