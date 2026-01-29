import 'hap.dart';
import 'pattern.dart';
import 'mini.dart';

typedef ControlMap = Map<String, dynamic>;

Pattern<ControlMap> createParam(String name, dynamic value) {
  return reify(value).map((v) => {name: v});
}

Pattern<ControlMap> s(dynamic value) {
  final parsed = _reifyString(value);
  return reify(parsed).map(_soundControlFromValue);
}
Pattern<ControlMap> n(dynamic value) => createParam('n', _reifyString(value));
Pattern<ControlMap> note(dynamic value) =>
    createParam('note', _reifyString(value));
Pattern<ControlMap> gain(dynamic value) => createParam('gain', value);
Pattern<ControlMap> pan(dynamic value) => createParam('pan', value);
Pattern<ControlMap> speed(dynamic value) => createParam('speed', value);
Pattern<ControlMap> velocity(dynamic value) => createParam('velocity', value);
Pattern<ControlMap> vowel(dynamic value) => createParam('vowel', value);
Pattern<ControlMap> lpf(dynamic value) => createParam('lpf', value);
Pattern<ControlMap> hpf(dynamic value) => createParam('hpf', value);
Pattern<ControlMap> bank(dynamic value) => createParam('bank', value);
Pattern<ControlMap> dec(dynamic value) => createParam('dec', value);
Pattern<ControlMap> attack(dynamic value) => createParam('attack', value);
Pattern<ControlMap> decay(dynamic value) => createParam('decay', value);
Pattern<ControlMap> sustain(dynamic value) => createParam('sustain', value);
Pattern<ControlMap> release(dynamic value) => createParam('release', value);
Pattern<ControlMap> bandf(dynamic value) => createParam('bandf', value);
Pattern<ControlMap> bandq(dynamic value) => createParam('bandq', value);
Pattern<ControlMap> hpq(dynamic value) => createParam('hpq', value);
Pattern<ControlMap> lpq(dynamic value) => createParam('lpq', value);
Pattern<ControlMap> cutoff(dynamic value) => createParam('cutoff', value);
Pattern<ControlMap> resonance(dynamic value) => createParam('resonance', value);
Pattern<ControlMap> room(dynamic value) => createParam('room', value);
Pattern<ControlMap> size(dynamic value) => createParam('size', value);
Pattern<ControlMap> dry(dynamic value) => createParam('dry', value);
Pattern<ControlMap> delay(dynamic value) => createParam('delay', value);
Pattern<ControlMap> delaytime(dynamic value) => createParam('delaytime', value);
Pattern<ControlMap> delayfeedback(dynamic value) =>
    createParam('delayfeedback', value);
Pattern<ControlMap> crush(dynamic value) => createParam('crush', value);
Pattern<ControlMap> coarse(dynamic value) => createParam('coarse', value);
Pattern<ControlMap> shape(dynamic value) => createParam('shape', value);
Pattern<ControlMap> color(dynamic value) => createParam('color', value);
Pattern<ControlMap> partials(dynamic value) => createParam('partials', value);
Pattern<ControlMap> phases(dynamic value) => createParam('phases', value);
Pattern<ControlMap> hsl(dynamic h, dynamic s, dynamic l) {
  final hue = (h as num).toDouble();
  final sat = (s as num).toDouble();
  final light = (l as num).toDouble();
  return color('hsl(${hue}turn,${sat * 100}%,${light * 100}%)');
}

Pattern<ControlMap> hsla(dynamic h, dynamic s, dynamic l, dynamic a) {
  final hue = (h as num).toDouble();
  final sat = (s as num).toDouble();
  final light = (l as num).toDouble();
  final alpha = (a as num).toDouble();
  return color('hsla(${hue}turn,${sat * 100}%,${light * 100}%,${alpha})');
}

Pattern<ControlMap> _distortWithAlg(
  String name,
  dynamic args, [
  Pattern<ControlMap>? pat,
]) {
  final argsPat = reify(args).map((v) {
    if (v is List) {
      return [...v, name];
    }
    return [v, 1, name];
  });
  if (pat == null) {
    return createParam('distort', argsPat);
  }
  return pat.distort(argsPat);
}

