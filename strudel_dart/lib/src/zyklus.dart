import 'dart:async';

typedef ClockCallback =
    void Function(double phase, double duration, int tick, double now);

class Clock {
  final double Function() getTime;
  final ClockCallback callback;
  double duration;
  final double interval;
  final double overlap;
  final bool round;

  int _tick = 0;
  double _phase = 0;
  final int _precision = 10000;
  final double minLatency = 0.01;
  Timer? _timer;

  Clock({
    required this.getTime,
    required this.callback,
    this.duration = 0.05,
    this.interval = 0.1,
    double? overlap,
    this.round = true,
  }) : overlap = overlap ?? 0.05;

  void setDuration(double Function(double) setter) {
    duration = setter(duration);
  }

  void _onTick() {
    final now = getTime();
    final lookahead = now + interval + overlap;
    if (_phase == 0) {
      _phase = now + minLatency;
    }
    while (_phase < lookahead) {
      final phase = round ? (_phase * _precision).round() / _precision : _phase;
      callback(phase, duration, _tick, now);
      _phase += duration;
      _tick++;
    }
  }

  void start() {
    stop();
    _onTick();
    _timer = Timer.periodic(
      Duration(milliseconds: (interval * 1000).round()),
      (_) => _onTick(),
    );
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void stop() {
    _tick = 0;
    _phase = 0;
    _timer?.cancel();
    _timer = null;
  }

  double getPhase() => _phase;
}
