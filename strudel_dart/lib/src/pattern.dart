import 'dart:async';
import 'dart:math' as math;
import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';
import 'hap.dart';
import 'state.dart';
import 'timespan.dart';
import 'bjorklund.dart';
import 'util.dart';
import 'draw_line.dart' as dl;
import 'logger.dart';

typedef Query<T> = List<Hap<T>> Function(StrudelState state);

class Pattern<T> {
  final Query<T> query;
  final f.Fraction? _steps;

  Pattern(this.query, {f.Fraction? steps}) : _steps = steps;

  f.Fraction? get steps => _steps;
  bool get hasSteps => _steps != null;

  Pattern<T> setSteps(f.Fraction steps) {
    return Pattern(query, steps: steps);
  }

  Pattern<T> withSteps(f.Fraction Function(f.Fraction) func) {
    if (_steps == null) return this;
    return Pattern(query, steps: func(_steps!));
  }

  Pattern<R> map<R>(R Function(T) func) {
    return Pattern(
      (state) => query(state).map((hap) => hap.withValue(func)).toList(),
      steps: _steps,
    );
  }

  Pattern<R> withValue<R>(R Function(T) func) => map(func);

  List<Hap<T>> queryArc(
    dynamic begin,
    dynamic end, {
    Map<String, dynamic> controls = const {},
  }) {
    return query(
      StrudelState(
        TimeSpan(fraction(begin), fraction(end)),
        controls: controls,
      ),
    );
  }

  Pattern<T> withQuerySpan(TimeSpan Function(TimeSpan) func) {
    return Pattern((state) => query(state.withSpan(func)), steps: _steps);
  }