Pattern<ControlMap> soft(dynamic args) => _distortWithAlg('soft', args);
Pattern<ControlMap> hard(dynamic args) => _distortWithAlg('hard', args);
Pattern<ControlMap> cubic(dynamic args) => _distortWithAlg('cubic', args);
Pattern<ControlMap> diode(dynamic args) => _distortWithAlg('diode', args);
Pattern<ControlMap> asym(dynamic args) => _distortWithAlg('asym', args);
Pattern<ControlMap> fold(dynamic args) => _distortWithAlg('fold', args);
Pattern<ControlMap> sinefold(dynamic args) => _distortWithAlg('sinefold', args);
Pattern<ControlMap> chebyshev(dynamic args) =>
    _distortWithAlg('chebyshev', args);

List<dynamic> _normalizeAdsr(dynamic value) {
  if (value is List) return value;
  if (value is String) {
    final parts = value.split(':').map((v) => v.trim()).toList();
    return parts;
  }
  return [value];
}

Pattern<ControlMap> _applyAdsr(
  Pattern<ControlMap> pat,
  List<dynamic> values,
) {
  Pattern<ControlMap> out = pat;
  if (values.isNotEmpty) out = out.attack(_reifyString(values[0]));
  if (values.length > 1) out = out.decay(_reifyString(values[1]));
  if (values.length > 2) out = out.sustain(_reifyString(values[2]));
  if (values.length > 3) out = out.release(_reifyString(values[3]));
  return out;
}

Pattern<ControlMap> adsr(dynamic adsr) {
  final values = _normalizeAdsr(adsr);
  return _applyAdsr(pure(<String, dynamic>{}), values);
}

Pattern<ControlMap> ad(dynamic t) {
  final values = _normalizeAdsr(t);
  final attack = values.isNotEmpty ? values[0] : 0;
  final decay = values.length > 1 ? values[1] : attack;
  return _applyAdsr(pure(<String, dynamic>{}), [attack, decay]);
}

Pattern<ControlMap> ds(dynamic t) {
  final values = _normalizeAdsr(t);
  final decay = values.isNotEmpty ? values[0] : 0;
  final sustain = values.length > 1 ? values[1] : 0;
  return _applyAdsr(pure(<String, dynamic>{}), [null, decay, sustain]);
}

Pattern<ControlMap> ar(dynamic t) {
  final values = _normalizeAdsr(t);
  final attack = values.isNotEmpty ? values[0] : 0;
  final release = values.length > 1 ? values[1] : attack;
  return _applyAdsr(pure(<String, dynamic>{}), [attack, null, null, release]);
}

// Wavetable
Pattern<ControlMap> wt(dynamic value) => createParam('wt', value);
Pattern<ControlMap> wtenv(dynamic value) => createParam('wtenv', value);
Pattern<ControlMap> wtattack(dynamic value) => createParam('wtattack', value);
Pattern<ControlMap> wtdecay(dynamic value) => createParam('wtdecay', value);
Pattern<ControlMap> wtsustain(dynamic value) => createParam('wtsustain', value);
Pattern<ControlMap> wtrelease(dynamic value) => createParam('wtrelease', value);
Pattern<ControlMap> wtrate(dynamic value) => createParam('wtrate', value);
Pattern<ControlMap> wtsync(dynamic value) => createParam('wtsync', value);
Pattern<ControlMap> wtdepth(dynamic value) => createParam('wtdepth', value);
Pattern<ControlMap> wtshape(dynamic value) => createParam('wtshape', value);
Pattern<ControlMap> wtdc(dynamic value) => createParam('wtdc', value);
Pattern<ControlMap> wtskew(dynamic value) => createParam('wtskew', value);
Pattern<ControlMap> wtphaserand(dynamic value) =>
    createParam('wtphaserand', value);

// Warp
Pattern<ControlMap> warp(dynamic value) => createParam('warp', value);
Pattern<ControlMap> warpenv(dynamic value) => createParam('warpenv', value);
Pattern<ControlMap> warpattack(dynamic value) =>
    createParam('warpattack', value);
Pattern<ControlMap> warpdecay(dynamic value) => createParam('warpdecay', value);
Pattern<ControlMap> warpsustain(dynamic value) =>
    createParam('warpsustain', value);
Pattern<ControlMap> warprelease(dynamic value) =>
    createParam('warprelease', value);
Pattern<ControlMap> warprate(dynamic value) => createParam('warprate', value);
Pattern<ControlMap> warpsync(dynamic value) => createParam('warpsync', value);
Pattern<ControlMap> warpdepth(dynamic value) => createParam('warpdepth', value);
Pattern<ControlMap> warpshape(dynamic value) => createParam('warpshape', value);
Pattern<ControlMap> warpdc(dynamic value) => createParam('warpdc', value);
Pattern<ControlMap> warpskew(dynamic value) => createParam('warpskew', value);
Pattern<ControlMap> warpmode(dynamic value) => createParam('warpmode', value);

