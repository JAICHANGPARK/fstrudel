import 'dart:math' as math;
import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';
import 'hap.dart';
import 'state.dart';
import 'timespan.dart';
import 'bjorklund.dart';

typedef Query<T> = List<Hap<T>> Function(StrudelState state);

class Pattern<T> {
  final Query<T> query;
  final f.Fraction? _steps;

  Pattern(this.query, {f.Fraction? steps}) : _steps = steps;

  f.Fraction? get steps => _steps;

  Pattern<T> setSteps(f.Fraction steps) {
    return Pattern(query, steps: steps);
  }

  Pattern<R> map<R>(R Function(T) func) {
    return Pattern(
      (state) => query(state).map((hap) => hap.withValue(func)).toList(),
      steps: _steps,
    );
  }

  List<Hap<T>> queryArc(dynamic begin, dynamic end) {
    return query(StrudelState(TimeSpan(fraction(begin), fraction(end))));
  }

  Pattern<T> withQuerySpan(TimeSpan Function(TimeSpan) func) {
    return Pattern((state) => query(state.withSpan(func)), steps: _steps);
  }

  Pattern<T> withQueryTime(f.Fraction Function(f.Fraction) func) {
    return withQuerySpan((span) => span.withTime(func));
  }

  Pattern<T> withHapSpan(TimeSpan Function(TimeSpan) func) {
    return Pattern(
      (state) => query(state).map((hap) => hap.withSpan(func)).toList(),
      steps: _steps,
    );
  }

  Pattern<T> withHapTime(f.Fraction Function(f.Fraction) func) {
    return withHapSpan((span) => span.withTime(func));
  }

  Pattern<T> fast(dynamic factor) {
    final f.Fraction fFactor = fraction(factor);
    return withQueryTime((t) => t * fFactor)
        .withHapTime((t) => t / fFactor)
        .setSteps((_steps ?? fraction(1)) * fFactor);
  }

  Pattern<T> slow(dynamic factor) {
    final f.Fraction fFactor = fraction(factor);
    return withQueryTime((t) => t / fFactor)
        .withHapTime((t) => t * fFactor)
        .setSteps((_steps ?? fraction(1)) / fFactor);
  }

  Pattern<T> withHaps(List<Hap<T>> Function(List<Hap<T>>, StrudelState) func) {
    return Pattern((state) => func(query(state), state), steps: _steps);
  }

  Pattern<T> onsetsOnly() {
    return withHaps((haps, _) => haps.where((hap) => hap.hasOnset()).toList());
  }

  Pattern<T> discreteOnly() {
    return withHaps(
      (haps, _) => haps.where((hap) => hap.whole != null).toList(),
    );
  }

  Pattern<T> zoom(dynamic begin, dynamic end) {
    final f.Fraction fBegin = fraction(begin);
    final f.Fraction fEnd = fraction(end);
    final f.Fraction d = fEnd - fBegin;

    return Pattern((state) {
      final zoomState = state.withSpan(
        (span) => span.withCycle((t) => fBegin + (t * d)),
      );
      return query(zoomState).map((hap) {
        return hap.withSpan((span) => span.withCycle((t) => (t - fBegin) / d));
      }).toList();
    }, steps: _steps != null ? _steps * d : null);
  }

  @override
  String toString() => 'Pattern(steps: $_steps)';

  Pattern<T> rev() {
    return Pattern((state) {
      final cycle = state.span.begin.sam();
      f.Fraction revTime(f.Fraction t) => cycle + fraction(1) - (t - cycle);

      final revSpan = TimeSpan(
        revTime(state.span.end),
        revTime(state.span.begin),
      );

      return query(state.setSpan(revSpan)).map((hap) {
        return hap.withSpan(
          (span) => TimeSpan(revTime(span.end), revTime(span.begin)),
        );
      }).toList();
    }, steps: _steps);
  }

  Pattern<T> every(int n, Pattern<T> Function(Pattern<T>) func) {
    final transformed = func(this);
    return Pattern((state) {
      final List<Hap<T>> results = [];
      for (final subspan in state.span.spanCycles) {
        final int cycle = (subspan.begin.toDouble()).floor();
        // print('DEBUG: every check cycle $cycle n=$n mod=${cycle % n}');
        if (cycle % n == 0) {
          results.addAll(transformed.query(state.setSpan(subspan)));
        } else {
          results.addAll(query(state.setSpan(subspan)));
        }
      }
      return results;
    }, steps: _steps);
  }

  Pattern<T> degradeBy(double chance) {
    return withHaps((haps, _) {
      final r = math.Random();
      return haps.where((h) => r.nextDouble() > chance).toList();
    });
  }
  // Applicative / Monadic

