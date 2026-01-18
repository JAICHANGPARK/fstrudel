import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';
import 'hap.dart';
import 'pattern.dart';
import 'state.dart';
import 'timespan.dart';

final Map<dynamic, f.Fraction> _timelines = {};

void resetState() {
  resetTimelines();
}

void resetTimelines() {
  _timelines.clear();
}

extension PatternTimelineExtension<T> on Pattern<T> {
  Pattern<T> timeline(dynamic timelinePattern) {
    final tpat = reify<dynamic>(timelinePattern);
    return Pattern<T>((state) {
      final scheduler = state.controls.containsKey('cyclist');
      final timeHaps = tpat.query(state);
      final result = <Hap<T>>[];
      for (final timehap in timeHaps) {
        final tlid = timehap.value;
        f.Fraction offset;
        if (tlid == 0) {
          offset = fraction(0);
        } else if (_timelines.containsKey(tlid)) {
          offset = _timelines[tlid]!;
        } else {
          final timeArc = timehap.wholeOrPart();
          final midpoint = timeArc.begin + (timeArc.duration / fraction(2));
          if (!scheduler || state.span.begin.lt(midpoint)) {
            offset = timeArc.begin;
          } else {
            offset = timeArc.end;
          }
        }

        if (scheduler) {
          _timelines[tlid] = offset;
          if (tlid != 0) {
            _timelines.remove(-tlid);
          }
        }

        final pathaps = this
            .late(offset)
            .query(state.setSpan(timehap.part))
            .map((h) => h.setContext(h.combineContext(timehap)));
        result.addAll(pathaps);
      }
      return result;
    }, steps: steps);
  }
}