// Source/Gain
Pattern<ControlMap> source(dynamic value) => createParam('source', value);
Pattern<ControlMap> accelerate(dynamic value) =>
    createParam('accelerate', value);
Pattern<ControlMap> postgain(dynamic value) => createParam('postgain', value);
Pattern<ControlMap> amp(dynamic value) => createParam('amp', value);

// FM
Pattern<ControlMap> fmh(dynamic value) => createParam('fmh', value);
Pattern<ControlMap> fmi(dynamic value) => createParam('fmi', value);
Pattern<ControlMap> fmenv(dynamic value) => createParam('fmenv', value);
Pattern<ControlMap> fmattack(dynamic value) => createParam('fmattack', value);
Pattern<ControlMap> fmdecay(dynamic value) => createParam('fmdecay', value);
Pattern<ControlMap> fmsustain(dynamic value) => createParam('fmsustain', value);
Pattern<ControlMap> fmrelease(dynamic value) => createParam('fmrelease', value);
Pattern<ControlMap> fmwave(dynamic value) => createParam('fmwave', value);

// Effects
Pattern<ControlMap> chorus(dynamic value) => createParam('chorus', value);
Pattern<ControlMap> analyze(dynamic value) => createParam('analyze', value);
Pattern<ControlMap> fft(dynamic value) => createParam('fft', value);
Pattern<ControlMap> hold(dynamic value) => createParam('hold', value);
Pattern<ControlMap> drive(dynamic value) => createParam('drive', value);

// Sample Playback
Pattern<ControlMap> begin(dynamic value) => createParam('begin', value);
Pattern<ControlMap> end(dynamic value) => createParam('end', value);
Pattern<ControlMap> loop(dynamic value) => createParam('loop', value);
Pattern<ControlMap> loopBegin(dynamic value) => createParam('loopBegin', value);
Pattern<ControlMap> loopEnd(dynamic value) => createParam('loopEnd', value);
Pattern<ControlMap> cut(dynamic value) => createParam('cut', value);

// Tremolo
Pattern<ControlMap> tremolo(dynamic value) => createParam('tremolo', value);
Pattern<ControlMap> tremolosync(dynamic value) =>
    createParam('tremolosync', value);
Pattern<ControlMap> tremolodepth(dynamic value) =>
    createParam('tremolodepth', value);
Pattern<ControlMap> tremoloskew(dynamic value) =>
    createParam('tremoloskew', value);
Pattern<ControlMap> tremolophase(dynamic value) =>
    createParam('tremolophase', value);
Pattern<ControlMap> tremoloshape(dynamic value) =>
    createParam('tremoloshape', value);

// Ducking
Pattern<ControlMap> duck(dynamic value) => createParam('duck', value);
Pattern<ControlMap> duckdepth(dynamic value) => createParam('duckdepth', value);
Pattern<ControlMap> duckonset(dynamic value) => createParam('duckonset', value);
Pattern<ControlMap> duckattack(dynamic value) =>
    createParam('duckattack', value);

// ByteBeat
Pattern<ControlMap> byteBeatExpression(dynamic value) =>
    createParam('byteBeatExpression', value);
Pattern<ControlMap> byteBeatStartTime(dynamic value) =>
    createParam('byteBeatStartTime', value);

// Channels
Pattern<ControlMap> channels(dynamic value) => createParam('channels', value);

// PulseWidth
Pattern<ControlMap> pw(dynamic value) => createParam('pw', value);
Pattern<ControlMap> pwrate(dynamic value) => createParam('pwrate', value);
Pattern<ControlMap> pwsweep(dynamic value) => createParam('pwsweep', value);

// Phaser
Pattern<ControlMap> phaser(dynamic value) => createParam('phaser', value);
Pattern<ControlMap> phasersweep(dynamic value) =>
    createParam('phasersweep', value);
Pattern<ControlMap> phasercenter(dynamic value) =>
    createParam('phasercenter', value);
Pattern<ControlMap> phaserdepth(dynamic value) =>
    createParam('phaserdepth', value);

// Filter ADSR + Envelopes
Pattern<ControlMap> lpenv(dynamic value) => createParam('lpenv', value);
Pattern<ControlMap> hpenv(dynamic value) => createParam('hpenv', value);
Pattern<ControlMap> bpenv(dynamic value) => createParam('bpenv', value);

