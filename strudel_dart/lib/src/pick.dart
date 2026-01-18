import 'pattern.dart';
import 'util.dart';

Pattern _pick(dynamic lookup, dynamic pat, {required bool modulo}) {
  final bool array = lookup is List;
  final int len = array ? lookup.length : (lookup as Map).length;

  final mapped = objectMap(lookup, (value, _, __) => reify(value));

  if (len == 0) {
    return silence;
  }

  final pattern = reify(pat);
  return pattern.map((i) {
    var key = i;
    if (array) {
      if (key is num) {
        final idx = key.round();
        key = (modulo ? mod(idx, len) : clamp(idx, 0, len - 1)).toInt();
      }
    }
    return array ? (mapped as List)[key as int] : (mapped as Map)[key];
  });
}

Pattern pick(dynamic lookup, dynamic pat) {
  if (pat is List) {
    final tmp = pat;
    pat = lookup;
    lookup = tmp;
  }
  return _pick(lookup, reify(pat), modulo: false).innerJoin();
}

Pattern pickmod(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: true).innerJoin();
}

Pattern pickF(dynamic lookup, List<Function> funcs, Pattern pat) {
  return pat.apply(pick(lookup, funcs));
}

Pattern pickmodF(dynamic lookup, List<Function> funcs, Pattern pat) {
  return pat.apply(pickmod(funcs, lookup));
}

Pattern pickOut(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: false).outerJoin();
}

Pattern pickmodOut(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: true).outerJoin();
}

Pattern pickRestart(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: false).restartJoin();
}

Pattern pickmodRestart(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: true).restartJoin();
}

Pattern pickReset(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: false).resetJoin();
}

Pattern pickmodReset(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: true).resetJoin();
}

Pattern inhabit(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: false).squeezeJoin();
}

Pattern pickSqueeze(dynamic lookup, Pattern pat) => inhabit(lookup, pat);

Pattern inhabitmod(dynamic lookup, dynamic pat) {
  return _pick(lookup, pat, modulo: true).squeezeJoin();
}

Pattern pickmodSqueeze(dynamic lookup, Pattern pat) => inhabitmod(lookup, pat);

Pattern squeeze(Pattern pat, List<dynamic> xs) {
  final values = xs.map(reify).toList();
  if (values.isEmpty) return silence;
  return pat.map((i) {
    final idx = mod((i as num).round(), values.length).toInt();
    return values[idx];
  }).squeezeJoin();
}
