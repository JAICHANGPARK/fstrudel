import 'package:petitparser/petitparser.dart';
import 'controls.dart' as c;
import 'pattern.dart' as p;
import 'bjorklund.dart' as b;

class StrudelREPL {
  late final Parser _parser;
  void Function(double)? onCpsChange;

  StrudelREPL({this.onCpsChange}) {
    _parser = StrudelGrammarDefinition(onCpsChange: onCpsChange).build();
  }

  p.Pattern evaluate(String input) {
    final lines = input.split('\n');
    final patterns = <p.Pattern>[];
    bool hasExplicitBlock = false;

    for (var line in lines) {
      line = line.trim();
      if (line.startsWith(
        r'$'
        ':',
      )) {
        hasExplicitBlock = true;
        final code = line.substring(2).trim();
        if (code.isNotEmpty) {
          final result = _parser.parse(code);
          if (result is Failure) {
            throw Exception(
              'Parse error in line "$line": ${result.message} at ${result.position}',
            );
          }
          if (result.value is List) {
            patterns.addAll((result.value as List).cast<p.Pattern>());
          } else {
            patterns.add(result.value as p.Pattern);
          }
        }
      }
    }

    if (!hasExplicitBlock) {
      String code = input.trim();
      if (code.isEmpty) return p.silence;

      // Handle legacy single-line explicit block that might have been missed if it was passed as single string
      if (code.startsWith(
        r'$'
        ':',
      )) {
        code = code.substring(2).trim();
      }

      final result = _parser.parse(code);
      if (result is Failure) {
        throw Exception('Parse error: ${result.message} at ${result.position}');
      }
      final list = result.value as List;
      if (list.isEmpty) return p.silence;
      return p.stack(list);
    }

    if (patterns.isEmpty) return p.silence;
    if (patterns.length == 1) return patterns[0];
    return p.stack(patterns);
  }
}

class StrudelGrammarDefinition extends GrammarDefinition {
  final void Function(double)? onCpsChange;

  StrudelGrammarDefinition({this.onCpsChange});

  @override
  Parser start() => ref0(expression).trim().star().end();

  Parser expression() => ref0(additive);

  Parser additive() =>
      (ref0(multiplicative) &
              (char('+') | char('-')).trim() &
              ref0(multiplicative))
          .map((values) {
            final left = values[0];
            final op = values[1] as String;
            final right = values[2];
            if (left is num && right is num) {
              return op == '+' ? left + right : left - right;
            }
            final lPat = p.reify(left);
            return op == '+' ? lPat.add(right) : lPat.sub(right);
          }) |
      ref0(multiplicative);

  Parser multiplicative() =>
      (ref0(methodChain) &
              (char('*') | char('/') | char('%')).trim() &
              ref0(methodChain))
          .map((values) {
            final left = values[0];
            final op = values[1] as String;
            final right = values[2];
            if (left is num && right is num) {
              if (op == '*') return left * right;
              if (op == '/') return left / right;
              if (op == '%') return left % right;
            }
            final lPat = p.reify(left);
            if (op == '*') return lPat.mul(right);
            if (op == '/') return lPat.div(right);
            if (op == '%') return lPat.mod(right);
            return lPat; // transform to error?
          }) |
      ref0(methodChain);

  Parser methodChain() => ref0(atom).seq(ref0(methodCall).star()).map((values) {
    var result = values[0];
    final calls = values[1] as List;
    for (final call in calls) {
      final methodName = call[0] as String;
      final args = call[1] as List;
      result = _invokeMethod(result, methodName, args);
    }
    return result;
  });

  Parser atom() =>
      ref0(functionCall) |
      ref0(parenthesizedExpression) |
      ref0(literal) |
      ref0(identifier).map((id) => _resolveIdentifier(id));

  Parser parenthesizedExpression() =>
      (char('(').trim() & ref0(expression) & char(')').trim()).map((v) => v[1]);

  Parser functionCall() => (ref0(identifier) & ref0(arguments)).map((values) {
    final name = values[0] as String;
    final args = values[1] as List;
    return _invokeFunction(name, args);
  });

  Parser methodCall() =>
      (char('.').trim() & ref0(identifier) & ref0(arguments)).map((values) {
        return [values[1], values[2]];
      });

  Parser arguments() =>
      (char('(').trim() & ref0(expressionList).optional() & char(')').trim())
          .map((values) => values[1] ?? []);