Pattern<ControlMap> lpattack(dynamic value) => createParam('lpattack', value);
Pattern<ControlMap> lpdecay(dynamic value) => createParam('lpdecay', value);
Pattern<ControlMap> lpsustain(dynamic value) => createParam('lpsustain', value);
Pattern<ControlMap> lprelease(dynamic value) => createParam('lprelease', value);

Pattern<ControlMap> hpattack(dynamic value) => createParam('hpattack', value);
Pattern<ControlMap> hpdecay(dynamic value) => createParam('hpdecay', value);
Pattern<ControlMap> hpsustain(dynamic value) => createParam('hpsustain', value);
Pattern<ControlMap> hprelease(dynamic value) => createParam('hprelease', value);

Pattern<ControlMap> bpattack(dynamic value) => createParam('bpattack', value);
Pattern<ControlMap> bpdecay(dynamic value) => createParam('bpdecay', value);
Pattern<ControlMap> bpsustain(dynamic value) => createParam('bpsustain', value);
Pattern<ControlMap> bprelease(dynamic value) => createParam('bprelease', value);

Pattern<ControlMap> ftype(dynamic value) => createParam('ftype', value);
Pattern<ControlMap> fanchor(dynamic value) => createParam('fanchor', value);

// Filter LFOs
Pattern<ControlMap> lprate(dynamic value) => createParam('lprate', value);
Pattern<ControlMap> lpsync(dynamic value) => createParam('lpsync', value);
Pattern<ControlMap> lpdepth(dynamic value) => createParam('lpdepth', value);
Pattern<ControlMap> lpdepthfreq(dynamic value) =>
    createParam('lpdepthfreq', value);
Pattern<ControlMap> lpshape(dynamic value) => createParam('lpshape', value);
Pattern<ControlMap> lpdc(dynamic value) => createParam('lpdc', value);
Pattern<ControlMap> lpskew(dynamic value) => createParam('lpskew', value);

Pattern<ControlMap> bprate(dynamic value) => createParam('bprate', value);
Pattern<ControlMap> bpsync(dynamic value) => createParam('bpsync', value);
Pattern<ControlMap> bpdepth(dynamic value) => createParam('bpdepth', value);
Pattern<ControlMap> bpdepthfreq(dynamic value) =>
    createParam('bpdepthfreq', value);
Pattern<ControlMap> bpshape(dynamic value) => createParam('bpshape', value);
Pattern<ControlMap> bpdc(dynamic value) => createParam('bpdc', value);
Pattern<ControlMap> bpskew(dynamic value) => createParam('bpskew', value);

// Highpass LFOs (inferred)
Pattern<ControlMap> hprate(dynamic value) => createParam('hprate', value);
Pattern<ControlMap> hpsync(dynamic value) => createParam('hpsync', value);
Pattern<ControlMap> hpdepth(dynamic value) => createParam('hpdepth', value);

dynamic _reifyString(dynamic value) {
  if (value is Pattern) return value;

  if (value is String) {
    print('Controls: Reifying string "$value"');
    try {
      final Pattern pat = mini(value);
      print('Controls: mini() success for "$value" -> $pat');
      return pat;
    } catch (e) {
      print('Controls: mini() failed for "$value": $e');
      return value;
    }
  }

  return value;
}

dynamic reifyString(dynamic value) {
  return _reifyString(value);
}

ControlMap _soundControlFromValue(dynamic value) {
  if (value is Map<String, dynamic>) return value;

  if (value is List) {
    final map = <String, dynamic>{};
    if (value.isNotEmpty) map['s'] = value[0];
    if (value.length > 1) map['n'] = _maybeNum(value[1]);
    if (value.length > 2) map['gain'] = _maybeNum(value[2]);
    return map;
  }

  if (value is String) {
    final parts = value.split(':');
    if (parts.length >= 2) {
      final nVal = _maybeNum(parts[1]);
      if (nVal is num) {
        final map = <String, dynamic>{'s': parts[0], 'n': nVal};
        if (parts.length > 2) {
          final gainVal = _maybeNum(parts[2]);
          if (gainVal != null) map['gain'] = gainVal;
        }
        return map;
      }
    }
    return {'s': value};
  }

  return {'s': value};
}

dynamic _maybeNum(dynamic value) {
  if (value is num) return value;
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) return parsed;
  }
  return value;
}