  Pattern<T> withQuerySpanMaybe(TimeSpan? Function(TimeSpan) func) {
    return Pattern((state) {
      final nextSpan = func(state.span);
      if (nextSpan == null) return [];
      return query(state.setSpan(nextSpan));
    }, steps: _steps);
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

  Pattern<T> splitQueries() {
    return Pattern((state) {
      final results = <Hap<T>>[];
      for (final subspan in state.span.spanCycles) {
        results.addAll(query(state.setSpan(subspan)));
      }
      return results;
    }, steps: _steps);
  }

  Pattern<T> withHapTime(f.Fraction Function(f.Fraction) func) {
    return withHapSpan((span) => span.withTime(func));
  }

  Pattern<T> fast(dynamic factor) {
    if (factor is Pattern) {
      return factor.bind((v) => fast(v)).cast<T>();
    }
    final f.Fraction fFactor = fraction(factor);
    if (fFactor.numerator == 0) {
      return silence.cast<T>();
    }
    return withQueryTime((t) => t * fFactor)
        .withHapTime((t) => t / fFactor)
        .setSteps((_steps ?? fraction(1)) * fFactor);
  }

  Pattern<T> slow(dynamic factor) {
    if (factor is Pattern) {
      return factor.bind((v) => slow(v)).cast<T>();
    }
    final f.Fraction fFactor = fraction(factor);
    if (fFactor.numerator == 0) {
      return silence.cast<T>();
    }
    return withQueryTime((t) => t / fFactor)
        .withHapTime((t) => t * fFactor)
        .setSteps((_steps ?? fraction(1)) / fFactor);
  }

  Pattern<T> withHaps(List<Hap<T>> Function(List<Hap<T>>, StrudelState) func) {
    return Pattern((state) => func(query(state), state), steps: _steps);
  }

  Pattern<T> withHap(Hap<T> Function(Hap<T>) func) {
    return withHaps((haps, _) => haps.map(func).toList());
  }

  Pattern<T> filter(bool Function(Hap<T>) test) {
    return withHaps((haps, _) => haps.where(test).toList());
  }

  Pattern<T> withContext(
    Map<String, dynamic> Function(Map<String, dynamic>) func,
  ) {
    return Pattern(
      (state) =>
          query(state).map((hap) => hap.setContext(func(hap.context))).toList(),
      steps: _steps,
    );
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
    if (fBegin >= fEnd) {
      return silence.cast<T>();
    }
    final f.Fraction d = fEnd - fBegin;

    return Pattern((state) {
      final zoomState = state.withSpan(
        (span) => span.withCycle((t) => fBegin + (t * d)),
      );
      return query(zoomState).map((hap) {
        return hap.withSpan((span) => span.withCycle((t) => (t - fBegin) / d));
      }).toList();
    }, steps: _steps != null ? _steps * d : null).splitQueries();
  }

  @override
  String toString() => 'Pattern(steps: $_steps)';

  String drawLine([int chars = 60]) {
    return dl.drawLine(this, chars: chars);
  }

  Pattern<dynamic> collect() {
    return Pattern((state) {
      final haps = query(state);
      final groups = <List<Hap<T>>>[];
      for (final hap in haps) {
        final index = groups.indexWhere(
          (group) => _spanEquals(group.first, hap),
        );
        if (index == -1) {
          groups.add([hap]);
        } else {
          groups[index].add(hap);
        }
      }
      return groups
          .map(
            (group) => Hap<List<Hap<T>>>(
              group.first.whole,
              group.first.part,
              group,
              context: const {},
              stateful: group.first.stateful,
              scheduledTime: group.first.scheduledTime,
            ),
          )
          .toList();
    }, steps: _steps);
  }

  Pattern<T> onTrigger(
    Function onTrigger, [
    bool dominant = true,
  ]) {
    return withHap((hap) {
      final prev = hap.context['onTrigger'];
      final next = (List<dynamic> args) {
        if (prev is Function) {
          Function.apply(prev, args);
        }
        Function.apply(onTrigger, args);
      };
      return hap.setContext({
        ...hap.context,
        'onTrigger': next,
        'dominantTrigger': (hap.context['dominantTrigger'] == true) || dominant,
      });
    });
  }

  Pattern<T> log([String Function(Hap<T>)? func]) {
    final formatter = func ?? (hap) => '[hap] $hap';
    return onTrigger((hap, _, __, ___) {
      logger(formatter(hap as Hap<T>));
    }, false);
  }

  Pattern<T> logValues([String Function(dynamic)? func]) {
    final formatter = func ?? (value) => '[hap] $value';
    return log((hap) => formatter(hap.value));
  }

  Pattern<T> onTriggerTime(Function func) {
    return onTrigger((hap, currentTime, _cps, targetTime) {
      final now = currentTime is num ? currentTime.toDouble() : 0.0;
      final target = targetTime is num ? targetTime.toDouble() : now;
      final diffMs = ((target - now) * 1000).round();
      final delay = diffMs < 0 ? 0 : diffMs;
      Timer(Duration(milliseconds: delay), () {
        Function.apply(func, [hap]);
      });
    }, false);
  }

  Pattern<T> hush() => silence.cast<T>();

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

  Pattern<T> revv() {
    TimeSpan negateSpan(TimeSpan span) =>
        TimeSpan(fraction(0) - span.end, fraction(0) - span.begin);
    return withQuerySpan(negateSpan).withHapSpan(negateSpan);
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

  Pattern<dynamic> apply(dynamic func) {
    if (func is Pattern) {
      return func.appLeft(this);
    }
    if (func is Function) {
      return func(this);
    }
    throw StateError('apply expects a Pattern or function');
  }

  Pattern<dynamic> resetJoin([bool restart = false]) {
    final patOfPats = this;
    return Pattern((state) {
      final outerHaps = patOfPats.discreteOnly().query(state);
      final results = <Hap<dynamic>>[];
      for (final outer in outerHaps) {
        final innerPat = outer.value as Pattern;
        final offset = restart
            ? outer.whole!.begin
            : outer.whole!.begin.cyclePos();
        final aligned = innerPat.late(offset);
        final innerHaps = aligned.query(state);
        for (final inner in innerHaps) {
          TimeSpan? whole;
          if (inner.whole != null && outer.whole != null) {
            whole = inner.whole!.intersection(outer.whole!);
            if (whole == null) {
              continue;
            }
          }
          final part = inner.part.intersection(outer.part);
          if (part == null) {
            continue;
          }
          results.add(
            Hap(whole, part, inner.value, context: outer.combineContext(inner)),
          );
        }
      }
      return results;
    }, steps: steps);
  }

  Pattern<dynamic> restartJoin() => resetJoin(true);

  Pattern<dynamic> squeezeJoin() {
    final patOfPats = this;
    return Pattern((state) {
      final outerHaps = patOfPats.discreteOnly().query(state);
      final results = <Hap<dynamic>>[];
      for (final outer in outerHaps) {
        final innerPat = outer.value as Pattern;
        final focusSpan = outer.wholeOrPart();
        final innerFocused = innerPat.compress(
          focusSpan.begin.cyclePos(),
          focusSpan.end.cyclePos(),
        );
        final innerHaps = innerFocused.query(state.setSpan(outer.part));
        for (final inner in innerHaps) {
          TimeSpan? whole;
          if (inner.whole != null && outer.whole != null) {
            whole = inner.whole!.intersection(outer.whole!);
            if (whole == null) {
              continue;
            }
          }
          final part = inner.part.intersection(outer.part);
          if (part == null) {
            continue;
          }
          results.add(
            Hap(whole, part, inner.value, context: inner.combineContext(outer)),
          );
        }
      }
      return results;
    }, steps: steps);
  }

  Pattern<dynamic> squeezeBind(Pattern Function(T) func) {
    return map(func).squeezeJoin();
  }

  Pattern<T> compress(dynamic begin, dynamic end) {
    final f.Fraction fBegin = fraction(begin);
    final f.Fraction fEnd = fraction(end);
    if (fBegin > fEnd ||
        fBegin > fraction(1) ||
        fEnd > fraction(1) ||
        fBegin < fraction(0) ||
        fEnd < fraction(0)) {
      return silence.cast<T>();
    }
    final span = fEnd - fBegin;
    if (span == fraction(0)) {
      return silence.cast<T>();
    }
    final factor = fraction(1) / span;
    return fastGap(factor).late(fBegin);
  }

  Pattern<T> fastGap(dynamic factor) {
    final f.Fraction fFactor = fraction(factor);
    if (fFactor == fraction(0)) {
      return silence.cast<T>();
    }
    final scaled = fast(fFactor);
    final maxPos = fraction(1) / fFactor;
    return scaled.withHaps((haps, _) {
      return haps.where((hap) => hap.part.begin.cyclePos() < maxPos).toList();
    });
  }

  Pattern<T> focus(dynamic begin, dynamic end) {
    final f.Fraction fBegin = fraction(begin);
    final f.Fraction fEnd = fraction(end);
    return early(fBegin.sam()).fast(fraction(1) / (fEnd - fBegin)).late(fBegin);
  }

  Pattern<T> ply(dynamic factor) {
    return map((x) => pure(x).fast(factor)).squeezeJoin().cast<T>();
  }

  Pattern<dynamic> hurry(dynamic factor) {
    final fFactor = factor is num ? factor : factor.toString();
    return fast(factor).map((v) {
      if (v is Map) {
        return {...v, 'speed': fFactor};
      }
      return v;
    });
  }

  Pattern<T> inside(dynamic factor, Pattern<T> Function(Pattern<T>) func) {
    return func(slow(factor)).fast(factor);
  }

  Pattern<T> outside(dynamic factor, Pattern<T> Function(Pattern<T>) func) {
    return func(fast(factor)).slow(factor);
  }

  Pattern<T> lastOf(int n, Pattern<T> Function(Pattern<T>) func) {
    final pats = List<dynamic>.filled(n - 1, this);
    pats.add(func(this));
    return slowcat<T>(pats);
  }

  Pattern<T> firstOf(int n, Pattern<T> Function(Pattern<T>) func) {
    final pats = <dynamic>[func(this)];
    pats.addAll(List<dynamic>.filled(n - 1, this));
    return slowcat<T>(pats);
  }

  Pattern<T> bite(dynamic nPat, dynamic iPat) {
    final Pattern ipat = reify(iPat);
    return ipat
        .map(
          (i) => (n) {
            final a = modFraction(fraction(i) / fraction(n), fraction(1));
            final b = a + (fraction(1) / fraction(n));
            return zoom(a, b);
          },
        )
        .appLeft(reify(nPat))
        .squeezeJoin()
        .cast<T>();
  }

  Pattern<T> linger(dynamic t) {
    final f.Fraction fT = fraction(t);
    if (fT == fraction(0)) {
      return silence.cast<T>();
    }
    if (fT < fraction(0)) {
      return zoom(fT + fraction(1), fraction(1)).slow(fT);
    }
    return zoom(fraction(0), fT).slow(fT);
  }

  Pattern<T> swingBy(dynamic swing, dynamic n) {
    final s = fraction(swing);
    final Pattern swingPat = sequence([fraction(0), s / fraction(2)]).cast();
    return inside(n, (p) => p.late(swingPat));
  }

  Pattern<T> swing(dynamic n) => swingBy(fraction(1) / fraction(3), n);

  Pattern<T> invert() {
    return map((x) {
      if (x is bool) return (!x) as dynamic;
      if (x is num) return (x == 0 ? 1 : 0) as dynamic;
      return x;
    });
  }

  Pattern<T> tag(String tag) {
    return withContext((ctx) {
      final tags = List<String>.from(ctx['tags'] as List? ?? const []);
      tags.add(tag);
      return {...ctx, 'tags': tags};
    });
  }

  Pattern<T> filterWhen(bool Function(f.Fraction) test) {
    return filter((hap) => test(hap.wholeOrPart().begin));
  }

  Pattern<T> within(
    dynamic a,
    dynamic b,
    Pattern<T> Function(Pattern<T>) func,
  ) {
    final f.Fraction fa = fraction(a);
    final f.Fraction fb = fraction(b);
    return stack<T>([
      func(filterWhen((t) => t.cyclePos() >= fa && t.cyclePos() <= fb)),
      filterWhen((t) => t.cyclePos() < fa || t.cyclePos() > fb),
    ]);
  }

  Pattern<T> whenPattern(Pattern on, Pattern<T> Function(Pattern<T>) func) {
    return on.bind((v) => (v is bool && v) ? func(this) : this).cast<T>();
  }

  Pattern<T> bypass(dynamic on) {
    bool enabled;
    if (on is bool) {
      enabled = on;
    } else if (on is num) {
      enabled = on != 0;
    } else {
      final parsed = int.tryParse(on.toString());
      enabled = parsed != null && parsed != 0;
    }
    return enabled ? silence.cast<T>() : this;
  }

  Pattern<Pattern<T>> unjoin(
    dynamic pieces, [
    Pattern<T> Function(Pattern<T>)? func,
  ]) {
    final apply = func ?? (Pattern<T> p) => p;
    final piecesPat = reify(pieces);
    return piecesPat.withHaps((haps, _) {
      return haps.map((hap) {
        final value = hap.value;
        final bool on = value is bool
            ? value
            : (value is num ? value != 0 : value != null);
        final span = hap.whole ?? hap.part;
        final replacement = on
            ? apply(ribbon(span.begin, span.duration))
            : this;
        return hap.withValue((_) => replacement);
      }).toList();
    }).cast<Pattern<T>>();
  }

  Pattern<T> into(dynamic pieces, Pattern<T> Function(Pattern<T>) func) {
    return unjoin(pieces, func).innerJoin().cast<T>();
  }

  Pattern<T> chunk(int n, Pattern<T> Function(Pattern<T>) func) {
    return _chunk(n, func, this, back: false, fast: false);
  }

  Pattern<T> chunkBack(int n, Pattern<T> Function(Pattern<T>) func) {
    return _chunk(n, func, this, back: true, fast: false);
  }

  Pattern<T> fastChunk(int n, Pattern<T> Function(Pattern<T>) func) {
    return _chunk(n, func, this, back: false, fast: true);
  }

  Pattern<T> chunkInto(int n, Pattern<T> Function(Pattern<T>) func) {
    final selector = fastcat<bool>([
      true,
      ...List<bool>.filled(n - 1, false),
    ]).iterBack(n);
    return into(selector, func);
  }

  Pattern<T> chunkBackInto(int n, Pattern<T> Function(Pattern<T>) func) {
    final selector = fastcat<bool>([
      true,
      ...List<bool>.filled(n - 1, false),
    ]).iter(n).early(1);
    return into(selector, func);
  }

  Pattern<T> off(dynamic time, Pattern<T> Function(Pattern<T>) func) {
    return stack<T>([this, func(late(time))]);
  }

  Pattern<T> brak() {
    final alt = slowcat<bool>([false, true]);
    return alt.bind((flag) {
      if (flag == true) {
        return fastcat<T>([
          this,
          silence.cast<T>(),
        ]).late(fraction(1) / fraction(4));
      }
      return this;
    }).cast<T>();
  }

  Pattern<T> pressBy(dynamic r) {
    return map((x) => pure(x).compress(r, 1)).squeezeJoin().cast<T>();
  }

  Pattern<T> press() => pressBy(fraction(1) / fraction(2));

  Pattern<T> palindrome() => lastOf(2, (p) => p.rev());

  Pattern<dynamic> juxBy(
    dynamic by,
    Pattern<dynamic> Function(Pattern<dynamic>) func,
  ) {
    final numBy = (by is num ? by : num.parse(by.toString())) / 2;
    Map<String, dynamic> adjust(Map<String, dynamic> val, double delta) {
      final pan = (val['pan'] is num) ? (val['pan'] as num).toDouble() : 0.5;
      return {...val, 'pan': pan + delta};
    }

    final left = map((val) {
      if (val is Map<String, dynamic>) {
        return adjust(val, -numBy);
      }
      return val;
    });
    final right = func(
      map((val) {
        if (val is Map<String, dynamic>) {
          return adjust(val, numBy);
        }
        return val;
      }),
    );
    return stack([left, right]);
  }

  Pattern<dynamic> jux(Pattern<dynamic> Function(Pattern<dynamic>) func) {
    return juxBy(1, func);
  }

  Pattern<dynamic> arpWith(Function func) {
    return collect()
        .map((v) => reify(func(v)))
        .innerJoin()
        .withHap((h) {
          final value = h.value;
          if (value is Hap) {
            return Hap(
              h.whole,
              h.part,
              value.value,
              context: h.combineContext(value),
              stateful: h.stateful,
              scheduledTime: h.scheduledTime,
            );
          }
          return h;
        });
  }

  Pattern<dynamic> arp(dynamic indices) {
    return arpWith((haps) {
      if (haps is! List || haps.isEmpty) return silence;
      return reify(indices).map((i) {
        final idx = (i as num).toInt();
        return haps[idx % haps.length];
      });
    });
  }

  Pattern<T> echoWith(
    int times,
    dynamic time,
    Pattern<T> Function(Pattern<T>, int) func,
  ) {
    final patterns = listRange(
      0,
      times - 1,
    ).map((i) => func(late(fraction(time) * fraction(i)), i)).toList();
    return stack<T>(patterns);
  }

  Pattern<T> echo(int times, dynamic time, num feedback) {
    return echoWith(times, time, (pat, i) {
      final gain = math.pow(feedback, i);
      return pat.map((value) {
            if (value is Map) {
              return {...value, 'gain': gain};
            }
            return value;
          })
          as Pattern<T>;
    });
  }

  Pattern<T> stut(int times, num feedback, dynamic time) {
    return echo(times, time, feedback);
  }

  Pattern<T> applyN(int n, Pattern<T> Function(Pattern<T>) func) {
    var result = this;
    for (var i = 0; i < n; i++) {
      result = func(result);
    }
    return result;
  }

  Pattern<T> iter(dynamic times, {bool back = false}) {
    final f.Fraction t = fraction(times);
    final int count = t.toDouble().floor();
    final patterns = listRange(0, count - 1).map((i) {
      final offset = fraction(i) / t;
      return back ? late(offset) : early(offset);
    }).toList();
    return slowcat<T>(patterns);
  }

  Pattern<T> iterBack(dynamic times) => iter(times, back: true);

  Pattern<num> asNumber() {
    return map<num>((value) {
      if (value is num) return value as num;
      throw StateError('Expected numeric pattern value, got $value');
    });
  }

  Pattern<num> round() {
    return asNumber().map((v) => v.round());
  }

  Pattern<num> floor() {
    return asNumber().map((v) => v.floor());
  }

  Pattern<num> ceil() {
    return asNumber().map((v) => v.ceil());
  }

  Pattern<num> log2() {
    return asNumber().map((v) => math.log(v) / math.ln2);
  }

  Pattern<num> rangex(dynamic min, dynamic max) {
    if (min is! num || max is! num) {
      throw StateError('rangex expects numeric min/max');
    }
    return range(math.log(min), math.log(max)).map((v) => math.exp(v as num));
  }

  Pattern<dynamic> ratio() {
    return map((v) {
      if (v is! List) return v;
      if (v.isEmpty) return v;
      return v.skip(1).fold<num>(v[0] as num, (acc, n) => acc / (n as num));
    });
  }

  Pattern<dynamic> band(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) {
        return a.toInt() & b.toInt();
      }
      return a;
    },
  );

