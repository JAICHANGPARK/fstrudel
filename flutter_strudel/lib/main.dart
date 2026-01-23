import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:strudel_dart/strudel_dart.dart';
import 'package:flutter_strudel/src/scheduler.dart';
import 'package:flutter_strudel/src/audio_engine.dart';
import 'package:flutter_strudel/src/web_draw_canvas_stub.dart'
    if (dart.library.js_interop) 'package:flutter_strudel/src/web_draw_canvas.dart';
import 'package:flutter_strudel/src/web_strudel_iframe_stub.dart'
    if (dart.library.js_interop) 'package:flutter_strudel/src/web_strudel_iframe.dart';

void main() {
  runApp(const StrudelApp());
}

class StrudelApp extends StatelessWidget {
  const StrudelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Strudel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
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
  late final StrudelREPL _repl;

  // For visualizing active sounds
  final ValueNotifier<Set<String>> _activeSoundsNotifier =
      ValueNotifier<Set<String>>({});
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
        _audioEngine.play(hap);

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
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Strudel'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
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
      appBar: AppBar(
        title: const Text('Flutter Strudel'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Code Editor
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.deepPurple.shade700),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 5,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  labelText: 'Strudel Expression',
                  labelStyle: TextStyle(color: Colors.deepPurple.shade200),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.deepPurple.shade800),
                  ),
                  child: const StrudelScopeCanvas(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!kIsWeb) ...[
              _buildAudioStatus(),
              const SizedBox(height: 12),
            ],

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
                        color: Colors.deepPurple.shade300,
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
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: canPlay
                      ? () async {
                          try {
                            if (kIsWeb) {
                              await _audioEngine.evalCode(_controller.text);
                              _log("Playing pattern (web)...");
                            } else {
                              final pattern = _repl.evaluate(_controller.text);
                              _scheduler.play(pattern);
                              _log("Playing pattern...");
                            }
                          } catch (e) {
                            _log("Error: $e");
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: SelectableText(e.toString()),
                              ),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
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
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
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
                        color: Colors.deepPurple.shade900,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.deepPurple.shade500),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.speed,
                            size: 16,
                            color: Colors.deepPurple.shade200,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'CPS: ${cps.toStringAsFixed(2)} | BPM: $bpm',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple.shade100,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _controller.clear();
                    _log("Editor cleared.");
                  },
                  child: const Text('Clear Editor'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                    });
                  },
                  child: const Text('Clear Logs'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Logs Area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
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
                          color: Colors.grey.shade300,
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

    return allSounds.map((sound) {
      final isActive = activeSounds.contains(sound);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? _getSoundColor(sound) : Colors.grey.shade800,
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
            color: isActive ? Colors.white : Colors.grey.shade600,
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
    if (_audioInitError != null) {
      return Row(
        children: [
          Icon(Icons.error, size: 16, color: Colors.red.shade300),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Audio init failed: $_audioInitError',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade300,
              ),
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
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.deepPurple.shade200,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading audio engine...',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.check_circle, size: 16, color: Colors.green.shade300),
        const SizedBox(width: 6),
        Text(
          'Audio ready',
          style: TextStyle(fontSize: 12, color: Colors.green.shade300),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final timer in _soundTimers.values) {
      timer.cancel();
    }
    _scheduler.dispose();
    _controller.dispose();
    _audioEngine.dispose();
    super.dispose();
  }
}