extension ControlPatternExtension on Pattern<ControlMap> {
  Pattern<ControlMap> addControl(String name, dynamic value) {
    final other = createParam(name, value);
    return Pattern((state) {
      final haps1 = query(state);
      final haps2 = other.query(state);
      final List<Hap<ControlMap>> results = [];

      for (final h1 in haps1) {
        for (final h2 in haps2) {
          final intersection = h1.part.intersection(h2.part);
          if (intersection != null) {
            results.add(
              Hap(h1.whole!.intersection(h2.whole!)!, intersection, {
                ...h1.value,
                ...h2.value,
              }),
            );
          }
        }
      }
      return results;
    }, steps: steps);
  }

  Pattern<ControlMap> s(dynamic value) => addControl('s', _reifyString(value));
  Pattern<ControlMap> n(dynamic value) => addControl('n', _reifyString(value));
  Pattern<ControlMap> note(dynamic value) =>
      addControl('note', _reifyString(value));
  Pattern<ControlMap> gain(dynamic value) => addControl('gain', value);
  Pattern<ControlMap> pan(dynamic value) => addControl('pan', value);
  Pattern<ControlMap> speed(dynamic value) => addControl('speed', value);
  Pattern<ControlMap> velocity(dynamic value) => addControl('velocity', value);
  Pattern<ControlMap> vowel(dynamic value) => addControl('vowel', value);
  Pattern<ControlMap> lpf(dynamic value) => addControl('lpf', value);
  Pattern<ControlMap> hpf(dynamic value) => addControl('hpf', value);
  Pattern<ControlMap> bank(dynamic value) => addControl('bank', value);
  Pattern<ControlMap> dec(dynamic value) => addControl('dec', value);
  Pattern<ControlMap> attack(dynamic value) => addControl('attack', value);
  Pattern<ControlMap> decay(dynamic value) => addControl('decay', value);
  Pattern<ControlMap> sustain(dynamic value) => addControl('sustain', value);
  Pattern<ControlMap> release(dynamic value) => addControl('release', value);
  Pattern<ControlMap> bandf(dynamic value) => addControl('bandf', value);
  Pattern<ControlMap> bandq(dynamic value) => addControl('bandq', value);
  Pattern<ControlMap> hpq(dynamic value) => addControl('hpq', value);
  Pattern<ControlMap> lpq(dynamic value) => addControl('lpq', value);
  Pattern<ControlMap> cutoff(dynamic value) => addControl('cutoff', value);
  Pattern<ControlMap> resonance(dynamic value) =>
      addControl('resonance', value);
  Pattern<ControlMap> room(dynamic value) => addControl('room', value);
  Pattern<ControlMap> size(dynamic value) => addControl('size', value);
  Pattern<ControlMap> dry(dynamic value) => addControl('dry', value);
  Pattern<ControlMap> roomsize(dynamic value) => addControl('roomsize', value);
  Pattern<ControlMap> roomfade(dynamic value) => addControl('roomfade', value);
  Pattern<ControlMap> roomlp(dynamic value) => addControl('roomlp', value);
  Pattern<ControlMap> distort(dynamic value) => addControl('distort', value);
  Pattern<ControlMap> delay(dynamic value) => addControl('delay', value);
  Pattern<ControlMap> delaytime(dynamic value) =>
      addControl('delaytime', value);
  Pattern<ControlMap> delayfeedback(dynamic value) =>
      addControl('delayfeedback', value);
  Pattern<ControlMap> roomdim(dynamic value) => addControl('roomdim', value);
  Pattern<ControlMap> orbit(dynamic value) => addControl('orbit', value);
  Pattern<ControlMap> compressor(dynamic value) =>
      addControl('compressor', value);
  Pattern<ControlMap> clip(dynamic value) => addControl('clip', value);
  Pattern<ControlMap> crush(dynamic value) => addControl('crush', value);
  Pattern<ControlMap> coarse(dynamic value) => addControl('coarse', value);
  Pattern<ControlMap> shape(dynamic value) => addControl('shape', value);
  Pattern<ControlMap> color(dynamic value) => addControl('color', value);
  Pattern<ControlMap> partials(dynamic value) => addControl('partials', value);
  Pattern<ControlMap> phases(dynamic value) => addControl('phases', value);
  Pattern<ControlMap> hsl(dynamic h, dynamic s, dynamic l) =>
      color('hsl(${(h as num)}turn,${(s as num) * 100}%,${(l as num) * 100}%)');
  Pattern<ControlMap> hsla(dynamic h, dynamic s, dynamic l, dynamic a) => color(
        'hsla(${(h as num)}turn,${(s as num) * 100}%,${(l as num) * 100}%,${(a as num)})',
      );
  Pattern<ControlMap> adsr(dynamic adsr) {
    final values = _normalizeAdsr(adsr);
    return _applyAdsr(this, values);
  }
  Pattern<ControlMap> ad(dynamic t) {
    final values = _normalizeAdsr(t);
    final attack = values.isNotEmpty ? values[0] : 0;
    final decay = values.length > 1 ? values[1] : attack;
    return _applyAdsr(this, [attack, decay]);
  }
  Pattern<ControlMap> ds(dynamic t) {
    final values = _normalizeAdsr(t);
    final decay = values.isNotEmpty ? values[0] : 0;
    final sustain = values.length > 1 ? values[1] : 0;
    return _applyAdsr(this, [null, decay, sustain]);
  }
  Pattern<ControlMap> ar(dynamic t) {
    final values = _normalizeAdsr(t);
    final attack = values.isNotEmpty ? values[0] : 0;
    final release = values.length > 1 ? values[1] : attack;
    return _applyAdsr(this, [attack, null, null, release]);
  }
  Pattern<ControlMap> soft(dynamic args) => _distortWithAlg('soft', args, this);
  Pattern<ControlMap> hard(dynamic args) => _distortWithAlg('hard', args, this);
  Pattern<ControlMap> cubic(dynamic args) =>
      _distortWithAlg('cubic', args, this);
  Pattern<ControlMap> diode(dynamic args) =>
      _distortWithAlg('diode', args, this);
  Pattern<ControlMap> asym(dynamic args) => _distortWithAlg('asym', args, this);
  Pattern<ControlMap> fold(dynamic args) => _distortWithAlg('fold', args, this);
  Pattern<ControlMap> sinefold(dynamic args) =>
      _distortWithAlg('sinefold', args, this);
  Pattern<ControlMap> chebyshev(dynamic args) =>
      _distortWithAlg('chebyshev', args, this);