  Pattern<dynamic> brshift(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) {
        return a.toInt() >> b.toInt();
      }
      return a;
    },
  );

  Pattern<num> toBipolar() {
    return asNumber().map((v) => (v * 2) - 1);
  }

  Pattern<num> fromBipolar() {
    return asNumber().map((v) => (v + 1) / 2);
  }

  Pattern<dynamic> range(dynamic min, dynamic max) {
    final minPat = reify(min);
    final maxPat = reify(max);
    return mul(maxPat.sub(minPat)).add(minPat);
  }

  Pattern<dynamic> range2(dynamic min, dynamic max) {
    return fromBipolar().range(min, max);
  }

  Pattern<T> filterValues(bool Function(T) predicate) {
    return withHaps(
      (haps, _) => haps.where((hap) => predicate(hap.value)).toList(),
    );
  }

  Pattern<T> when(bool condition, Pattern<T> Function(Pattern<T>) func) {
    return condition ? func(this) : this;
  }

  Pattern<T> late(dynamic offset) {
    final f.Fraction fOffset = fraction(offset);
    return withHapTime((t) => t + fOffset).withQueryTime((t) => t - fOffset);
  }

  Pattern<T> early(dynamic offset) {
    final f.Fraction fOffset = fraction(offset);
    return withHapTime((t) => t - fOffset).withQueryTime((t) => t + fOffset);
  }

  Pattern<T> ribbon(dynamic offset, dynamic cycles) {
    return early(offset).restart(pure(1).slow(cycles)).cast<T>();
  }

  // Arithmetic

  Pattern<dynamic> _opIn(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    return map(op).appLeft(reify(other));
  }

  Pattern<dynamic> _opOut(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    return map(op).appRight(reify(other));
  }

  Pattern<dynamic> _opMix(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    return map(op).appBoth(reify(other));
  }

  Pattern<dynamic> _opSqueeze(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    final otherPat = reify(other);
    return map((a) => otherPat.map((b) => op(a)(b))).squeezeJoin();
  }

  Pattern<dynamic> _opSqueezeOut(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    final thisPat = this;
    final otherPat = reify(other);
    return otherPat.map((a) => thisPat.map((b) => op(b)(a))).squeezeJoin();
  }

  Pattern<dynamic> _opReset(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    final otherPat = reify(other);
    return otherPat.map((b) => map((a) => op(a)(b))).resetJoin();
  }

  Pattern<dynamic> _opRestart(
    dynamic other,
    dynamic Function(dynamic) Function(dynamic) op,
  ) {
    final otherPat = reify(other);
    return otherPat.map((b) => map((a) => op(a)(b))).restartJoin();
  }

  Pattern<dynamic> set(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is Map || b is Map) {
        final mapA = a is Map ? Map<String, dynamic>.from(a) : {'value': a};
        final mapB = b is Map ? Map<String, dynamic>.from(b) : {'value': b};
        return {...mapA, ...mapB};
      }
      return b;
    },
  );

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

  Pattern<dynamic> pow(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return math.pow(a, b);
      return a;
    },
  );

  Pattern<dynamic> bor(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a.toInt() | b.toInt();
      return a;
    },
  );

  Pattern<dynamic> bxor(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a.toInt() ^ b.toInt();
      return a;
    },
  );

  Pattern<dynamic> blshift(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a.toInt() << b.toInt();
      return a;
    },
  );

  Pattern<dynamic> lt(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a < b;
      if (a is String && b is String) return a.compareTo(b) < 0;
      return false;
    },
  );

  Pattern<dynamic> gt(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a > b;
      if (a is String && b is String) return a.compareTo(b) > 0;
      return false;
    },
  );

  Pattern<dynamic> lte(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a <= b;
      if (a is String && b is String) return a.compareTo(b) <= 0;
      return false;
    },
  );

  Pattern<dynamic> gte(dynamic other) => _opIn(
    other,
    (a) => (b) {
      if (a is num && b is num) return a >= b;
      if (a is String && b is String) return a.compareTo(b) >= 0;
      return false;
    },
  );

  Pattern<dynamic> eq(dynamic other) => _opIn(
    other,
    (a) => (b) => a == b,
  );

  Pattern<dynamic> eqt(dynamic other) => _opIn(
    other,
    (a) => (b) => a == b,
  );

  Pattern<dynamic> ne(dynamic other) => _opIn(
    other,
    (a) => (b) => a != b,
  );

  Pattern<dynamic> net(dynamic other) => _opIn(
    other,
    (a) => (b) => a != b,
  );

  Pattern<dynamic> and(dynamic other) => _opIn(
    other,
    (a) => (b) => _truthy(a) ? b : a,
  );

  Pattern<dynamic> or(dynamic other) => _opIn(
    other,
    (a) => (b) => _truthy(a) ? a : b,
  );

  Pattern<T> keep(dynamic other) {
    return _opIn(
      other,
      (a) => (b) => a,
    ).cast<T>();
  }

  Pattern<T> keepif(dynamic other) {
    return _opIn(
      other,
      (a) => (b) => _truthy(b) ? a : null,
    ).filterValues((v) => v != null).cast<T>();
  }

  Pattern<T> reset(dynamic other) {
    final otherPat = reify(other);
    return otherPat.map((_) => this).resetJoin().cast<T>();
  }

  Pattern<T> restart(dynamic other) {
    final otherPat = reify(other);
    return otherPat.map((_) => this).restartJoin().cast<T>();
  }

  Pattern<T> structAll(dynamic other) => struct(reify(other)).cast<T>();

  Pattern<T> maskAll(dynamic other) => mask(reify(other)).cast<T>();

  Pattern<T> resetAll(dynamic other) => reset(other);

  Pattern<T> restartAll(dynamic other) => restart(other);

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

  Pattern<T> segment(dynamic rate) {
    if (rate is! num) {
      throw StateError('segment expects numeric rate');
    }
    if (rate <= 0) {
      return silence.cast<T>();
    }
    return struct(pure(true).fast(rate)).setSteps(fraction(rate));
  }

  Pattern<T> _segment(dynamic rate) => segment(rate);

  Pattern<T> repeatCycles(dynamic n) {
    final f.Fraction fN = fraction(n);
    return Pattern((state) {
      final cycle = state.span.begin.sam();
      final sourceCycle = (cycle / fN).sam();
      final delta = cycle - sourceCycle;
      final shiftedState = state.withSpan(
        (span) => span.withTime((t) => t - delta),
      );
      return query(shiftedState)
          .map((hap) => hap.withSpan((span) => span.withTime((t) => t + delta)))
          .toList();
    }, steps: steps);
  }

  Pattern<T> pace(dynamic targetSteps) {
    if (!hasSteps) return this;
    if (_steps == null || _steps == fraction(0)) {
      return silence.cast<T>();
    }
    final f.Fraction target = fraction(targetSteps);
    return fast(target / _steps!).setSteps(target);
  }

  Pattern<dynamic> stepJoin() {
    final first = stepcat(_retime(_slices(queryArc(0, 1))));
    final firstSteps = first.steps;
    List<Hap<dynamic>> q(StrudelState state) {
      final shifted = early(state.span.begin.sam());
      final haps = shifted.query(
        state.setSpan(TimeSpan(fraction(0), fraction(1))),
      );
      final pat = stepcat(_retime(_slices(haps)));
      return pat.query(state);
    }

    return Pattern(q, steps: firstSteps);
  }

  Pattern<dynamic> stepBind(Pattern Function(T) func) {
    return map(func).stepJoin();
  }

  Pattern<T> take(dynamic i) {
    if (!hasSteps) return silence.cast<T>();
    if (_steps == null || _steps! <= fraction(0)) {
      return silence.cast<T>();
    }
    var amount = fraction(i);
    if (amount == fraction(0)) return silence.cast<T>();
    final flip = amount < fraction(0);
    if (flip) {
      amount = fraction(0) - amount;
    }
    final frac = amount / _steps!;
    if (frac <= fraction(0)) return silence.cast<T>();
    if (frac >= fraction(1)) return this;
    if (flip) {
      return zoom(fraction(1) - frac, fraction(1));
    }
    return zoom(fraction(0), frac);
  }

  Pattern<T> drop(dynamic i) {
    if (!hasSteps) return silence.cast<T>();
    final amount = fraction(i);
    if (amount < fraction(0)) {
      return take(_steps! + amount);
    }
    return take(fraction(0) - (_steps! - amount));
  }

  Pattern<T> expand(dynamic factor) {
    return withSteps((t) => t * fraction(factor));
  }

  Pattern<T> contract(dynamic factor) {
    return withSteps((t) => t / fraction(factor));
  }

  Pattern<T> extend(dynamic factor) {
    return fast(factor).expand(factor);
  }

  Pattern<T> replicate(dynamic factor) {
    return repeatCycles(factor).fast(factor).expand(factor);
  }

  List<Pattern<T>> shrinklist(dynamic amount) {
    if (!hasSteps) return [this];
    var amountValue = amount;
    dynamic times = _steps!;
    if (amount is List && amount.length == 2) {
      amountValue = amount[0];
      times = amount[1];
    }
    var amt = fraction(amountValue);
    if (times == 0 || amt == fraction(0)) {
      return [this];
    }
    final int count = times is f.Fraction
        ? times.toDouble().floor()
        : (times as num).toInt();
    final ranges = <List<f.Fraction>>[];
    if (amt > fraction(0)) {
      final seg = (fraction(1) / _steps!) * amt;
      for (var i = 0; i < count; i++) {
        final s = seg * fraction(i);
        if (s > fraction(1)) break;
        ranges.add([s, fraction(1)]);
      }
    } else {
      amt = fraction(0) - amt;
      final seg = (fraction(1) / _steps!) * amt;
      for (var i = 0; i < count; i++) {
        final e = fraction(1) - (seg * fraction(i));
        if (e < fraction(0)) break;
        ranges.add([fraction(0), e]);
      }
    }
    return ranges.map((r) => zoom(r[0], r[1])).toList();
  }

  Pattern<T> shrink(dynamic amount) {
    if (!hasSteps) return silence.cast<T>();
    final list = shrinklist(amount);
    final result = stepcat(list).setSteps(
      list.fold<f.Fraction>(
        fraction(0),
        (a, b) => a + (b.steps ?? fraction(0)),
      ),
    );
    return result.cast<T>();
  }

  Pattern<T> grow(dynamic amount) {
    if (!hasSteps) return silence.cast<T>();
    final list = shrinklist(fraction(0) - fraction(amount)).reversed.toList();
    final result = stepcat(list).setSteps(
      list.fold<f.Fraction>(
        fraction(0),
        (a, b) => a + (b.steps ?? fraction(0)),
      ),
    );
    return result.cast<T>();
  }

  Pattern<T> tour(List<dynamic> many) {
    final List<dynamic> items = many;
    final sequences = <dynamic>[];
    for (var i = 0; i < items.length; i++) {
      final head = items.sublist(0, items.length - i);
      final tail = items.sublist(items.length - i);
      sequences.addAll([...head, this, ...tail]);
    }
    sequences.add(this);
    sequences.addAll(items);
    return stepcat(sequences).cast<T>();
  }

  Pattern<dynamic> chop(int n) {
    final slices = List<int>.generate(n, (i) => i);
    final sliceObjects = slices
        .map((i) => {'begin': i / n, 'end': (i + 1) / n})
        .toList();
    return squeezeBind((o) {
      final base = o is Map<String, dynamic> ? o : {'s': o};
      final objs = sliceObjects.map((slice) => {...base, ...slice}).toList();
      return sequence(objs);
    }).setSteps(hasSteps ? (_steps! * fraction(n)) : fraction(n));
  }

  Pattern<dynamic> striate(int n) {
    final slices = List<int>.generate(n, (i) => i);
    final sliceObjects = slices
        .map((i) => {'begin': i / n, 'end': (i + 1) / n})
        .toList();
    final slicePat = slowcat(sliceObjects);
    return set(
      slicePat,
    ).fast(n).setSteps(hasSteps ? (_steps! * fraction(n)) : fraction(n));
  }

  Pattern<dynamic> loopAt(dynamic factor, {double? cps}) {
    final localCps = cps ?? 0.5;
    return map((v) {
      if (v is Map) {
        return {...v, 'speed': (1 / (factor as num)) * localCps, 'unit': 'c'};
      }
      return v;
    }).slow(factor);
  }

  Pattern<dynamic> loopAtCps(dynamic factor, double cps) {
    return loopAt(factor, cps: cps);
  }

  Pattern<dynamic> fit() {
    return cast<dynamic>().withHaps((haps, state) {
      return haps.map((hap) {
        return hap.withValue((v) {
          if (v is! Map) return v;
          final begin = (v['begin'] as num?) ?? 0;
          final end = (v['end'] as num?) ?? 1;
          final slicedur = end - begin;
          final cps = state.controls['_cps'] is num
              ? state.controls['_cps'] as num
              : 1;
          return {
            ...v,
            'speed': (cps / hap.whole!.duration.toDouble()) * slicedur,
            'unit': 'c',
          };
        });
      }).toList();
    });
  }
}

