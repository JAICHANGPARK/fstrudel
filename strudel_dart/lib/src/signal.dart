import 'dart:math' as math;
import 'package:fraction/fraction.dart' as f;
import 'fraction.dart';
import 'hap.dart';
import 'pattern.dart';
import 'util.dart';

Pattern<T> steady<T>(T value) {
  return Pattern((state) => [Hap(null, state.span, value)]);
}

Pattern<T> signal<T>(T Function(f.Fraction, Map<String, dynamic>) func) {
  return Pattern(
    (state) => [Hap(null, state.span, func(state.span.begin, state.controls))],
  );
}

Pattern<num> saw = signal((t, _) => t.cyclePos().toDouble());
Pattern<num> saw2 = saw.toBipolar();
Pattern<num> isaw = signal((t, _) => 1 - t.cyclePos().toDouble());
Pattern<num> isaw2 = isaw.toBipolar();
Pattern<num> sine2 = signal((t, _) => math.sin(2 * math.pi * t.toDouble()));
Pattern<num> sine = sine2.fromBipolar();
Pattern<num> cosine = sine.early(fraction(1) / fraction(4));
Pattern<num> cosine2 = sine2.early(fraction(1) / fraction(4));
Pattern<num> square = signal((t, _) => ((t.toDouble() * 2) % 2).floor());
Pattern<num> square2 = square.toBipolar();
Pattern<num> tri = fastcat<num>([saw, isaw]);
Pattern<num> tri2 = fastcat<num>([saw2, isaw2]);
Pattern<num> itri = fastcat<num>([isaw, saw]);
Pattern<num> itri2 = fastcat<num>([isaw2, saw2]);
Pattern<f.Fraction> time = signal((t, _) => t);

double _mouseY = 0;
double _mouseX = 0;

void setMousePosition({double? x, double? y}) {
  if (x != null) _mouseX = x;
  if (y != null) _mouseY = y;
}

Pattern<num> mousey = signal((_, __) => _mouseY);
Pattern<num> mouseY = mousey;
Pattern<num> mousex = signal((_, __) => _mouseX);
Pattern<num> mouseX = mousex;

int _murmurHashFinalizer(int x) {
  x = x.toSigned(32);
  x ^= (x >> 16);
  x = (x * 0x85ebca6b).toSigned(32);
  x ^= (x >> 13);
  x = (x * 0xc2b2ae35).toSigned(32);
  x ^= (x >> 16);
  return x.toUnsigned(32);
}

int _tToT(f.Fraction t) {
  return (t.toDouble() * 536870912).floor();
}

int _decorrelate(int t, int i, int seed) {
  final lowBits = t.toUnsigned(32);
  final highBits = (t ~/ 4294967296).toUnsigned(32);
  var key = lowBits ^ ((highBits ^ 0x85ebca6b) * 0xc2b2ae35).toSigned(32);
  key ^= ((i ^ 0x7f4a7c15) * 0x9e3779b9).toSigned(32);
  key ^= ((seed ^ 0x165667b1) * 0x27d4eb2d).toSigned(32);
  return key.toUnsigned(32);
}

double _randAt(int t, int i, int seed) {
  return _murmurHashFinalizer(_decorrelate(t, i, seed)) / 4294967296;
}

dynamic _timeToRands(f.Fraction t, int n, int seed) {
  final T = _tToT(t);
  if (n == 1) {
    return _randAt(T, 0, seed);
  }
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    out.add(_randAt(T, i, seed));
  }
  return out;
}

int _xorwise(int x) {
  final a = (x << 13) ^ x;
  final b = (a >> 17) ^ a;
  return (b << 5) ^ b;
}

double _frac(double x) => x - x.truncate();

int _timeToIntSeed(double x) =>
    _xorwise((_frac(x / 300) * 536870912).truncate());

double _intSeedToRand(int x) => (x % 536870912) / 536870912;

dynamic _timeToRandsPrime(int seed, int n) {
  if (n == 1) {
    return _intSeedToRand(seed).abs();
  }
  final result = <double>[];
  var currentSeed = seed;
  for (var i = 0; i < n; i++) {
    result.add(_intSeedToRand(currentSeed));
    currentSeed = _xorwise(currentSeed);
  }
  return result;
}

dynamic _timeToRandsLegacy(f.Fraction t, int n) {
  final seed = _timeToIntSeed(t.toDouble());
  return _timeToRandsPrime(seed, n);
}

String _rngMode = 'legacy';

dynamic getRandsAtTime(f.Fraction t, {int n = 1, int seed = 0}) {
  if (_rngMode == 'legacy') {
    return _timeToRandsLegacy(t + fraction(seed), n);
  }
  return _timeToRands(t, n, seed);
}

void useRNG([String mode = 'legacy']) {
  _rngMode = mode;
}

Pattern<num> run(int n) => saw.range(0, n).round().segment(n);

Pattern binary(int n) {
  final nBits = (math.log(n) / math.ln2).floor() + 1;
  return binaryN(n, nBits);
}

