enum ControlGateMode { off, warn, strict }

extension ControlGateModeLabel on ControlGateMode {
  String get label {
    switch (this) {
      case ControlGateMode.off:
        return 'Off';
      case ControlGateMode.warn:
        return 'Warn';
      case ControlGateMode.strict:
        return 'Strict';
    }
  }
}

class ControlSupportReport {
  const ControlSupportReport({
    required this.unsupported,
    required this.partial,
  });

  final Set<String> unsupported;
  final Set<String> partial;

  bool get hasUnsupported => unsupported.isNotEmpty;
  bool get hasPartial => partial.isNotEmpty;
}

class ControlSupportMatrix {
  static const Set<String> unsupportedControls = {
    'accelerate',
    'analyze',
    'bpdc',
    'bpdepth',
    'bpdepthfreq',
    'bprate',
    'bpshape',
    'bpskew',
    'bpsync',
    'byteBeatExpression',
    'byteBeatStartTime',
    'channels',
    'color',
    'dry',
    'duckattack',
    'duckdepth',
    'duckonset',
    'fmwave',
    'hold',
    'hpdepth',
    'hprate',
    'hpsync',
    'lpdc',
    'lpdepth',
    'lpdepthfreq',
    'lprate',
    'lpshape',
    'lpskew',
    'lpsync',
    'phasercenter',
    'pwrate',
    'pwsweep',
    'roomlp',
    'source',
    'tremolodepth',
    'tremolophase',
    'tremoloshape',
    'tremoloskew',
    'tremolosync',
    'vowel',
  };

  static const Set<String> partialControls = {
    'bandf',
    'clip',
    'compressor',
    'delay',
    'delayfeedback',
    'delaytime',
    'distort',
    'duck',
    'hpf',
    'lpf',
    'phaser',
    'phaserdepth',
    'phasersweep',
    'postgain',
    'room',
    'roomdim',
    'roomfade',
    'roomsize',
    'shape',
    'tremolo',
  };

  static ControlSupportReport evaluate(Map<dynamic, dynamic> controls) {
    final unsupported = <String>{};
    final partial = <String>{};

    for (final entry in controls.entries) {
      final keyRaw = entry.key;
      if (keyRaw is! String) continue;
      final key = keyRaw.trim();
      if (key.isEmpty || key.startsWith('_')) continue;

      if (unsupportedControls.contains(key)) {
        unsupported.add(key);
      }
      if (partialControls.contains(key)) {
        partial.add(key);
      }
    }

    return ControlSupportReport(unsupported: unsupported, partial: partial);
  }

  static String formatKeys(Iterable<String> keys) {
    final sorted = keys.toList()..sort();
    return sorted.join(', ');
  }
}