bool _spanEquals(Hap a, Hap b) {
  final samePart = a.part.equals(b.part);
  final aw = a.whole;
  final bw = b.whole;
  if (aw == null && bw == null) return samePart;
  if (aw == null || bw == null) return false;
  return samePart && aw.equals(bw);
}

bool _truthy(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.isNotEmpty && value != '~';
  return true;
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

Pattern<List<dynamic>> sequenceP(List<dynamic> pats) {
  var result = pure(<dynamic>[]);
  for (final pat in pats) {
    result = result
        .bind((list) => reify(pat).map((v) => [...list, v]))
        .cast<List<dynamic>>();
  }
  return result;
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

Pattern stepcat(List<dynamic> timepats) {
  if (timepats.isEmpty) return silence;
  List<List<dynamic>> entries = timepats.map((item) {
    if (item is List && item.length == 2) {
      return [fraction(item[0]), item[1]];
    }
    if (item is Pattern && item.steps != null) {
      return [item.steps!, item];
    }
    return [fraction(1), item];
  }).toList();

  final knownSteps = entries
      .where((e) => e[0] != null)
      .map((e) => e[0] as f.Fraction)
      .toList();
  if (knownSteps.isNotEmpty && knownSteps.length != entries.length) {
    final avg =
        knownSteps.reduce((a, b) => a + b) / fraction(knownSteps.length);
    entries = entries.map((e) => [e[0] ?? avg, e[1]]).toList();
  }

  if (entries.length == 1) {
    final pat = reify(entries[0][1]);
    return pat.setSteps(entries[0][0] as f.Fraction);
  }

  final total = entries.map((e) => e[0] as f.Fraction).reduce((a, b) => a + b);
  f.Fraction begin = fraction(0);
  final pats = <Pattern>[];
  for (final entry in entries) {
    final time = entry[0] as f.Fraction;
    final pat = reify(entry[1]);
    if (time == fraction(0)) continue;
    final end = begin + time;
    pats.add(pat.compress(begin / total, end / total));
    begin = end;
  }
  final result = stack(pats).setSteps(total);
  return result;
}

List<List<dynamic>> _retime(List<List<dynamic>> timedHaps) {
  final occupied = timedHaps.where((entry) {
    final pat = entry[1] as Pattern;
    return pat.hasSteps;
  }).toList();
  final occupiedPerc = occupied.fold<f.Fraction>(
    fraction(0),
    (acc, entry) => acc + (entry[0] as f.Fraction),
  );
  final occupiedSteps = occupied.fold<f.Fraction>(
    fraction(0),
    (acc, entry) => acc + ((entry[1] as Pattern).steps ?? fraction(0)),
  );
  final f.Fraction? totalSteps = occupiedPerc == fraction(0)
      ? null
      : occupiedSteps / occupiedPerc;
  return timedHaps.map((entry) {
    final dur = entry[0] as f.Fraction;
    final pat = entry[1] as Pattern;
    if (!pat.hasSteps) {
      final adjusted = totalSteps == null ? dur : dur * totalSteps;
      return [adjusted, pat];
    }
    return [pat.steps!, pat];
  }).toList();
}

List<List<dynamic>> _slices(List<Hap> haps) {
  final breakpoints = flatten(
    haps.map((hap) => [hap.part.begin, hap.part.end]),
  );
  final unique = uniqsortr([fraction(0), fraction(1), ...breakpoints]);
  final slicespans = pairs(unique);
  return slicespans.map((span) {
    final sliceSpan = TimeSpan(span[0], span[1]);
    final sliceHaps = _fitslice(sliceSpan, haps);
    final slicePatterns = sliceHaps.map((hap) {
      final value = hap.value;
      final Pattern pat = value is Pattern ? value : pure(value);
      return pat.withHaps((innerHaps, _) {
        return innerHaps
            .map((inner) => inner.setContext(inner.combineContext(hap)))
            .toList();
      });
    }).toList();
    return [span[1] - span[0], stack(slicePatterns)];
  }).toList();
}

List<Hap> _fitslice(TimeSpan span, List<Hap> haps) {
  return removeUndefineds(haps.map((hap) => _match(span, hap)));
}

Hap? _match(TimeSpan span, Hap hap) {
  final subspan = span.intersection(hap.part);
  if (subspan == null) {
    return null;
  }
  return Hap(hap.whole, subspan, hap.value, context: hap.context);
}

Pattern stepalt(List<dynamic> groups) {
  final normalized = groups
      .map((g) => g is List ? g.map(reify).toList() : [reify(g)])
      .toList();
  if (normalized.isEmpty) return silence;
  int lcmLen = 1;
  for (final group in normalized) {
    if (group.isEmpty) continue;
    lcmLen = _lcmInt(lcmLen, group.length);
  }
  final result = <Pattern>[];
  for (var cycle = 0; cycle < lcmLen; cycle++) {
    for (final group in normalized) {
      if (group.isEmpty) {
        result.add(silence);
      } else {
        result.add(group[cycle % group.length]);
      }
    }
  }
  final filtered = result.where((p) => p.hasSteps).toList();
  final steps = filtered.fold<f.Fraction>(
    fraction(0),
    (a, b) => a + (b.steps ?? fraction(0)),
  );
  final out = stepcat(filtered).setSteps(steps);
  return out;
}

Pattern<T> _chunk<T>(
  int n,
  Pattern<T> Function(Pattern<T>) func,
  Pattern<T> pat, {
  required bool back,
  required bool fast,
}) {
  final binary = List<bool>.filled(n, false)..[0] = true;
  final selector = sequence<bool>(binary).iter(n, back: !back);
  final target = fast ? pat : pat.repeatCycles(n);
  return target.whenPattern(selector, func).cast<T>();
}

Pattern polymeter(List<Pattern> args) {
  if (args.isEmpty) return silence;
  final withSteps = args.where((p) => p.hasSteps).toList();
  if (withSteps.isEmpty) return silence;
  final steps = lcmMany(withSteps.map((p) => p.steps)) ?? fraction(0);
  if (steps == fraction(0)) return silence;
  final result = stack(withSteps.map((p) => p.pace(steps)).toList());
  return result.setSteps(steps);
}

Pattern zip(List<Pattern> pats) {
  final filtered = pats.where((p) => p.hasSteps).toList();
  if (filtered.isEmpty) return silence;
  final zipped = slowcat(
    filtered.map((pat) => pat.slow(pat.steps ?? fraction(1))).toList(),
  );
  final steps = lcmMany(filtered.map((p) => p.steps)) ?? fraction(0);
  return zipped.fast(steps).setSteps(steps);
}

Pattern slice(dynamic npat, dynamic ipat, dynamic opat) {
  final nPat = reify(npat);
  final iPat = reify(ipat);
  final oPat = reify(opat);
  return nPat
      .innerBind(
        (n) => iPat.outerBind(
          (i) => oPat.outerBind((o) {
            final obj = o is Map<String, dynamic> ? o : {'s': o};
            final begin = n is List
                ? (n[i as int] as num)
                : (i as num) / (n as num);
            final end = n is List
                ? (n[(i as int) + 1] as num)
                : ((i as num) + 1) / (n as num);
            return pure({'begin': begin, 'end': end, '_slices': n, ...obj});
          }),
        ),
      )
      .setSteps(iPat.steps ?? fraction(1));
}

Pattern splice(dynamic npat, dynamic ipat, dynamic opat) {
  final sliced = slice(npat, ipat, opat);
  return Pattern((state) {
    final cps = state.controls['_cps'] is num
        ? (state.controls['_cps'] as num).toDouble()
        : 1.0;
    final haps = sliced.query(state);
    return haps
        .map(
          (hap) => hap.withValue((v) {
            if (v is! Map) return v;
            final slices = v['_slices'];
            final sliceCount = slices is List
                ? slices.length
                : (slices as num).toDouble();
            final speed =
                (cps / sliceCount / hap.whole!.duration.toDouble()) *
                ((v['speed'] as num?) ?? 1);
            return {...v, 'speed': speed, 'unit': 'c'};
          }),
        )
        .toList();
  }, steps: sliced.steps);
}

Pattern ref(dynamic Function() accessor) {
  return pure(1).map((_) => reify(accessor())).innerJoin();
}

Pattern xfade(Pattern a, dynamic pos, Pattern b) {
  final posPat = reify(pos);
  final gainA = posPat.map(
    (v) => {'gain': (v as num) < 0.5 ? 1 : 1 - (v - 0.5) / 0.5},
  );
  final gainB = posPat.map(
    (v) => {'gain': (1 - (v as num)) < 0.5 ? 1 : 1 - ((1 - v) - 0.5) / 0.5},
  );
  return stack([a.mul(gainA), b.mul(gainB)]);
}

Pattern beat(dynamic t, dynamic div, Pattern pat) {
  final fdiv = fraction(div);
  final ft = modFraction(fraction(t), fdiv);
  final b = ft / fdiv;
  final e = (ft + fraction(1)) / fdiv;
  return pat.map((x) => pure(x).compress(b, e)).innerJoin();
}

List<int> _binaryListFrom(dynamic value) {
  if (value is List) {
    return value
        .map((v) => v is bool ? (v ? 1 : 0) : (v as num).toInt())
        .toList();
  }
  if (value is String) {
    return value
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();
  }
  throw StateError('morph expects a list or string');
}

Pattern<bool> _morph(dynamic from, dynamic to, dynamic by) {
  final fromList = _binaryListFrom(from);
  final toList = _binaryListFrom(to);
  if (fromList.isEmpty || toList.isEmpty) {
    return silence.cast<bool>();
  }
  final f.Fraction byFrac = fraction(by);
  final dur = fraction(1) / fraction(fromList.length);
  List<List<dynamic>> positions(List<int> list) {
    final result = <List<dynamic>>[];
    for (var i = 0; i < list.length; i++) {
      if (list[i] != 0) {
        result.add([fraction(i) / fraction(list.length), true]);
      }
    }
    return result;
  }

  final arcs = zipWith<TimeSpan>(
    (a, b) {
      final posa = a[0] as f.Fraction;
      final posb = b[0] as f.Fraction;
      final begin = byFrac * (posb - posa) + posa;
      final end = begin + dur;
      return TimeSpan(begin, end);
    },
    positions(fromList),
    positions(toList),
  );

  List<Hap<bool>> query(StrudelState state) {
    final cycle = state.span.begin.sam();
    final cycleArc = state.span.cycleArc();
    final result = <Hap<bool>>[];
    for (final whole in arcs) {
      final part = whole.intersection(cycleArc);
      if (part != null) {
        result.add(
          Hap(
            whole.withTime((x) => x + cycle),
            part.withTime((x) => x + cycle),
            true,
          ),
        );
      }
    }
    return result;
  }

  return Pattern<bool>(query).splitQueries();
}

Pattern morph(dynamic frompat, dynamic topat, dynamic bypat) {
  final fromPattern = reify(frompat);
  final toPattern = reify(topat);
  final byPattern = reify(bypat);
  return fromPattern.innerBind(
    (from) => toPattern.innerBind(
      (to) => byPattern.innerBind((by) => _morph(from, to, by)),
    ),
  );
}

int _lcmInt(int a, int b) {
  int gcd(int x, int y) => y == 0 ? x : gcd(y, x % y);
  return (a ~/ gcd(a, b)) * b;
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