  Parser expressionList() => ref0(
    expression,
  ).plusSeparated(char(',').trim()).map((values) => values.elements);

  Parser literal() => ref0(stringLiteral) | ref0(numberLiteral);

  Parser stringLiteral() =>
      ((char("'") & any().starLazy(char("'")).flatten() & char("'")).pick(1) |
              (char('"') & any().starLazy(char('"')).flatten() & char('"'))
                  .pick(1) |
              (char('`') & any().starLazy(char('`')).flatten() & char('`'))
                  .pick(1))
          .trim();

  Parser numberLiteral() =>
      ((char('-').optional() &
                  ((digit().plus() & (char('.') & digit().plus()).optional()) |
                      (char('.') & digit().plus())))
              .flatten()
              .map(num.parse))
          .trim();

  Parser identifier() =>
      (letter() & (word() | char('_')).star()).flatten().trim();

  dynamic _resolveIdentifier(String name) {
    switch (name) {
      case 'rev':
        return (dynamic x) => (x as p.Pattern).rev() as dynamic;
      default:
        // fallback to string for things like bank names?
        // or throw? For now return string to be safe for reification
        return name;
    }
  }

  dynamic _invokeFunction(String name, List args) {
    switch (name) {
      case 's':
      case 'sound':
        return c.s(args.isEmpty ? '' : args[0]);
      case 'n':
        return c.n(args.isEmpty ? '' : args[0]);
      case 'note':
        return c.note(args.isEmpty ? '' : args[0]);
      case 'gain':
        return c.gain(args.isEmpty ? 1.0 : args[0]);
      case 'pan':
        return c.pan(args.isEmpty ? 0.5 : args[0]);
      case 'speed':
        return c.speed(args.isEmpty ? 1.0 : args[0]);
      case 'velocity':
        return c.velocity(args.isEmpty ? 1.0 : args[0]);
      case 'vowel':
        return c.vowel(args.isEmpty ? '' : args[0]);
      case 'lpf':
        return c.lpf(args.isEmpty ? 0.0 : args[0]);
      case 'hpf':
        return c.hpf(args.isEmpty ? 0.0 : args[0]);
      case 'bank':
        return c.bank(args.isEmpty ? '' : args[0]);
      case 'dec':
        return c.dec(args.isEmpty ? 0.0 : args[0]);
      case 'stack':
        return p.stack(args);
      case 'sequence':
        return p.sequence(args);
      case 'setcps':
      case 'cps':
        final val = args.isEmpty ? 0.5 : (args[0] as num).toDouble();
        onCpsChange?.call(val);
        return p.silence;
      case 'setcpm':
      case 'cpm':
        final val = args.isEmpty ? 120.0 : (args[0] as num).toDouble();
        onCpsChange?.call(val / 60.0);
        return p.silence;
      case 'setbpm':
      case 'bpm':
        final val = args.isEmpty ? 120.0 : (args[0] as num).toDouble();
        onCpsChange?.call(val / 240.0);
        return p.silence;
      case 'attack':
        return c.attack(args[0]);
      case 'decay':
        return c.decay(args[0]);
      case 'sustain':
        return c.sustain(args[0]);
      case 'release':
        return c.release(args[0]);
      case 'lpq':
        return c.lpq(args[0]);
      case 'hpq':
        return c.hpq(args[0]);
      case 'bandf':
        return c.bandf(args[0]);
      case 'bandq':
        return c.bandq(args[0]);
      case 'room':
        return c.room(args[0]);
      case 'size':
        return c.size(args[0]);
      case 'dry':
        return c.dry(args[0]);
      case 'delay':
        return c.delay(args[0]);
      case 'delaytime':
        return c.delaytime(args[0]);
      case 'delayfeedback':
        return c.delayfeedback(args[0]);
      case 'crush':
        return c.crush(args[0]);
      case 'coarse':
        return c.coarse(args[0]);
      case 'shape':
        return c.shape(args[0]);
      case 'cutoff':
        return c.cutoff(args[0]);
      case 'resonance':
        return c.resonance(args[0]);

      // Wavetable
      case 'wt':
        return c.wt(args[0]);
      case 'wtenv':
        return c.wtenv(args[0]);
      case 'wtattack':
      case 'wtatt':
        return c.wtattack(args[0]);
      case 'wtdecay':
      case 'wtdec':
        return c.wtdecay(args[0]);
      case 'wtsustain':
      case 'wtsus':
        return c.wtsustain(args[0]);
      case 'wtrelease':
      case 'wtrel':
        return c.wtrelease(args[0]);
      case 'wtrate':
        return c.wtrate(args[0]);
      case 'wtsync':
        return c.wtsync(args[0]);
      case 'wtdepth':
        return c.wtdepth(args[0]);
      case 'wtshape':
        return c.wtshape(args[0]);
      case 'wtdc':
        return c.wtdc(args[0]);
      case 'wtskew':
        return c.wtskew(args[0]);
      case 'wtphaserand':
        return c.wtphaserand(args[0]);

      // Warp
      case 'warp':
        return c.warp(args[0]);
      case 'warpenv':
        return c.warpenv(args[0]);
      case 'warpattack':
      case 'warpatt':
        return c.warpattack(args[0]);
      case 'warpdecay':
      case 'warpdec':
        return c.warpdecay(args[0]);
      case 'warpsustain':
      case 'warpsus':
        return c.warpsustain(args[0]);
      case 'warprelease':
      case 'warprel':
        return c.warprelease(args[0]);
      case 'warprate':
        return c.warprate(args[0]);
      case 'warpsync':
        return c.warpsync(args[0]);
      case 'warpdepth':
        return c.warpdepth(args[0]);
      case 'warpshape':
        return c.warpshape(args[0]);
      case 'warpdc':
        return c.warpdc(args[0]);
      case 'warpskew':
        return c.warpskew(args[0]);
      case 'warpmode':
        return c.warpmode(args[0]);

      // Source/Gain
      case 'source':
      case 'src':
        return c.source(args[0]);
      case 'accelerate':
        return c.accelerate(args[0]);
      case 'postgain':
        return c.postgain(args[0]);
      case 'amp':
        return c.amp(args[0]);

      // FM
      case 'fmh':
        return c.fmh(args[0]);
      case 'fmi':
      case 'fm':
        return c.fmi(args[0]);
      case 'fmenv':
        return c.fmenv(args[0]);
      case 'fmattack':
      case 'fmatt':
        return c.fmattack(args[0]);
      case 'fmdecay':
      case 'fmdec':
        return c.fmdecay(args[0]);
      case 'fmsustain':
      case 'fmsus':
        return c.fmsustain(args[0]);
      case 'fmrelease':
      case 'fmrel':
        return c.fmrelease(args[0]);
      case 'fmwave':
        return c.fmwave(args[0]);

      // Effects
      case 'chorus':
        return c.chorus(args[0]);
      case 'analyze':
        return c.analyze(args[0]);
      case 'fft':
        return c.fft(args[0]);
      case 'hold':
        return c.hold(args[0]);
      case 'drive':
        return c.drive(args[0]);

      // Sample Playback
      case 'begin':
        return c.begin(args[0]);
      case 'end':
        return c.end(args[0]);
      case 'loop':
        return c.loop(args[0]);
      case 'loopBegin':
      case 'loopb':
        return c.loopBegin(args[0]);
      case 'loopEnd':
      case 'loope':
        return c.loopEnd(args[0]);
      case 'cut':
        return c.cut(args[0]);

      // Tremolo
      case 'tremolo':
      case 'trem':
        return c.tremolo(args[0]);
      case 'tremolosync':
      case 'tremsync':
        return c.tremolosync(args[0]);
      case 'tremolodepth':
      case 'tremdepth':
        return c.tremolodepth(args[0]);
      case 'tremoloskew':
      case 'tremskew':
        return c.tremoloskew(args[0]);
      case 'tremolophase':
      case 'tremphase':
        return c.tremolophase(args[0]);
      case 'tremoloshape':
      case 'tremshape':
        return c.tremoloshape(args[0]);

      // Ducking
      case 'duck':
      case 'duckorbit':
        return c.duck(args[0]);
      case 'duckdepth':
        return c.duckdepth(args[0]);
      case 'duckonset':
      case 'duckons':
        return c.duckonset(args[0]);
      case 'duckattack':
      case 'duckatt':
        return c.duckattack(args[0]);

      // ByteBeat
      case 'byteBeatExpression':
      case 'bbexpr':
        return c.byteBeatExpression(args[0]);
      case 'byteBeatStartTime':
      case 'bbst':
        return c.byteBeatStartTime(args[0]);

      // Channels
      case 'channels':
      case 'ch':
        return c.channels(args[0]);

      // PulseWidth
      case 'pw':
        return c.pw(args[0]);
      case 'pwrate':
        return c.pwrate(args[0]);
      case 'pwsweep':
        return c.pwsweep(args[0]);

      // Phaser
      case 'phaser':
      case 'ph':
        return c.phaser(args[0]);
      case 'phasersweep':
      case 'phs':
        return c.phasersweep(args[0]);
      case 'phasercenter':
      case 'phc':
        return c.phasercenter(args[0]);
      case 'phaserdepth':
      case 'phd':
        return c.phaserdepth(args[0]);

      // Filter ADSR + Envelopes
      case 'lpenv':
      case 'lpe':
        return c.lpenv(args[0]);
      case 'hpenv':
      case 'hpe':
        return c.hpenv(args[0]);
      case 'bpenv':
      case 'bpe':
        return c.bpenv(args[0]);

      case 'lpattack':
      case 'lpa':
        return c.lpattack(args[0]);
      case 'lpdecay':
      case 'lpd':
        return c.lpdecay(args[0]);
      case 'lpsustain':
      case 'lps':
        return c.lpsustain(args[0]);
      case 'lprelease':
      case 'lpr':
        return c.lprelease(args[0]);

      case 'hpattack':
      case 'hpa':
        return c.hpattack(args[0]);
      case 'hpdecay':
      case 'hpd':
        return c.hpdecay(args[0]);
      case 'hpsustain':
      case 'hps':
        return c.hpsustain(args[0]);
      case 'hprelease':
      case 'hpr':
        return c.hprelease(args[0]);

      case 'bpattack':
      case 'bpa':
        return c.bpattack(args[0]);
      case 'bpdecay':
      case 'bpd':
        return c.bpdecay(args[0]);
      case 'bpsustain':
      case 'bps':
        return c.bpsustain(args[0]);
      case 'bprelease':
      case 'bpr':
        return c.bprelease(args[0]);

      case 'ftype':
        return c.ftype(args[0]);
      case 'fanchor':
        return c.fanchor(args[0]);

      // Filter LFOs
      case 'lprate':
        return c.lprate(args[0]);
      case 'lpsync':
        return c.lpsync(args[0]);
      case 'lpdepth':
        return c.lpdepth(args[0]);
      case 'lpdepthfreq':
      case 'lpdepthfrequency':
        return c.lpdepthfreq(args[0]);
      case 'lpshape':
        return c.lpshape(args[0]);
      case 'lpdc':
        return c.lpdc(args[0]);
      case 'lpskew':
        return c.lpskew(args[0]);

      case 'bprate':
        return c.bprate(args[0]);
      case 'bpsync':
        return c.bpsync(args[0]);
      case 'bpdepth':
        return c.bpdepth(args[0]);
      case 'bpdepthfreq':
      case 'bpdepthfrequency':
        return c.bpdepthfreq(args[0]);
      case 'bpshape':
        return c.bpshape(args[0]);
      case 'bpdc':
        return c.bpdc(args[0]);
      case 'bpskew':
        return c.bpskew(args[0]);

      case 'hprate':
        return c.hprate(args[0]);
      case 'hpsync':
        return c.hpsync(args[0]);
      case 'hpdepth':
        return c.hpdepth(args[0]);
      case 'euclid':
        if (args.length == 3) {
          return (args[2] as p.Pattern).euclid(args[0], args[1]);
        }
        return p.sequence(b.bjorklund(args[0], args[1]));
      default:
        throw Exception('Unknown function: $name');
    }
  }