  Pattern<dynamic> appWhole(
    TimeSpan? Function(TimeSpan?, TimeSpan?) wholeFunc,
    Pattern other,
  ) {
    return Pattern((state) {
      final hapFuncs = query(state);
      final hapVals = other.query(state);
      final List<Hap<dynamic>> results = [];

      for (final hf in hapFuncs) {
        for (final hv in hapVals) {
          final s = hf.part.intersection(hv.part);
          if (s != null) {
            final val = (hf.value as Function)(hv.value);
            results.add(
              Hap(
                wholeFunc(hf.whole, hv.whole),
                s,
                val,
                context: hv.combineContext(hf),
              ),
            );
          }
        }
      }
      return results;
    }, steps: _steps); // TODO: lcm of steps?
  }

  Pattern<dynamic> appBoth(Pattern other) {
    return appWhole((a, b) {
      if (a == null || b == null) return null;
      return a.intersection(b);
    }, other);
  }

  Pattern<dynamic> appLeft(Pattern other) {
    return Pattern((state) {
      final haps = <Hap<dynamic>>[];
      for (final hf in query(state)) {
        final hapVals = other.query(state.setSpan(hf.wholeOrPart()));
        for (final hv in hapVals) {
          final newPart = hf.part.intersection(hv.part);
          if (newPart != null) {
            final val = (hf.value as Function)(hv.value);
            haps.add(
              Hap(hf.whole, newPart, val, context: hv.combineContext(hf)),
            );
          }
        }
      }
      return haps;
    }, steps: _steps);
  }

  Pattern<dynamic> appRight(Pattern other) {
    return Pattern((state) {
      final haps = <Hap<dynamic>>[];
      for (final hv in other.query(state)) {
        final hapFuncs = query(state.setSpan(hv.wholeOrPart()));
        for (final hf in hapFuncs) {
          final newPart = hf.part.intersection(hv.part);
          if (newPart != null) {
            final val = (hf.value as Function)(hv.value);
            haps.add(
              Hap(hv.whole, newPart, val, context: hv.combineContext(hf)),
            );
          }
        }
      }
      return haps;
    }, steps: other.steps);
  }

  // Monadic

  Pattern<dynamic> bindWhole(
    TimeSpan? Function(TimeSpan?, TimeSpan?) chooseWhole,
    Pattern Function(T) func,
  ) {
    return Pattern((state) {
      final haps = query(state);
      final List<Hap<dynamic>> results = [];
      for (final h in haps) {
        final innerPat = func(h.value);
        final innerHaps = innerPat.query(state.setSpan(h.part));
        for (final inh in innerHaps) {
          results.add(
            Hap(
              chooseWhole(h.whole, inh.whole),
              inh.part,
              inh.value,
              context: h.combineContext(inh),
            ),
          );
        }
      }
      return results;
    }, steps: _steps);
  }

  Pattern<dynamic> outerBind(Pattern Function(T) func) {
    return bindWhole((a, b) => a, func).setSteps(steps ?? fraction(1));
  }

  Pattern<dynamic> outerJoin() => outerBind((x) => x as Pattern);

  Pattern<dynamic> innerBind(Pattern Function(T) func) {
    return bindWhole((a, b) => b, func);
  }

  Pattern<dynamic> innerJoin() => innerBind((x) => x as Pattern);

  Pattern<dynamic> bind(Pattern Function(T) func) {
    return bindWhole((a, b) {
      if (a == null || b == null) return null;
      return a.intersection(b);
    }, func);
  }

  Pattern<dynamic> join() => bind((x) => x as Pattern);

  // Arithmetic

  Pattern<dynamic> _opIn(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    return map(op).appLeft(reify(other));
  }

  Pattern<dynamic> add(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is Map && b is Map) return {...a, ...b};
      if (a is num && b is num) return a + b;
      if (a is String && b is String) return a + b;
      return a; // fallback?
    },
  );

  Pattern<dynamic> sub(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a - b;
      return a;
    },
  );

  Pattern<dynamic> mul(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a * b;
      return a;
    },
  );

  Pattern<dynamic> div(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a / b;
      return a;
    },
  );

  Pattern<dynamic> mod(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a % b;
      return a;
    },
  );

  Pattern<dynamic> layer(List<Pattern Function(Pattern)> funcs) {
    return stack(funcs.map((f) => f(this)).toList());
  }

  // Structure
  Pattern<R> cast<R>() {
    return Pattern((state) {
      return query(state)
          .map(
            (h) => Hap<R>(
              h.whole,
              h.part,
              h.value as R,
              context: h.context,
              stateful: h.stateful,
              scheduledTime: h.scheduledTime,
            ),
          )
          .toList();
    }, steps: _steps);
  }

  // Structure
  Pattern<T> struct(Pattern structure) {
    return structure.bind((v) {
      bool isTrue = false;
      if (v is num && v != 0) isTrue = true;
      if (v is bool && v) isTrue = true;
      if (v is String && v != '~' && v != '') isTrue = true;

      if (isTrue) return this;
      return silence.cast<T>();
    }).cast<T>();
  }

  Pattern<T> mask(Pattern structure) => struct(structure);

  Pattern<T> euclid(int k, int n) {
    final seq = bjorklund(k, n);
    return struct(sequence(seq));
  }
}

