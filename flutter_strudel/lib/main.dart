import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:strudel_dart/strudel_dart.dart';
import 'package:flutter_strudel/src/scheduler.dart';
import 'package:flutter_strudel/src/audio_engine.dart';
import 'package:flutter_strudel/src/control_support.dart';
import 'package:flutter_strudel/src/visual_feedback.dart';
import 'package:flutter_strudel/src/web_strudel_iframe_stub.dart'
    if (dart.library.js_interop) 'package:flutter_strudel/src/web_strudel_iframe.dart';

void main() {
  runApp(const StrudelApp());
}

class StrudelApp extends StatelessWidget {
  const StrudelApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
    );
    final colorScheme = baseScheme.copyWith(
      surface: const Color(0xFF0D1321),
      surfaceVariant: const Color(0xFF162033),
      outline: const Color(0xFF2A3B57),
      outlineVariant: const Color(0xFF1F2A40),
    );

    return MaterialApp(
      title: 'Flutter Strudel',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(color: colorScheme.primary.withOpacity(0.8)),
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: colorScheme.primary,
          selectionColor: colorScheme.primary.withOpacity(0.25),
          selectionHandleColor: colorScheme.primary,
        ),
        useMaterial3: true,
      ),
      home: const StrudelHome(),
    );
  }
}

class StrudelHome extends StatefulWidget {
  const StrudelHome({super.key});

  @override
  State<StrudelHome> createState() => _StrudelHomeState();
}

class _StrudelHomeState extends State<StrudelHome> {
  final StrudelScheduler _scheduler = StrudelScheduler();
  final AudioEngine _audioEngine = AudioEngine();
  final List<String> _logs = [];
  final TextEditingController _controller = TextEditingController(
    text: 's("bd sd [~ bd] sd, hh*16, misc")',
  );
  final ValueNotifier<double> _cpsNotifier = ValueNotifier<double>(0.5);
  final ValueNotifier<ControlGateMode> _controlGateNotifier =
      ValueNotifier<ControlGateMode>(ControlGateMode.warn);
  late final StrudelREPL _repl;

  // For visualizing active sounds
  final ValueNotifier<Set<String>> _activeSoundsNotifier =
      ValueNotifier<Set<String>>({});
  final ValueNotifier<StrudelVisualRequest?> _visualRequest =
      ValueNotifier<StrudelVisualRequest?>(null);
  final Map<String, Timer> _soundTimers = {};

  bool _audioReady = false;
  String? _audioInitError;

  DateTime _lastLogTime = DateTime.fromMillisecondsSinceEpoch(0);
  final List<String> _pendingLogs = [];

  void _log(String message) {
    if (mounted) {
      final time = DateTime.now()
          .toIso8601String()
          .split('T')[1]
          .substring(0, 8);
      final logEntry = '[$time] $message';

      _pendingLogs.add(logEntry);

      final now = DateTime.now();
      if (now.difference(_lastLogTime).inMilliseconds > 100 ||
          message.contains('Error') ||
          message.contains('Stop') ||
          message.contains('Playing')) {
        setState(() {
          _logs.insertAll(0, _pendingLogs.reversed);
          _pendingLogs.clear();
          if (_logs.length > 50) _logs.removeRange(50, _logs.length);
          _lastLogTime = now;
        });
      }
    }
  }

  void _activateSound(String sound) {
    // Cancel existing timer for this sound if any
    _soundTimers[sound]?.cancel();

    // Add sound to active set
    final current = Set<String>.from(_activeSoundsNotifier.value);
    current.add(sound);
    _activeSoundsNotifier.value = current;

    // Set timer to remove highlight after 150ms
    _soundTimers[sound] = Timer(const Duration(milliseconds: 150), () {
      final updated = Set<String>.from(_activeSoundsNotifier.value);
      updated.remove(sound);
      _activeSoundsNotifier.value = updated;
    });
  }