  dynamic _invokeMethod(dynamic receiver, String name, List args) {
    if (receiver is! p.Pattern) {
      // If it's a literal, we can't call methods on it in this simple REPL
      // unless we promote it to a Pattern.
      receiver = p.reify(receiver);
    }

    final dynamic pattern = receiver;

    switch (name) {
      case 's':
      case 'sound':
        return (pattern as p.Pattern<c.ControlMap>).s(args[0]);
      case 'n':
        return (pattern as p.Pattern<c.ControlMap>).n(args[0]);
      case 'note':
        return (pattern as p.Pattern<c.ControlMap>).note(args[0]);
      case 'gain':
        return (pattern as p.Pattern<c.ControlMap>).gain(args[0]);
      case 'pan':
        return (pattern as p.Pattern<c.ControlMap>).pan(args[0]);
      case 'speed':
        return (pattern as p.Pattern<c.ControlMap>).speed(args[0]);
      case 'velocity':
        return (pattern as p.Pattern<c.ControlMap>).velocity(args[0]);
      case 'vowel':
        return (pattern as p.Pattern<c.ControlMap>).vowel(args[0]);
      case 'lpf':
        return (pattern as p.Pattern<c.ControlMap>).lpf(args[0]);
      case 'hpf':
        return (pattern as p.Pattern<c.ControlMap>).hpf(args[0]);
      case 'bank':
        return (pattern as p.Pattern<c.ControlMap>).bank(args[0]);
      case 'dec':
        return (pattern as p.Pattern<c.ControlMap>).dec(args[0]);
      case 'fast':
        return pattern.fast(args[0]);
      case 'slow':
        return pattern.slow(args[0]);
      case 'rev':
        return pattern.rev();
      case 'overlay':
        return (pattern as p.Pattern<c.ControlMap>).overlay(args[0]);
      case 'cat':
        return (pattern as p.Pattern<c.ControlMap>).cat(args);
      case 'attack':
        return (pattern as p.Pattern<c.ControlMap>).attack(args[0]);
      case 'decay':
        return (pattern as p.Pattern<c.ControlMap>).decay(args[0]);
      case 'sustain':
        return (pattern as p.Pattern<c.ControlMap>).sustain(args[0]);
      case 'release':
        return (pattern as p.Pattern<c.ControlMap>).release(args[0]);
      case 'lpq':
        return (pattern as p.Pattern<c.ControlMap>).lpq(args[0]);
      case 'hpq':
        return (pattern as p.Pattern<c.ControlMap>).hpq(args[0]);
      case 'bandf':
        return (pattern as p.Pattern<c.ControlMap>).bandf(args[0]);
      case 'bandq':
        return (pattern as p.Pattern<c.ControlMap>).bandq(args[0]);
      case 'room':
        return (pattern as p.Pattern<c.ControlMap>).room(args[0]);
      case 'size':
        return (pattern as p.Pattern<c.ControlMap>).size(args[0]);
      case 'dry':
        return (pattern as p.Pattern<c.ControlMap>).dry(args[0]);
      case 'delay':
        return (pattern as p.Pattern<c.ControlMap>).delay(args[0]);
      case 'delaytime':
        return (pattern as p.Pattern<c.ControlMap>).delaytime(args[0]);
      case 'delayfeedback':
        return (pattern as p.Pattern<c.ControlMap>).delayfeedback(args[0]);
      case 'crush':
        return (pattern as p.Pattern<c.ControlMap>).crush(args[0]);
      case 'coarse':
        return (pattern as p.Pattern<c.ControlMap>).coarse(args[0]);
      case 'shape':
        return (pattern as p.Pattern<c.ControlMap>).shape(args[0]);
      case 'cutoff':
        return (pattern as p.Pattern<c.ControlMap>).cutoff(args[0]);
      case 'resonance':
        return (pattern as p.Pattern<c.ControlMap>).resonance(args[0]);

      // Wavetable
      case 'wt':
        return (pattern as p.Pattern<c.ControlMap>).wt(args[0]);
      case 'wtenv':
        return (pattern as p.Pattern<c.ControlMap>).wtenv(args[0]);
      case 'wtattack':
      case 'wtatt':
        return (pattern as p.Pattern<c.ControlMap>).wtattack(args[0]);
      case 'wtdecay':
      case 'wtdec':
        return (pattern as p.Pattern<c.ControlMap>).wtdecay(args[0]);
      case 'wtsustain':
      case 'wtsus':
        return (pattern as p.Pattern<c.ControlMap>).wtsustain(args[0]);
      case 'wtrelease':
      case 'wtrel':
        return (pattern as p.Pattern<c.ControlMap>).wtrelease(args[0]);
      case 'wtrate':
        return (pattern as p.Pattern<c.ControlMap>).wtrate(args[0]);
      case 'wtsync':
        return (pattern as p.Pattern<c.ControlMap>).wtsync(args[0]);
      case 'wtdepth':
        return (pattern as p.Pattern<c.ControlMap>).wtdepth(args[0]);
      case 'wtshape':
        return (pattern as p.Pattern<c.ControlMap>).wtshape(args[0]);
      case 'wtdc':
        return (pattern as p.Pattern<c.ControlMap>).wtdc(args[0]);
      case 'wtskew':
        return (pattern as p.Pattern<c.ControlMap>).wtskew(args[0]);
      case 'wtphaserand':
        return (pattern as p.Pattern<c.ControlMap>).wtphaserand(args[0]);

      // Warp
      case 'warp':
        return (pattern as p.Pattern<c.ControlMap>).warp(args[0]);
      case 'warpenv':
        return (pattern as p.Pattern<c.ControlMap>).warpenv(args[0]);
      case 'warpattack':
      case 'warpatt':
        return (pattern as p.Pattern<c.ControlMap>).warpattack(args[0]);
      case 'warpdecay':
      case 'warpdec':
        return (pattern as p.Pattern<c.ControlMap>).warpdecay(args[0]);
      case 'warpsustain':
      case 'warpsus':
        return (pattern as p.Pattern<c.ControlMap>).warpsustain(args[0]);
      case 'warprelease':
      case 'warprel':
        return (pattern as p.Pattern<c.ControlMap>).warprelease(args[0]);
      case 'warprate':
        return (pattern as p.Pattern<c.ControlMap>).warprate(args[0]);
      case 'warpsync':
        return (pattern as p.Pattern<c.ControlMap>).warpsync(args[0]);
      case 'warpdepth':
        return (pattern as p.Pattern<c.ControlMap>).warpdepth(args[0]);
      case 'warpshape':
        return (pattern as p.Pattern<c.ControlMap>).warpshape(args[0]);
      case 'warpdc':
        return (pattern as p.Pattern<c.ControlMap>).warpdc(args[0]);
      case 'warpskew':
        return (pattern as p.Pattern<c.ControlMap>).warpskew(args[0]);
      case 'warpmode':
        return (pattern as p.Pattern<c.ControlMap>).warpmode(args[0]);

      // Source/Gain
      case 'source':
      case 'src':
        return (pattern as p.Pattern<c.ControlMap>).source(args[0]);
      case 'accelerate':
        return (pattern as p.Pattern<c.ControlMap>).accelerate(args[0]);
      case 'postgain':
        return (pattern as p.Pattern<c.ControlMap>).postgain(args[0]);
      case 'amp':
        return (pattern as p.Pattern<c.ControlMap>).amp(args[0]);

      // FM
      case 'fmh':
        return (pattern as p.Pattern<c.ControlMap>).fmh(args[0]);
      case 'fmi':
      case 'fm':
        return (pattern as p.Pattern<c.ControlMap>).fmi(args[0]);
      case 'fmenv':
        return (pattern as p.Pattern<c.ControlMap>).fmenv(args[0]);
      case 'fmattack':
      case 'fmatt':
        return (pattern as p.Pattern<c.ControlMap>).fmattack(args[0]);
      case 'fmdecay':
      case 'fmdec':
        return (pattern as p.Pattern<c.ControlMap>).fmdecay(args[0]);
      case 'fmsustain':
      case 'fmsus':
        return (pattern as p.Pattern<c.ControlMap>).fmsustain(args[0]);
      case 'fmrelease':
      case 'fmrel':
        return (pattern as p.Pattern<c.ControlMap>).fmrelease(args[0]);
      case 'fmwave':
        return (pattern as p.Pattern<c.ControlMap>).fmwave(args[0]);

      // Effects
      case 'chorus':
        return (pattern as p.Pattern<c.ControlMap>).chorus(args[0]);
      case 'analyze':
        return (pattern as p.Pattern<c.ControlMap>).analyze(args[0]);
      case 'fft':
        return (pattern as p.Pattern<c.ControlMap>).fft(args[0]);
      case 'hold':
        return (pattern as p.Pattern<c.ControlMap>).hold(args[0]);
      case 'drive':
        return (pattern as p.Pattern<c.ControlMap>).drive(args[0]);

      // Sample Playback
      case 'begin':
        return (pattern as p.Pattern<c.ControlMap>).begin(args[0]);
      case 'end':
        return (pattern as p.Pattern<c.ControlMap>).end(args[0]);
      case 'loop':
        return (pattern as p.Pattern<c.ControlMap>).loop(args[0]);
      case 'loopBegin':
      case 'loopb':
        return (pattern as p.Pattern<c.ControlMap>).loopBegin(args[0]);
      case 'loopEnd':
      case 'loope':
        return (pattern as p.Pattern<c.ControlMap>).loopEnd(args[0]);
      case 'cut':
        return (pattern as p.Pattern<c.ControlMap>).cut(args[0]);

      // Tremolo
      case 'tremolo':
      case 'trem':
        return (pattern as p.Pattern<c.ControlMap>).tremolo(args[0]);
      case 'tremolosync':
      case 'tremsync':
        return (pattern as p.Pattern<c.ControlMap>).tremolosync(args[0]);
      case 'tremolodepth':
      case 'tremdepth':
        return (pattern as p.Pattern<c.ControlMap>).tremolodepth(args[0]);
      case 'tremoloskew':
      case 'tremskew':
        return (pattern as p.Pattern<c.ControlMap>).tremoloskew(args[0]);
      case 'tremolophase':
      case 'tremphase':
        return (pattern as p.Pattern<c.ControlMap>).tremolophase(args[0]);
      case 'tremoloshape':
      case 'tremshape':
        return (pattern as p.Pattern<c.ControlMap>).tremoloshape(args[0]);

      // Ducking
      case 'duck':
      case 'duckorbit':
        return (pattern as p.Pattern<c.ControlMap>).duck(args[0]);
      case 'duckdepth':
        return (pattern as p.Pattern<c.ControlMap>).duckdepth(args[0]);
      case 'duckonset':
      case 'duckons':
        return (pattern as p.Pattern<c.ControlMap>).duckonset(args[0]);
      case 'duckattack':
      case 'duckatt':
        return (pattern as p.Pattern<c.ControlMap>).duckattack(args[0]);

      // ByteBeat
      case 'byteBeatExpression':
      case 'bbexpr':
        return (pattern as p.Pattern<c.ControlMap>).byteBeatExpression(args[0]);
      case 'byteBeatStartTime':
      case 'bbst':
        return (pattern as p.Pattern<c.ControlMap>).byteBeatStartTime(args[0]);

      // Channels
      case 'channels':
      case 'ch':
        return (pattern as p.Pattern<c.ControlMap>).channels(args[0]);

      // PulseWidth
      case 'pw':
        return (pattern as p.Pattern<c.ControlMap>).pw(args[0]);
      case 'pwrate':
        return (pattern as p.Pattern<c.ControlMap>).pwrate(args[0]);
      case 'pwsweep':
        return (pattern as p.Pattern<c.ControlMap>).pwsweep(args[0]);

      // Phaser
      case 'phaser':
      case 'ph':
        return (pattern as p.Pattern<c.ControlMap>).phaser(args[0]);
      case 'phasersweep':
      case 'phs':
        return (pattern as p.Pattern<c.ControlMap>).phasersweep(args[0]);
      case 'phasercenter':
      case 'phc':
        return (pattern as p.Pattern<c.ControlMap>).phasercenter(args[0]);
      case 'phaserdepth':
      case 'phd':
        return (pattern as p.Pattern<c.ControlMap>).phaserdepth(args[0]);

      // Filter ADSR + Envelopes
      case 'lpenv':
      case 'lpe':
        return (pattern as p.Pattern<c.ControlMap>).lpenv(args[0]);
      case 'hpenv':
      case 'hpe':
        return (pattern as p.Pattern<c.ControlMap>).hpenv(args[0]);
      case 'bpenv':
      case 'bpe':
        return (pattern as p.Pattern<c.ControlMap>).bpenv(args[0]);

      case 'lpattack':
      case 'lpa':
        return (pattern as p.Pattern<c.ControlMap>).lpattack(args[0]);
      case 'lpdecay':
      case 'lpd':
        return (pattern as p.Pattern<c.ControlMap>).lpdecay(args[0]);
      case 'lpsustain':
      case 'lps':
        return (pattern as p.Pattern<c.ControlMap>).lpsustain(args[0]);
      case 'lprelease':
      case 'lpr':
        return (pattern as p.Pattern<c.ControlMap>).lprelease(args[0]);

      case 'hpattack':
      case 'hpa':
        return (pattern as p.Pattern<c.ControlMap>).hpattack(args[0]);
      case 'hpdecay':
      case 'hpd':
        return (pattern as p.Pattern<c.ControlMap>).hpdecay(args[0]);
      case 'hpsustain':
      case 'hps':
        return (pattern as p.Pattern<c.ControlMap>).hpsustain(args[0]);
      case 'hprelease':
      case 'hpr':
        return (pattern as p.Pattern<c.ControlMap>).hprelease(args[0]);

      case 'bpattack':
      case 'bpa':
        return (pattern as p.Pattern<c.ControlMap>).bpattack(args[0]);
      case 'bpdecay':
      case 'bpd':
        return (pattern as p.Pattern<c.ControlMap>).bpdecay(args[0]);
      case 'bpsustain':
      case 'bps':
        return (pattern as p.Pattern<c.ControlMap>).bpsustain(args[0]);
      case 'bprelease':
      case 'bpr':
        return (pattern as p.Pattern<c.ControlMap>).bprelease(args[0]);

      case 'ftype':
        return (pattern as p.Pattern<c.ControlMap>).ftype(args[0]);
      case 'fanchor':
        return (pattern as p.Pattern<c.ControlMap>).fanchor(args[0]);

      // Filter LFOs
      case 'lprate':
        return (pattern as p.Pattern<c.ControlMap>).lprate(args[0]);
      case 'lpsync':
        return (pattern as p.Pattern<c.ControlMap>).lpsync(args[0]);
      case 'lpdepth':
        return (pattern as p.Pattern<c.ControlMap>).lpdepth(args[0]);
      case 'lpdepthfreq':
      case 'lpdepthfrequency':
        return (pattern as p.Pattern<c.ControlMap>).lpdepthfreq(args[0]);
      case 'lpshape':
        return (pattern as p.Pattern<c.ControlMap>).lpshape(args[0]);
      case 'lpdc':
        return (pattern as p.Pattern<c.ControlMap>).lpdc(args[0]);
      case 'lpskew':
        return (pattern as p.Pattern<c.ControlMap>).lpskew(args[0]);

      case 'bprate':
        return (pattern as p.Pattern<c.ControlMap>).bprate(args[0]);
      case 'bpsync':
        return (pattern as p.Pattern<c.ControlMap>).bpsync(args[0]);
      case 'bpdepth':
        return (pattern as p.Pattern<c.ControlMap>).bpdepth(args[0]);
      case 'bpdepthfreq':
      case 'bpdepthfrequency':
        return (pattern as p.Pattern<c.ControlMap>).bpdepthfreq(args[0]);
      case 'bpshape':
        return (pattern as p.Pattern<c.ControlMap>).bpshape(args[0]);
      case 'bpdc':
        return (pattern as p.Pattern<c.ControlMap>).bpdc(args[0]);
      case 'bpskew':
        return (pattern as p.Pattern<c.ControlMap>).bpskew(args[0]);

      case 'hprate':
        return (pattern as p.Pattern<c.ControlMap>).hprate(args[0]);
      case 'hpsync':
        return (pattern as p.Pattern<c.ControlMap>).hpsync(args[0]);
      case 'hpdepth':
        return (pattern as p.Pattern<c.ControlMap>).hpdepth(args[0]);
      case 'every':
        return (pattern as p.Pattern<c.ControlMap>).every(
          args[0] as int,
          (x) => (args[1] as Function)(x) as p.Pattern<c.ControlMap>,
        );
      case 'degradeBy':
        return pattern.degradeBy((args[0] as num).toDouble());
      case 'jux':
        // args[0] is function
        return (pattern as p.Pattern<c.ControlMap>).jux(
          (x) => (args[0] as Function)(x) as p.Pattern<c.ControlMap>,
        );
      case 'add':
        return (pattern as p.Pattern<dynamic>).add(args[0]);
      case 'sub':
        return (pattern as p.Pattern<dynamic>).sub(args[0]);
      case 'mul':
        return (pattern as p.Pattern<dynamic>).mul(args[0]);
      case 'div':
        return (pattern as p.Pattern<dynamic>).div(args[0]);
      case 'mod':
        return (pattern as p.Pattern<dynamic>).mod(args[0]);

      case 'struct':
        return pattern.struct(args[0] as p.Pattern);
      case 'mask':
        return pattern.mask(args[0] as p.Pattern);
      case 'euclid':
        return pattern.euclid(args[0], args[1]);

      case 'layer':
        return (pattern as p.Pattern).layer(
          args
              .map(
                (a) =>
                    (x) => (a as Function)(x) as p.Pattern,
              )
              .toList(),
        );
      default:
        throw Exception('Unknown method: $name');
    }
  }
}