Pattern binaryN(int n, int nBits) {
  final bitPos = run(nBits).mul(-1).add(nBits - 1);
  return reify(n).segment(nBits).brshift(bitPos).band(pure(1));
}

Pattern binaryL(int n) {
  final nBits = (math.log(n) / math.ln2).floor() + 1;
  return binaryNL(n, nBits);
}

Pattern binaryNL(int n, int nBits) {
  return reify(n)
      .withValue(
        (v) => (bits) {
          final list = <int>[];
          for (var i = bits - 1; i >= 0; i--) {
            list.add(((v as int) >> i) & 1);
          }
          return list;
        },
      )
      .appLeft(reify(nBits));
}

Pattern randL(int n) {
  return signal(
    (t, _) => (int nVal) {
      final rands = getRandsAtTime(t, n: nVal) as List<double>;
      return rands.map((v) => v.abs()).toList();
    },
  ).appLeft(reify(n));
}

Pattern randrun(int n) {
  return signal((t, controls) {
    final seed = controls['randSeed'] is int ? controls['randSeed'] as int : 0;
    final rands =
        getRandsAtTime(t.sam() + fraction(0.5), n: n, seed: seed)
            as List<double>;
    final nums = rands
        .asMap()
        .entries
        .map<List<num>>((e) => [e.value, e.key])
        .toList()
      ..sort((a, b) => a[0].compareTo(b[0]));
    final idx = ((t.cyclePos() * fraction(n)).toDouble().floor()) % n;
    return nums[idx][1];
  }).segment(n);
}

Pattern _rearrangeWith(Pattern ipat, int n, Pattern pat) {
  final pats = List.generate(
    n,
    (i) => pat.zoom(fraction(i) / fraction(n), fraction(i + 1) / fraction(n)),
  );
  return ipat
      .map((i) => pats[(i as num).toInt()].repeatCycles(n).fast(n))
      .innerJoin();
}

Pattern shuffle(int n, Pattern pat) => _rearrangeWith(randrun(n), n, pat);

Pattern scramble(int n, Pattern pat) =>
    _rearrangeWith(irand(n).segment(n), n, pat);

Pattern withSeed(int? Function(int?) func, Pattern pat) {
  return Pattern((state) {
    final randSeed = state.controls['randSeed'];
    final nextSeed = func(randSeed is num ? randSeed.toInt() : null);
    return pat.query(state.setControls({'randSeed': nextSeed}));
  }, steps: pat.steps);
}

Pattern seed(int n, Pattern pat) {
  return withSeed((_) => n, pat);
}

Pattern<num> rand = signal((t, controls) {
  final seed = controls['randSeed'] is int ? controls['randSeed'] as int : 0;
  return getRandsAtTime(t, seed: seed) as num;
});

Pattern<num> rand2 = rand.toBipolar();

Pattern<bool> _brandBy(num p) => rand.map((x) => x < p);

Pattern brandBy(Pattern pPat) =>
    reify(pPat).map((p) => _brandBy(p as num)).innerJoin();

Pattern<bool> brand = _brandBy(0.5);

Pattern<int> _irand(int i) => rand.map((x) => (x * i).truncate()).cast<int>();

Pattern<int> irand(dynamic ipat) =>
    reify(ipat).map((i) => _irand((i as num).toInt())).innerJoin().cast<int>();

Pattern __chooseWith(Pattern pat, List<dynamic> xs) {
  final values = xs.map(reify).toList();
  if (values.isEmpty) return silence;
  return pat.range(0, values.length).map((i) {
    final idx = clamp((i as num).floor(), 0, values.length - 1).toInt();
    return values[idx];
  });
}

Pattern chooseWith(Pattern pat, List<dynamic> xs) =>
    __chooseWith(pat, xs).outerJoin();

Pattern chooseInWith(Pattern pat, List<dynamic> xs) =>
    __chooseWith(pat, xs).innerJoin();

Pattern choose(List<dynamic> xs) => chooseWith(rand, xs);

Pattern chooseIn(List<dynamic> xs) => chooseInWith(rand, xs);

Pattern chooseCycles(List<dynamic> xs) => chooseInWith(rand.segment(1), xs);

Pattern randcat(List<dynamic> xs) => chooseCycles(xs);

Pattern _wchooseWith(Pattern pat, List<List<dynamic>> pairs) {
  final values = pairs.map((pair) => reify(pair[0])).toList();
  final weights = <Pattern>[];
  Pattern total = pure(0);
  for (final pair in pairs) {
    total = total.add(pair[1]);
    weights.add(total);
  }
  final weightspat = sequenceP(weights);
  return pat.bind((r) {
    final findpat = total.mul(r);
    return weightspat
        .map(
          (weights) => (find) {
            final w = weights;
            final idx = w.indexWhere((x) => x > find);
            return values[idx];
          },
        )
        .appLeft(findpat);
  });
}

Pattern wchoose(List<List<dynamic>> pairs) =>
    _wchooseWith(rand, pairs).outerJoin();

Pattern wchooseCycles(List<List<dynamic>> pairs) =>
    _wchooseWith(rand.segment(1), pairs).innerJoin();