Pattern<R> sequence<R>(List<dynamic> pats) => fastcat<R>(pats);

Pattern<T> slowcat<T>(List<dynamic> pats) {
  final reifiedPats = pats.map((p) => reify<T>(p)).toList();

  if (reifiedPats.isEmpty) {
    return Pattern((state) => []);
  }
  if (reifiedPats.length == 1) {
    return reifiedPats[0];
  }

  return Pattern((state) {
    final span = state.span;
    // We only support single-cycle queries for now in this simple slowcat
    // Strudel does more clever things to handle multi-cycle queries.
    // But it requires splitting the span.
    final List<Hap<T>> results = [];
    for (final subspan in span.spanCycles) {
      final patIndex =
          (subspan.begin.numerator ~/ subspan.begin.denominator) %
          reifiedPats.length;
      final pat = reifiedPats[patIndex];
      // offset calculation from Strudel
      final f.Fraction offset =
          subspan.begin.sam() -
          (subspan.begin / fraction(reifiedPats.length)).sam();

      results.addAll(
        pat
            .withHapTime((t) => t + offset)
            .query(state.setSpan(subspan.withTime((t) => t - offset))),
      );
    }
    return results;
  }, steps: fraction(reifiedPats.length));
}

Pattern<T> fastcat<T>(List<dynamic> pats) {
  if (pats.isEmpty) return Pattern((state) => []);
  return slowcat<T>(pats).fast(pats.length).setSteps(fraction(pats.length));
}

final Pattern silence = Pattern((state) => []);

Pattern<T> pure<T>(T value) {
  return Pattern(
    (state) => state.span.spanCycles
        .map((subspan) => Hap(subspan.wholeCycle(), subspan, value))
        .toList(),
    steps: fraction(1),
  );
}

Pattern<T> stack<T>(List<dynamic> pats) {
  final reifiedPats = pats.map((p) => reify<T>(p)).toList();
  final query = (StrudelState state) =>
      reifiedPats.expand((pat) => pat.query(state)).toList();
  final steps = lcmMany(reifiedPats.map((p) => p.steps));
  return Pattern(query, steps: steps);
}

Pattern<int> euclid(int k, int n) => sequence(bjorklund(k, n));

Pattern<T> reify<T>(dynamic thing) {
  if (thing is Pattern<T>) return thing;
  return pure(thing as T);
}

Pattern<T> timeCat<T>(List<dynamic> pats) {
  if (pats.isEmpty) return silence as Pattern<T>;

  final List<List<dynamic>> weightedPats = pats.map((p) {
    if (p is List && p.length == 2 && p[0] is num) {
      return [fraction(p[0]), reify<T>(p[1])];
    }
    return [fraction(1), reify<T>(p)];
  }).toList();

  final f.Fraction total = weightedPats
      .map((p) => p[0] as f.Fraction)
      .reduce((a, b) => a + b);

  f.Fraction begin = fraction(0);
  final List<Pattern<T>> zoomedPats = [];

  for (final wp in weightedPats) {
    final weight = wp[0] as f.Fraction;
    final pat = wp[1] as Pattern<T>;
    if (weight == fraction(0)) continue;

    final end = begin + weight;
    // zoom(a, b) selects [a, b] from pat and stretches to cycle
    // We want the OPPOSITE: compress cycle of pat into [begin/total, end/total]
    // Strudel's compress(b, e) = zoom(0, 1) but with inverse logic?
    // Actually, zoom(s, e) means:
    // new_cycle(0, 1) -> old_cycle(s, e)
    // So compress(s, e) is:
    // new_cycle(s, e) -> old_cycle(0, 1)

    // Let's implement compress directly or via zoom inverse.
    // Strudel uses _compress.
    // I'll implement compress in Pattern.
    zoomedPats.add(pat.compress(begin / total, end / total));
    begin = end;
  }

  return stack<T>(zoomedPats).setSteps(total);
}

extension PatternCompressExtension<T> on Pattern<T> {
  Pattern<T> compress(dynamic begin, dynamic end) {
    final f.Fraction fBegin = fraction(begin);
    final f.Fraction fEnd = fraction(end);
    final f.Fraction d = fEnd - fBegin;

    return Pattern((state) {
      final cycle = state.span.begin.sam();
      final b = cycle + fBegin;
      final e = cycle + fEnd;
      final querySpan = state.span.intersection(TimeSpan(b, e));
      if (querySpan == null) return [];

      final compressState = state.setSpan(
        querySpan.withCycle((t) => (t - fBegin) / d),
      );

      return query(compressState).map((hap) {
        return hap.withSpan((span) => span.withCycle((t) => fBegin + (t * d)));
      }).toList();
    }, steps: steps != null ? steps! / d : null);
  }
}