  @override
  void initState() {
    super.initState();

    _repl = StrudelREPL(
      onCpsChange: (newCps) {
        _cpsNotifier.value = newCps;
        _scheduler.setCps(newCps);
        _log("Tempo changed: CPS=${newCps.toStringAsFixed(2)}");
      },
    );
    StrudelVisuals.onVisualRequest = (request) {
      _visualRequest.value = request;
    };
    _audioEngine.setControlGateMode(_controlGateNotifier.value);

    _audioReady = kIsWeb;
    if (!kIsWeb) {
      print('MainUI: Initializing AudioEngine...');
      _audioEngine
          .init()
          .then((_) {
            print('MainUI: AudioEngine initialized.');
            if (mounted) {
              setState(() {
                _audioReady = true;
              });
            }
          })
          .catchError((e) {
            print('MainUI: AudioEngine initialization failed: $e');
            if (mounted) {
              setState(() {
                _audioInitError = e.toString();
              });
            }
          });
    }

    if (!kIsWeb) {
      _scheduler.haps.listen((hap) {
        print('MainUI: Event received: $hap');
        unawaited(
          _audioEngine.play(hap).catchError((error) {
            _log('Error: $error');
          }),
        );

        // Extract sound name for visualization
        if (hap.value is Map) {
          final sound = hap.value['s'] as String?;
          if (sound != null) {
            _activateSound(sound);
          }
        }

        _log('Event: $hap');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Flutter Strudel')),
        body: const Padding(
          padding: EdgeInsets.all(16.0),
          child: SizedBox.expand(
            child: StrudelIframeEmbed(src: 'https://strudel.cc/'),
          ),
        ),
      );
    }
    final canPlay = _audioReady && _audioInitError == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Strudel')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Code Editor
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 5,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: 'Strudel Expression',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ValueListenableBuilder<StrudelVisualRequest?>(
                valueListenable: _visualRequest,
                builder: (context, request, child) {
                  return StrudelVisualPanel(request: request);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (!kIsWeb) ...[_buildAudioStatus(), const SizedBox(height: 12)],

            // Active Sounds Visualizer
            ValueListenableBuilder<Set<String>>(
              valueListenable: _activeSoundsNotifier,
              builder: (context, activeSounds, child) {
                return Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.music_note,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _buildSoundChips(activeSounds),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Controls Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: canPlay
                        ? () async {
                            try {
                              if (kIsWeb) {
                                await _audioEngine.evalCode(_controller.text);
                                _log("Playing pattern (web)...");
                              } else {
                                final pattern = _repl.evaluate(
                                  _controller.text,
                                );
                                final visualRequest = _visualRequest.value;
                                if (visualRequest != null) {
                                  _visualRequest.value = StrudelVisualRequest(
                                    type: visualRequest.type,
                                    pattern: pattern,
                                    options: visualRequest.options,
                                    inline: visualRequest.inline,
                                  );
                                }
                                _scheduler.play(pattern);
                                _log("Playing pattern...");
                              }
                            } catch (e) {
                              _log("Error: $e");
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: SelectableText(e.toString())),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!kIsWeb) {
                        _scheduler.stop();
                      }
                      _audioEngine.stopAll();
                      _activeSoundsNotifier.value = {};
                      _log("Stopped.");
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ValueListenableBuilder<double>(
                    valueListenable: _cpsNotifier,
                    builder: (context, cps, child) {
                      final bpm = (cps * 240).round();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colorScheme.secondary),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.speed,
                              size: 16,
                              color: colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'CPS: ${cps.toStringAsFixed(2)} | BPM: $bpm',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  _buildControlGateSelector(),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _controller.clear();
                      _log("Editor cleared.");
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                    child: const Text('Clear Editor'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _logs.clear();
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                    ),
                    child: const Text('Clear Logs'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Logs Area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        _logs[index],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSoundChips(Set<String> activeSounds) {
    // Common sounds to always show (dim when inactive)
    const commonSounds = ['bd', 'sd', 'hh', 'oh', 'cp', 'rim', 'misc'];
    final allSounds = {...commonSounds, ...activeSounds};
    final colorScheme = Theme.of(context).colorScheme;

    return allSounds.map((sound) {
      final isActive = activeSounds.contains(sound);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? _getSoundColor(sound) : colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: _getSoundColor(sound).withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          sound,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }).toList();
  }

  Color _getSoundColor(String sound) {
    switch (sound) {
      case 'bd':
      case 'kick':
        return Colors.red.shade600;
      case 'sd':
        return Colors.orange.shade600;
      case 'hh':
        return Colors.cyan.shade600;
      case 'oh':
        return Colors.teal.shade600;
      case 'cp':
        return Colors.pink.shade600;
      case 'rim':
        return Colors.amber.shade600;
      case 'cr':
      case 'rd':
        return Colors.yellow.shade700;
      case 'ht':
      case 'mt':
      case 'lt':
        return Colors.brown.shade400;
      case 'misc':
        return Colors.purple.shade600;
      default:
        return Colors.deepPurple.shade400;
    }
  }

  Widget _buildAudioStatus() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_audioInitError != null) {
      return Row(
        children: [
          Icon(Icons.error, size: 16, color: colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Audio init failed: $_audioInitError',
              style: TextStyle(fontSize: 12, color: colorScheme.error),
            ),
          ),
        ],
      );
    }
    if (!_audioReady) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading audio engine...',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.check_circle, size: 16, color: colorScheme.tertiary),
        const SizedBox(width: 6),
        Text(
          'Audio ready',
          style: TextStyle(fontSize: 12, color: colorScheme.tertiary),
        ),
      ],
    );
  }

  Widget _buildControlGateSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<ControlGateMode>(
      valueListenable: _controlGateNotifier,
      builder: (context, mode, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rule, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<ControlGateMode>(
                  value: mode,
                  isDense: true,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                  dropdownColor: colorScheme.surfaceVariant,
                  iconEnabledColor: colorScheme.onSurfaceVariant,
                  onChanged: (nextMode) {
                    if (nextMode == null) return;
                    _controlGateNotifier.value = nextMode;
                    _audioEngine.setControlGateMode(nextMode);
                    _log('Control gate: ${nextMode.label}');
                  },
                  items: ControlGateMode.values.map((gateMode) {
                    return DropdownMenuItem<ControlGateMode>(
                      value: gateMode,
                      child: Text('Gate ${gateMode.label}'),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    for (final timer in _soundTimers.values) {
      timer.cancel();
    }
    StrudelVisuals.onVisualRequest = null;
    _visualRequest.dispose();
    _controlGateNotifier.dispose();
    _scheduler.dispose();
    _controller.dispose();
    _audioEngine.dispose();
    super.dispose();
  }
}