Pattern wrandcat(List<List<dynamic>> pairs) => wchooseCycles(pairs);

extension PatternChooseExtension<T> on Pattern<T> {
  Pattern choose(List<dynamic> xs) => chooseWith(this, xs);

  Pattern choose2(List<dynamic> xs) => chooseWith(fromBipolar(), xs);
}

double _perlin(num t, int seed) {
  final ta = t.floor();
  final tb = ta + 1;
  double smootherStep(double x) =>
      (6.0 * math.pow(x, 5) - 15.0 * math.pow(x, 4) + 10.0 * math.pow(x, 3))
          .toDouble();
  double interp(double x, double a, double b) => a + smootherStep(x) * (b - a);
  final ra = getRandsAtTime(fraction(ta), seed: seed) as num;
  final rb = getRandsAtTime(fraction(tb), seed: seed) as num;
  return interp((t - ta).toDouble(), ra.toDouble(), rb.toDouble());
}

double _berlin(num t, int seed) {
  final prev = t.floor();
  final next = prev + 1;
  final prevBottom = getRandsAtTime(fraction(prev), seed: seed) as num;
  final height = getRandsAtTime(fraction(next), seed: seed) as num;
  final nextTop = prevBottom + height;
  final percent = (t - prev) / (next - prev);
  return (prevBottom + percent * (nextTop - prevBottom) / 2).toDouble();
}

Pattern<num> perlin = signal(
  (t, controls) => _perlin(
    t.toDouble(),
    controls['randSeed'] is int ? controls['randSeed'] as int : 0,
  ),
);

Pattern<num> berlin = signal(
  (t, controls) => _berlin(
    t.toDouble(),
    controls['randSeed'] is int ? controls['randSeed'] as int : 0,
  ),
);

Pattern degradeByWith(Pattern withPat, num x, Pattern pat) {
  return pat
      .map(
        (a) =>
            (_) => a,
      )
      .appLeft(withPat.filterValues((v) => v is num && v > x));
}

Pattern degradeBy(num x, Pattern pat) => degradeByWith(rand, x, pat);

Pattern degrade(Pattern pat) => degradeBy(0.5, pat);

Pattern undegradeBy(num x, Pattern pat) =>
    degradeByWith(rand.map((r) => 1 - r), x, pat);

Pattern undegrade(Pattern pat) => undegradeBy(0.5, pat);

Pattern sometimesBy(Pattern patx, Pattern Function(Pattern) func, Pattern pat) {
  return patx
      .map(
        (x) => stack([
          degradeBy(x, pat),
          func(undegradeBy(1 - x, pat)),
        ]),
      )
      .innerJoin();
}

Pattern sometimes(Pattern Function(Pattern) func, Pattern pat) =>
    sometimesBy(pure(0.5), func, pat);

Pattern someCyclesBy(
  Pattern patx,
  Pattern Function(Pattern) func,
  Pattern pat,
) {
  return patx.map((x) {
    final numX = x as num;
    return stack([
      degradeByWith(rand.segment(1), numX, pat),
      func(degradeByWith(rand.map((r) => 1 - r).segment(1), 1 - numX, pat)),
    ]);
  }).innerJoin();
}

Pattern someCycles(Pattern Function(Pattern) func, Pattern pat) =>
    someCyclesBy(pure(0.5), func, pat);

Pattern often(Pattern Function(Pattern) func, Pattern pat) =>
    sometimesBy(pure(0.75), func, pat);

Pattern rarely(Pattern Function(Pattern) func, Pattern pat) =>
    sometimesBy(pure(0.25), func, pat);

Pattern almostNever(Pattern Function(Pattern) func, Pattern pat) =>
    sometimesBy(pure(0.1), func, pat);

Pattern almostAlways(Pattern Function(Pattern) func, Pattern pat) =>
    sometimesBy(pure(0.9), func, pat);

Pattern never(Pattern Function(Pattern) func, Pattern pat) => pat;

Pattern always(Pattern Function(Pattern) func, Pattern pat) => func(pat);

bool _keyDown(dynamic keyname) {
  List<String> keys;
  if (keyname is List) {
    keys = keyname.map((k) => k.toString()).toList();
  } else {
    keys = [keyname.toString()];
  }
  final state = getCurrentKeyboardState();
  return keys.every((key) {
    final mapped = keyAlias[key] ?? key;
    return state[mapped] == true;
  });
}

Pattern whenKey(dynamic input, Pattern Function(Pattern) func, Pattern pat) {
  return pat.when(_keyDown(input), func);
}

Pattern keyDown(Pattern pat) => pat.map(_keyDown);

Pattern cyclesPer = Pattern(
  (state) => [Hap(null, state.span, state.span.duration)],
);

Pattern per = Pattern(
  (state) => [Hap(null, state.span, fraction(1) / state.span.duration)],
);

Pattern perCycle = per;

Pattern perx = Pattern((state) {
  final n = fraction(1) / state.span.duration;
  final val = (math.log(n.toDouble()) / math.ln2) + 1;
  return [Hap(null, state.span, val)];
});