  Pattern<ControlMap> FX(List<dynamic> effects) {
    final effectsPat = sequenceP(effects);
    return withValue((v) {
          return (dynamic vEff) {
            final curr = v['FX'];
            final next = <dynamic>[];
            if (curr is List) {
              next.addAll(curr);
            }
            if (vEff is List) {
              next.addAll(vEff);
            } else {
              next.add(vEff);
            }
            return {...v, 'FX': next};
          };
        }).appLeft(effectsPat)
        as Pattern<ControlMap>;
  }

  Pattern<ControlMap> worklet(String src, [List<dynamic> inputs = const []]) {
    final inputsPat = sequenceP(inputs);
    return outerBind((v) {
      return inputsPat.withValue((vInput) {
        final currInputs = v['workletInputs'];
        final nextInputs = <dynamic>[];
        if (currInputs is List) {
          nextInputs.addAll(currInputs);
        }
        if (vInput is List) {
          nextInputs.addAll(vInput);
        } else {
          nextInputs.add(vInput);
        }
        return {...v, 'workletSrc': src, 'workletInputs': nextInputs};
      });
    }).cast<ControlMap>();
  }

  // Wavetable
  Pattern<ControlMap> wt(dynamic value) => addControl('wt', value);
  Pattern<ControlMap> wtenv(dynamic value) => addControl('wtenv', value);
  Pattern<ControlMap> wtattack(dynamic value) => addControl('wtattack', value);
  Pattern<ControlMap> wtdecay(dynamic value) => addControl('wtdecay', value);
  Pattern<ControlMap> wtsustain(dynamic value) =>
      addControl('wtsustain', value);
  Pattern<ControlMap> wtrelease(dynamic value) =>
      addControl('wtrelease', value);
  Pattern<ControlMap> wtrate(dynamic value) => addControl('wtrate', value);
  Pattern<ControlMap> wtsync(dynamic value) => addControl('wtsync', value);
  Pattern<ControlMap> wtdepth(dynamic value) => addControl('wtdepth', value);
  Pattern<ControlMap> wtshape(dynamic value) => addControl('wtshape', value);
  Pattern<ControlMap> wtdc(dynamic value) => addControl('wtdc', value);
  Pattern<ControlMap> wtskew(dynamic value) => addControl('wtskew', value);
  Pattern<ControlMap> wtphaserand(dynamic value) =>
      addControl('wtphaserand', value);

