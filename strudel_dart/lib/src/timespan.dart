import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';

class TimeSpan {
  final f.Fraction begin;
  final f.Fraction end;

  TimeSpan(dynamic begin, dynamic end)
    : begin = fraction(begin),
      end = fraction(end);

  List<TimeSpan> get spanCycles {
    final spans = <TimeSpan>[];
    f.Fraction currentBegin = begin;
    final f.Fraction currentEnd = end;
    final f.Fraction endSam = currentEnd.sam();

    if (currentBegin == currentEnd) {
      return [TimeSpan(currentBegin, currentEnd)];
    }

    while (currentEnd > currentBegin) {
      if (currentBegin.sam() == endSam) {
        spans.push(TimeSpan(currentBegin, currentEnd));
        break;
      }
      final nextBegin = currentBegin.nextSam();
      spans.push(TimeSpan(currentBegin, nextBegin));
      currentBegin = nextBegin;
    }
    return spans;
  }

  f.Fraction get duration => end - begin;

  TimeSpan cycleArc() {
    final b = begin.cyclePos();
    final e = b + duration;
    return TimeSpan(b, e);
  }

  TimeSpan wholeCycle() => TimeSpan(begin.sam(), begin.nextSam());

  TimeSpan withTime(f.Fraction Function(f.Fraction) func) {
    return TimeSpan(func(begin), func(end));
  }

  TimeSpan withCycle(f.Fraction Function(f.Fraction) func) {
    final cycle = begin.sam();
    return TimeSpan(cycle + func(begin - cycle), cycle + func(end - cycle));
  }

  TimeSpan? intersection(TimeSpan other) {
    final intersectBegin = begin.max(other.begin);
    final intersectEnd = end.min(other.end);

    if (intersectBegin > intersectEnd) {
      return null;
    }

    if (intersectBegin == intersectEnd) {
      if (intersectBegin == end && begin < end) {
        return null;
      }
      if (intersectBegin == other.end && other.begin < other.end) {
        return null;
      }
    }
    return TimeSpan(intersectBegin, intersectEnd);
  }

  bool equals(TimeSpan other) {
    return begin == other.begin && end == other.end;
  }

  String show() => '${begin.show()} → ${end.show()}';

  @override
  String toString() => show();
}

extension ListPush<T> on List<T> {
  void push(T element) => add(element);
}
