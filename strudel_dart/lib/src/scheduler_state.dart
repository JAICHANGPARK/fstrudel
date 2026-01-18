import 'pattern.dart';

double Function()? _time;
double Function()? _cpsFunc;
Pattern? _pattern;
dynamic Function()? _triggerFunc;
bool _isStarted = false;

double getTime() {
  final time = _time;
  if (time == null) {
    throw StateError('no time set! use setTime to define a time source');
  }
  return time();
}

void setTime(double Function() func) {
  _time = func;
}

void setCpsFunc(double Function() func) {
  _cpsFunc = func;
}

double? getCps() => _cpsFunc?.call();

void setPattern(Pattern pat) {
  _pattern = pat;
}

Pattern? getPattern() => _pattern;

void setTriggerFunc(dynamic Function() func) {
  _triggerFunc = func;
}

dynamic Function()? getTriggerFunc() => _triggerFunc;

void setIsStarted(bool val) {
  _isStarted = val;
}

bool getIsStarted() => _isStarted;