  // Warp
  Pattern<ControlMap> warp(dynamic value) => addControl('warp', value);
  Pattern<ControlMap> warpenv(dynamic value) => addControl('warpenv', value);
  Pattern<ControlMap> warpattack(dynamic value) =>
      addControl('warpattack', value);
  Pattern<ControlMap> warpdecay(dynamic value) =>
      addControl('warpdecay', value);
  Pattern<ControlMap> warpsustain(dynamic value) =>
      addControl('warpsustain', value);
  Pattern<ControlMap> warprelease(dynamic value) =>
      addControl('warprelease', value);
  Pattern<ControlMap> warprate(dynamic value) => addControl('warprate', value);
  Pattern<ControlMap> warpsync(dynamic value) => addControl('warpsync', value);
  Pattern<ControlMap> warpdepth(dynamic value) =>
      addControl('warpdepth', value);
  Pattern<ControlMap> warpshape(dynamic value) =>
      addControl('warpshape', value);
  Pattern<ControlMap> warpdc(dynamic value) => addControl('warpdc', value);
  Pattern<ControlMap> warpskew(dynamic value) => addControl('warpskew', value);
  Pattern<ControlMap> warpmode(dynamic value) => addControl('warpmode', value);

  // Source/Gain
  Pattern<ControlMap> source(dynamic value) => addControl('source', value);
  Pattern<ControlMap> accelerate(dynamic value) =>
      addControl('accelerate', value);
  Pattern<ControlMap> postgain(dynamic value) => addControl('postgain', value);
  Pattern<ControlMap> amp(dynamic value) => addControl('amp', value);

  // FM
  Pattern<ControlMap> fmh(dynamic value) => addControl('fmh', value);
  Pattern<ControlMap> fmi(dynamic value) => addControl('fmi', value);
  Pattern<ControlMap> fmenv(dynamic value) => addControl('fmenv', value);
  Pattern<ControlMap> fmattack(dynamic value) => addControl('fmattack', value);
  Pattern<ControlMap> fmdecay(dynamic value) => addControl('fmdecay', value);
  Pattern<ControlMap> fmsustain(dynamic value) =>
      addControl('fmsustain', value);
  Pattern<ControlMap> fmrelease(dynamic value) =>
      addControl('fmrelease', value);
  Pattern<ControlMap> fmwave(dynamic value) => addControl('fmwave', value);

  // Effects
  Pattern<ControlMap> chorus(dynamic value) => addControl('chorus', value);
  Pattern<ControlMap> analyze(dynamic value) => addControl('analyze', value);
  Pattern<ControlMap> fft(dynamic value) => addControl('fft', value);
  Pattern<ControlMap> hold(dynamic value) => addControl('hold', value);
  Pattern<ControlMap> drive(dynamic value) => addControl('drive', value);

  // Sample Playback
  Pattern<ControlMap> begin(dynamic value) => addControl('begin', value);
  Pattern<ControlMap> end(dynamic value) => addControl('end', value);
  Pattern<ControlMap> loop(dynamic value) => addControl('loop', value);
  Pattern<ControlMap> loopBegin(dynamic value) =>
      addControl('loopBegin', value);
  Pattern<ControlMap> loopEnd(dynamic value) => addControl('loopEnd', value);
  Pattern<ControlMap> cut(dynamic value) => addControl('cut', value);

  // Tremolo
  Pattern<ControlMap> tremolo(dynamic value) => addControl('tremolo', value);
  Pattern<ControlMap> tremolosync(dynamic value) =>
      addControl('tremolosync', value);
  Pattern<ControlMap> tremolodepth(dynamic value) =>
      addControl('tremolodepth', value);
  Pattern<ControlMap> tremoloskew(dynamic value) =>
      addControl('tremoloskew', value);
  Pattern<ControlMap> tremolophase(dynamic value) =>
      addControl('tremolophase', value);
  Pattern<ControlMap> tremoloshape(dynamic value) =>
      addControl('tremoloshape', value);

  // Ducking
  Pattern<ControlMap> duck(dynamic value) => addControl('duck', value);
  Pattern<ControlMap> duckdepth(dynamic value) =>
      addControl('duckdepth', value);
  Pattern<ControlMap> duckonset(dynamic value) =>
      addControl('duckonset', value);
  Pattern<ControlMap> duckattack(dynamic value) =>
      addControl('duckattack', value);

  // ByteBeat
  Pattern<ControlMap> byteBeatExpression(dynamic value) =>
      addControl('byteBeatExpression', value);
  Pattern<ControlMap> byteBeatStartTime(dynamic value) =>
      addControl('byteBeatStartTime', value);

  // Channels
  Pattern<ControlMap> channels(dynamic value) => addControl('channels', value);

