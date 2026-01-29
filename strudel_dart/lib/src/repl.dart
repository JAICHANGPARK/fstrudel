import 'dart:async';
import 'package:petitparser/petitparser.dart';
import 'controls.dart' as c;
import 'pattern.dart' as p;
import 'bjorklund.dart' as b;
import 'signal.dart' as s;
import 'pick.dart' as k;
import 'speak.dart' as sp;
import 'resources.dart';
import 'visuals.dart';
import 'logger.dart';

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
      ((letter() | char('_')) & (word() | char('_')).star()).flatten().trim();

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
      case 'samples':
        final sampleMap = args.isNotEmpty ? args[0] : '';
        final baseUrl =
            args.length > 1 && args[1] != null ? args[1].toString() : null;
        _fireAndForget(
          StrudelResources.onSamples?.call(
            sampleMap,
            baseUrl: baseUrl,
          ),
          'samples',
        );
        return p.silence;
      case 'tables':
        final source = args.isNotEmpty ? args[0] : '';
        final frameLen = args.length > 1 && args[1] is num
            ? (args[1] as num).toInt()
            : null;
        _fireAndForget(
          StrudelResources.onTables?.call(
            source,
            frameLen: frameLen,
          ),
          'tables',
        );
        return p.silence;
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
      case 'saw':
        return s.saw;
      case 'saw2':
        return s.saw2;
      case 'isaw':
        return s.isaw;
      case 'isaw2':
        return s.isaw2;
      case 'sine':
        return s.sine;
      case 'sine2':
        return s.sine2;
      case 'cosine':
        return s.cosine;
      case 'cosine2':
        return s.cosine2;
      case 'square':
        return s.square;
      case 'square2':
        return s.square2;
      case 'tri':
        return s.tri;
      case 'tri2':
        return s.tri2;
      case 'itri':
        return s.itri;
      case 'itri2':
        return s.itri2;
      case 'time':
        return s.time;
      case 'rand':
        return s.rand;
      case 'rand2':
        return s.rand2;
      case 'brand':
        return s.brand;
      case 'perlin':
        return s.perlin;
      case 'berlin':
        return s.berlin;
      case 'mousex':
      case 'mouseX':
        return s.mousex;
      case 'mousey':
      case 'mouseY':
        return s.mousey;
      case 'run':
        return s.run(args[0] as int);
      case 'irand':
        return s.irand(args[0]);
      case 'choose':
        return s.choose(args);
      case 'chooseIn':
        return s.chooseIn(args);
      case 'chooseCycles':
        return s.chooseCycles(args);
      case 'wchoose':
        return s.wchoose(args.cast<List<dynamic>>());
      case 'wchooseCycles':
        return s.wchooseCycles(args.cast<List<dynamic>>());
      case 'shuffle':
        return s.shuffle(args[0] as int, args[1] as p.Pattern);
      case 'scramble':
        return s.scramble(args[0] as int, args[1] as p.Pattern);
      case 'binary':
        return s.binary(args[0] as int);
      case 'binaryN':
        return s.binaryN(args[0] as int, args[1] as int);
      case 'binaryL':
        return s.binaryL(args[0] as int);
      case 'binaryNL':
        return s.binaryNL(args[0] as int, args[1] as int);
      case 'cyclesPer':
        return s.cyclesPer;
      case 'per':
      case 'perCycle':
        return s.per;
      case 'perx':
        return s.perx;
      case 'pick':
        return k.pick(args[0], args[1]);
      case 'pickmod':
        return k.pickmod(args[0], args[1] as p.Pattern);
      case 'pickF':
        return k.pickF(
          args[0],
          args[1] as List<Function>,
          args[2] as p.Pattern,
        );
      case 'pickmodF':
        return k.pickmodF(
          args[0],
          args[1] as List<Function>,
          args[2] as p.Pattern,
        );
      case 'pickOut':
        return k.pickOut(args[0], args[1] as p.Pattern);
      case 'pickmodOut':
        return k.pickmodOut(args[0], args[1] as p.Pattern);
      case 'pickRestart':
        return k.pickRestart(args[0], args[1] as p.Pattern);
      case 'pickmodRestart':
        return k.pickmodRestart(args[0], args[1] as p.Pattern);
      case 'pickReset':
        return k.pickReset(args[0], args[1] as p.Pattern);
      case 'pickmodReset':
        return k.pickmodReset(args[0], args[1] as p.Pattern);
      case 'inhabit':
      case 'pickSqueeze':
        return k.inhabit(args[0], args[1] as p.Pattern);
      case 'inhabitmod':
      case 'pickmodSqueeze':
        return k.inhabitmod(args[0], args[1] as p.Pattern);
      case 'squeeze':
        return k.squeeze(args[0] as p.Pattern, args[1] as List<dynamic>);
      case 'arpWith':
        return (args[1] as p.Pattern).arpWith(args[0] as Function);
      case 'arp':
        return (args[1] as p.Pattern).arp(args[0]);
      case 'stack':
        return p.stack(args);
      case 'sequence':
        return p.sequence(args);
      case 'morph':
        return p.morph(args[0], args[1], args[2]);
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
      case 'speak':
        return sp.speak(
          args.isNotEmpty ? args[0] : 'en',
          args.length > 1 ? args[1] : null,
          args.length > 2 ? args[2] as p.Pattern : p.silence,
        );
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
      case 'adsr':
        return c.adsr(args.length == 1 ? args[0] : args);
      case 'ad':
        return c.ad(args.length == 1 ? args[0] : args);
      case 'ds':
        return c.ds(args.length == 1 ? args[0] : args);
      case 'ar':
        return c.ar(args.length == 1 ? args[0] : args);
      case 'color':
        return c.color(args[0]);
      case 'hsl':
        return c.hsl(args[0], args[1], args[2]);
      case 'hsla':
        return c.hsla(args[0], args[1], args[2], args[3]);
      case 'partials':
        return c.partials(args[0]);
      case 'phases':
        return c.phases(args[0]);
      case 'soft':
        return c.soft(args[0]);
      case 'hard':
        return c.hard(args[0]);
      case 'cubic':
        return c.cubic(args[0]);
      case 'diode':
        return c.diode(args[0]);
      case 'asym':
        return c.asym(args[0]);
      case 'fold':
        return c.fold(args[0]);
      case 'sinefold':
        return c.sinefold(args[0]);
      case 'chebyshev':
        return c.chebyshev(args[0]);
      case 'worklet':
        return c.worklet(args[0] as String, args.sublist(1));

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
        throw Exception(_unsupportedMessage('function', name));
    }
  }

  dynamic _invokeMethod(dynamic receiver, String name, List args) {
    if (receiver is! p.Pattern) {
      // If it's a literal, promote it to a Pattern. Strings get mini-notation
      // parsing so chained methods like ".fast" work as in Strudel.
      if (receiver is String) {
        final parsed = c.reifyString(receiver);
        receiver = parsed is p.Pattern ? parsed : p.reify(parsed);
      } else {
        receiver = p.reify(receiver);
      }
    }

    final dynamic pattern = receiver;

    switch (name) {
      case '_scope':
      case 'scope':
      case '_punchcard':
      case 'punchcard':
      case '_pianoroll':
      case 'pianoroll':
      case '_spiral':
      case 'spiral':
      case '_pitchwheel':
      case 'pitchwheel':
      case '_spectrum':
      case 'spectrum':
      case '_markcss':
      case 'markcss':
        return _handleVisual(pattern, name, args);
      case 's':
      case 'sound':
        return (pattern as p.Pattern<c.ControlMap>).s(args[0]);
      case 'n':
        return (pattern as p.Pattern<c.ControlMap>).n(args[0]);
      case 'note':
        return (pattern as p.Pattern<c.ControlMap>).note(args[0]);
      case 'scale':
        return pattern.scale(args[0]);
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
      case 'speak':
        return sp.speak(
          args.isNotEmpty ? args[0] : 'en',
          args.length > 1 ? args[1] : null,
          pattern as p.Pattern,
        );
      case 'adsr':
        return (pattern as p.Pattern<c.ControlMap>)
            .adsr(args.length == 1 ? args[0] : args);
      case 'ad':
        return (pattern as p.Pattern<c.ControlMap>)
            .ad(args.length == 1 ? args[0] : args);
      case 'ds':
        return (pattern as p.Pattern<c.ControlMap>)
            .ds(args.length == 1 ? args[0] : args);
      case 'ar':
        return (pattern as p.Pattern<c.ControlMap>)
            .ar(args.length == 1 ? args[0] : args);
      case 'color':
        return (pattern as p.Pattern<c.ControlMap>).color(args[0]);
      case 'hsl':
        return (pattern as p.Pattern<c.ControlMap>).hsl(
          args[0],
          args[1],
          args[2],
        );
      case 'hsla':
        return (pattern as p.Pattern<c.ControlMap>).hsla(
          args[0],
          args[1],
          args[2],
          args[3],
        );
      case 'partials':
        return (pattern as p.Pattern<c.ControlMap>).partials(args[0]);
      case 'phases':
        return (pattern as p.Pattern<c.ControlMap>).phases(args[0]);
      case 'soft':
        return (pattern as p.Pattern<c.ControlMap>).soft(args[0]);
      case 'hard':
        return (pattern as p.Pattern<c.ControlMap>).hard(args[0]);
      case 'cubic':
        return (pattern as p.Pattern<c.ControlMap>).cubic(args[0]);
      case 'diode':
        return (pattern as p.Pattern<c.ControlMap>).diode(args[0]);
      case 'asym':
        return (pattern as p.Pattern<c.ControlMap>).asym(args[0]);
      case 'fold':
        return (pattern as p.Pattern<c.ControlMap>).fold(args[0]);
      case 'sinefold':
        return (pattern as p.Pattern<c.ControlMap>).sinefold(args[0]);
      case 'chebyshev':
        return (pattern as p.Pattern<c.ControlMap>).chebyshev(args[0]);
      case 'fast':
        return pattern.fast(args[0]);
      case 'slow':
        return pattern.slow(args[0]);
      case 'segment':
      case 'seg':
        return pattern.segment(args[0]);
      case 'chunk':
        return pattern.chunk(
          (args[0] as num).toInt(),
          args[1] as p.Pattern Function(p.Pattern),
        );
      case 'chunkBack':
        return pattern.chunkBack(
          (args[0] as num).toInt(),
          args[1] as p.Pattern Function(p.Pattern),
        );
      case 'fastChunk':
        return pattern.fastChunk(
          (args[0] as num).toInt(),
          args[1] as p.Pattern Function(p.Pattern),
        );
      case 'chunkInto':
        return pattern.chunkInto(
          (args[0] as num).toInt(),
          args[1] as p.Pattern Function(p.Pattern),
        );
      case 'chunkBackInto':
        return pattern.chunkBackInto(
          (args[0] as num).toInt(),
          args[1] as p.Pattern Function(p.Pattern),
        );
      case 'into':
        return pattern.into(args[0], args[1] as p.Pattern Function(p.Pattern));
      case 'bypass':
        return pattern.bypass(args[0]);
      case 'ribbon':
      case 'rib':
        return pattern.ribbon(args[0], args[1]);
      case 'reset':
        return pattern.reset(args[0]);
      case 'restart':
        return pattern.restart(args[0]);
      case 'resetAll':
        return pattern.resetAll(args[0]);
      case 'restartAll':
        return pattern.restartAll(args[0]);
      case 'structAll':
        return pattern.structAll(args[0]);
      case 'maskAll':
        return pattern.maskAll(args[0]);
      case 'collect':
        return pattern.collect();
      case 'arpWith':
        return pattern.arpWith(args[0] as Function);
      case 'arp':
        return pattern.arp(args[0]);
      case 'log':
        return pattern.log();
      case 'logValues':
        return pattern.logValues();
      case 'onTriggerTime':
        return pattern.onTriggerTime(args[0] as Function);
      case 'hush':
        return pattern.hush();
      case 'stepJoin':
        return pattern.stepJoin();
      case 'stepBind':
        return pattern.stepBind(args[0] as p.Pattern Function(dynamic));
      case 'range':
        return pattern.range(args[0], args[1]);
      case 'range2':
        return pattern.range2(args[0], args[1]);
      case 'toBipolar':
        return pattern.toBipolar();
      case 'fromBipolar':
        return pattern.fromBipolar();
      case 'round':
        return pattern.round();
      case 'floor':
        return pattern.floor();
      case 'ceil':
        return pattern.ceil();
      case 'log2':
        return pattern.log2();
      case 'band':
        return pattern.band(args[0]);
      case 'brshift':
        return pattern.brshift(args[0]);
      case 'shuffle':
        return s.shuffle(args[0] as int, pattern);
      case 'scramble':
        return s.scramble(args[0] as int, pattern);
      case 'pick':
        return k.pick(args[0], pattern);
      case 'pickmod':
        return k.pickmod(args[0], pattern);
      case 'pickF':
        return k.pickF(args[0], args[1] as List<Function>, pattern);
      case 'pickmodF':
        return k.pickmodF(args[0], args[1] as List<Function>, pattern);
      case 'pickOut':
        return k.pickOut(args[0], pattern);
      case 'pickmodOut':
        return k.pickmodOut(args[0], pattern);
      case 'pickRestart':
        return k.pickRestart(args[0], pattern);
      case 'pickmodRestart':
        return k.pickmodRestart(args[0], pattern);
      case 'pickReset':
        return k.pickReset(args[0], pattern);
      case 'pickmodReset':
        return k.pickmodReset(args[0], pattern);
      case 'inhabit':
      case 'pickSqueeze':
        return k.inhabit(args[0], pattern);
      case 'inhabitmod':
      case 'pickmodSqueeze':
        return k.inhabitmod(args[0], pattern);
      case 'squeeze':
        return k.squeeze(pattern, args[0] as List<dynamic>);
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
      case 'distort':
        return (pattern as p.Pattern<c.ControlMap>).distort(args[0]);
      case 'FX':
        return (pattern as p.Pattern<c.ControlMap>).FX(args);
      case 'worklet':
        return (pattern as p.Pattern<c.ControlMap>).worklet(
          args[0] as String,
          args.sublist(1),
        );
      case 'roomsize':
        return (pattern as p.Pattern<c.ControlMap>).roomsize(args[0]);
      case 'roomfade':
        return (pattern as p.Pattern<c.ControlMap>).roomfade(args[0]);
      case 'roomlp':
        return (pattern as p.Pattern<c.ControlMap>).roomlp(args[0]);
      case 'roomdim':
        return (pattern as p.Pattern<c.ControlMap>).roomdim(args[0]);
      case 'orbit':
        return (pattern as p.Pattern<c.ControlMap>).orbit(args[0]);
      case 'compressor':
        return (pattern as p.Pattern<c.ControlMap>).compressor(args[0]);
      case 'clip':
        return (pattern as p.Pattern<c.ControlMap>).clip(args[0]);

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
      case 'degrade':
        return s.degrade(pattern);
      case 'undegradeBy':
        return s.undegradeBy((args[0] as num).toDouble(), pattern);
      case 'undegrade':
        return s.undegrade(pattern);
      case 'seed':
        return s.seed((args[0] as num).toInt(), pattern);
      case 'sometimesBy':
        return s.sometimesBy(
          p.reify(args[0]),
          (x) => (args[1] as Function)(x) as p.Pattern,
          pattern,
        );
      case 'sometimes':
        return s.sometimes(
          (x) => (args[0] as Function)(x) as p.Pattern,
          pattern,
        );
      case 'someCyclesBy':
        return s.someCyclesBy(
          p.reify(args[0]),
          (x) => (args[1] as Function)(x) as p.Pattern,
          pattern,
        );
      case 'someCycles':
        return s.someCycles(
          (x) => (args[0] as Function)(x) as p.Pattern,
          pattern,
        );
      case 'often':
        return s.often((x) => (args[0] as Function)(x) as p.Pattern, pattern);
      case 'rarely':
        return s.rarely((x) => (args[0] as Function)(x) as p.Pattern, pattern);
      case 'almostNever':
        return s.almostNever(
          (x) => (args[0] as Function)(x) as p.Pattern,
          pattern,
        );
      case 'almostAlways':
        return s.almostAlways(
          (x) => (args[0] as Function)(x) as p.Pattern,
          pattern,
        );
      case 'never':
        return s.never((x) => (args[0] as Function)(x) as p.Pattern, pattern);
      case 'always':
        return s.always((x) => (args[0] as Function)(x) as p.Pattern, pattern);
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
      case 'pow':
        return (pattern as p.Pattern<dynamic>).pow(args[0]);
      case 'lt':
        return (pattern as p.Pattern<dynamic>).lt(args[0]);
      case 'gt':
        return (pattern as p.Pattern<dynamic>).gt(args[0]);
      case 'lte':
        return (pattern as p.Pattern<dynamic>).lte(args[0]);
      case 'gte':
        return (pattern as p.Pattern<dynamic>).gte(args[0]);
      case 'eq':
        return (pattern as p.Pattern<dynamic>).eq(args[0]);
      case 'eqt':
        return (pattern as p.Pattern<dynamic>).eqt(args[0]);
      case 'ne':
        return (pattern as p.Pattern<dynamic>).ne(args[0]);
      case 'net':
        return (pattern as p.Pattern<dynamic>).net(args[0]);
      case 'and':
        return (pattern as p.Pattern<dynamic>).and(args[0]);
      case 'or':
        return (pattern as p.Pattern<dynamic>).or(args[0]);
      case 'bor':
        return (pattern as p.Pattern<dynamic>).bor(args[0]);
      case 'bxor':
        return (pattern as p.Pattern<dynamic>).bxor(args[0]);
      case 'blshift':
        return (pattern as p.Pattern<dynamic>).blshift(args[0]);
      case 'keep':
        return (pattern as p.Pattern<dynamic>).keep(args[0]);
      case 'keepif':
        return (pattern as p.Pattern<dynamic>).keepif(args[0]);

      case 'struct':
        return pattern.struct(args[0] as p.Pattern);
      case 'mask':
        return pattern.mask(args[0] as p.Pattern);
      case 'euclid':
        return pattern.euclid(args[0], args[1]);
      case 'choose':
        return s.chooseWith(pattern, args);
      case 'choose2':
        return s.chooseWith(pattern.fromBipolar(), args);

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
        throw Exception(_unsupportedMessage('method', name));
    }
  }

  p.Pattern<dynamic> _handleVisual(
    dynamic pattern,
    String name,
    List args,
  ) {
    final type = name.startsWith('_') ? name.substring(1) : name;
    final castPattern = pattern as p.Pattern<dynamic>;
    StrudelVisuals.emit(
      type,
      castPattern,
      options: _visualOptions(args),
      inline: name.startsWith('_'),
    );
    return castPattern;
  }

  Map<String, dynamic> _visualOptions(List args) {
    if (args.isEmpty) return const {};
    final arg = args.first;
    if (arg is Map) {
      return Map<String, dynamic>.from(arg);
    }
    return const {};
  }
}

String _unsupportedMessage(String kind, String name) {
  return 'Unsupported $kind: $name. Not available in the Dart/Flutter port '
      'yet. See https://strudel.cc/ and strudel_dart/PORTING.md.';
}

void _fireAndForget(Future<void>? future, String origin) {
  if (future == null) return;
  unawaited(
    future.catchError((error) => errorLogger(error, origin: origin)),
  );
}