  // PulseWidth
  Pattern<ControlMap> pw(dynamic value) => addControl('pw', value);
  Pattern<ControlMap> pwrate(dynamic value) => addControl('pwrate', value);
  Pattern<ControlMap> pwsweep(dynamic value) => addControl('pwsweep', value);

  // Phaser
  Pattern<ControlMap> phaser(dynamic value) => addControl('phaser', value);
  Pattern<ControlMap> phasersweep(dynamic value) =>
      addControl('phasersweep', value);
  Pattern<ControlMap> phasercenter(dynamic value) =>
      addControl('phasercenter', value);
  Pattern<ControlMap> phaserdepth(dynamic value) =>
      addControl('phaserdepth', value);

  // Filter ADSR + Envelopes
  Pattern<ControlMap> lpenv(dynamic value) => addControl('lpenv', value);
  Pattern<ControlMap> hpenv(dynamic value) => addControl('hpenv', value);
  Pattern<ControlMap> bpenv(dynamic value) => addControl('bpenv', value);

  Pattern<ControlMap> lpattack(dynamic value) => addControl('lpattack', value);
  Pattern<ControlMap> lpdecay(dynamic value) => addControl('lpdecay', value);
  Pattern<ControlMap> lpsustain(dynamic value) =>
      addControl('lpsustain', value);
  Pattern<ControlMap> lprelease(dynamic value) =>
      addControl('lprelease', value);

  Pattern<ControlMap> hpattack(dynamic value) => addControl('hpattack', value);
  Pattern<ControlMap> hpdecay(dynamic value) => addControl('hpdecay', value);
  Pattern<ControlMap> hpsustain(dynamic value) =>
      addControl('hpsustain', value);
  Pattern<ControlMap> hprelease(dynamic value) =>
      addControl('hprelease', value);

  Pattern<ControlMap> bpattack(dynamic value) => addControl('bpattack', value);
  Pattern<ControlMap> bpdecay(dynamic value) => addControl('bpdecay', value);
  Pattern<ControlMap> bpsustain(dynamic value) =>
      addControl('bpsustain', value);
  Pattern<ControlMap> bprelease(dynamic value) =>
      addControl('bprelease', value);

  Pattern<ControlMap> ftype(dynamic value) => addControl('ftype', value);
  Pattern<ControlMap> fanchor(dynamic value) => addControl('fanchor', value);

  // Filter LFOs
  Pattern<ControlMap> lprate(dynamic value) => addControl('lprate', value);
  Pattern<ControlMap> lpsync(dynamic value) => addControl('lpsync', value);
  Pattern<ControlMap> lpdepth(dynamic value) => addControl('lpdepth', value);
  Pattern<ControlMap> lpdepthfreq(dynamic value) =>
      addControl('lpdepthfreq', value);
  Pattern<ControlMap> lpshape(dynamic value) => addControl('lpshape', value);
  Pattern<ControlMap> lpdc(dynamic value) => addControl('lpdc', value);
  Pattern<ControlMap> lpskew(dynamic value) => addControl('lpskew', value);

  Pattern<ControlMap> bprate(dynamic value) => addControl('bprate', value);
  Pattern<ControlMap> bpsync(dynamic value) => addControl('bpsync', value);
  Pattern<ControlMap> bpdepth(dynamic value) => addControl('bpdepth', value);
  Pattern<ControlMap> bpdepthfreq(dynamic value) =>
      addControl('bpdepthfreq', value);
  Pattern<ControlMap> bpshape(dynamic value) => addControl('bpshape', value);
  Pattern<ControlMap> bpdc(dynamic value) => addControl('bpdc', value);
  Pattern<ControlMap> bpskew(dynamic value) => addControl('bpskew', value);

  // Highpass LFOs (inferred)
  Pattern<ControlMap> hprate(dynamic value) => addControl('hprate', value);
  Pattern<ControlMap> hpsync(dynamic value) => addControl('hpsync', value);
  Pattern<ControlMap> hpdepth(dynamic value) => addControl('hpdepth', value);

  Pattern<ControlMap> jux(Pattern<ControlMap> Function(Pattern<ControlMap>) f) {
    return stack([pan(0), f(this).pan(1)]);
  }

  Pattern<ControlMap> overlay(dynamic other) => stack([this, other]);
  Pattern<ControlMap> cat(List<dynamic> others) => slowcat([this, ...others]);
}

Pattern<ControlMap> worklet(String src, [List<dynamic> inputs = const []]) {
  return pure<ControlMap>({}).worklet(src, inputs);
}
