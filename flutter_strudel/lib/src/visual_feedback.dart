import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:strudel_dart/strudel_dart.dart';

class StrudelVisualPanel extends StatelessWidget {
  const StrudelVisualPanel({super.key, required this.request});

  final StrudelVisualRequest? request;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: request == null
          ? const _EmptyVisualState()
          : _VisualContent(request: request!),
    );
  }
}

class _EmptyVisualState extends StatelessWidget {
  const _EmptyVisualState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'Run a pattern with .punchcard() or .pianoroll()',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _VisualContent extends StatelessWidget {
  const _VisualContent({required this.request});

  final StrudelVisualRequest request;

  @override
  Widget build(BuildContext context) {
    final type = request.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VisualHeader(type: type),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _visualBody(type, request),
          ),
        ),
      ],
    );
  }

  Widget _visualBody(String type, StrudelVisualRequest request) {
    switch (type) {
      case 'punchcard':
      case 'pianoroll':
        return _PatternTimelineView(type: type, request: request);
      default:
        return _UnsupportedVisual(type: type);
    }
  }
}

class _VisualHeader extends StatelessWidget {
  const _VisualHeader({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 11,
          letterSpacing: 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _UnsupportedVisual extends StatelessWidget {
  const _UnsupportedVisual({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        '$type is not supported in Flutter yet.',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PatternTimelineView extends StatelessWidget {
  const _PatternTimelineView({
    required this.type,
    required this.request,
  });

  final String type;
  final StrudelVisualRequest request;

  @override
  Widget build(BuildContext context) {
    final haps = request.pattern.onsetsOnly().queryArc(0, 1);
    final rows = _buildRows(haps, type, maxRows: 8);
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'No events in current cycle',
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    return CustomPaint(
      painter: _PatternTimelinePainter(
        rows: rows,
        colorScheme: Theme.of(context).colorScheme,
      ),
    );
  }
}

class _PatternTimelinePainter extends CustomPainter {
  _PatternTimelinePainter({
    required this.rows,
    required this.colorScheme,
  });

  final List<_VisualRow> rows;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final labelWidth = 72.0;
    final plotWidth = math.max(0, size.width - labelWidth);
    final rowHeight = size.height / rows.length;
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withOpacity(0.6)
      ..strokeWidth = 1;
    final rowPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 1; i < 4; i++) {
      final x = labelWidth + (plotWidth * (i / 4));
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final yTop = rowIndex * rowHeight;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: row.label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        maxLines: 1,
        ellipsis: '...',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelWidth - 8);
      labelPainter.paint(canvas, Offset(4, yTop + 2));

      for (final event in row.events) {
        final xStart = labelWidth + (plotWidth * event.start);
        final xEnd = labelWidth + (plotWidth * event.end);
        final width = math.max(2.0, xEnd - xStart);
        rowPaint.color = event.color;
        final rect = Rect.fromLTWH(
          xStart,
          yTop + rowHeight * 0.2,
          width,
          rowHeight * 0.6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          rowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PatternTimelinePainter oldDelegate) => true;
}

class _VisualRow {
  const _VisualRow({
    required this.label,
    required this.events,
  });

  final String label;
  final List<_VisualEvent> events;
}

class _VisualEvent {
  const _VisualEvent({
    required this.start,
    required this.end,
    required this.color,
  });

  final double start;
  final double end;
  final Color color;
}

List<_VisualRow> _buildRows(
  List<Hap<dynamic>> haps,
  String type, {
  required int maxRows,
}) {
  if (type == 'pianoroll') {
    return _buildPianorollRows(haps, maxRows: maxRows);
  }
  return _buildPunchcardRows(haps, maxRows: maxRows);
}

List<_VisualRow> _buildPunchcardRows(
  List<Hap<dynamic>> haps, {
  required int maxRows,
}) {
  final Map<String, List<Hap<dynamic>>> grouped = {};
  for (final hap in haps) {
    final label = _labelForHap(hap);
    if (label.isEmpty) continue;
    if (!grouped.containsKey(label) && grouped.length >= maxRows) {
      continue;
    }
    grouped.putIfAbsent(label, () => []).add(hap);
  }
  return grouped.entries.map((entry) {
    final color = _colorForKey(entry.key);
    final events = _eventsForHaps(entry.value, color: color);
    return _VisualRow(label: entry.key, events: events);
  }).toList();
}

List<_VisualRow> _buildPianorollRows(
  List<Hap<dynamic>> haps, {
  required int maxRows,
}) {
  final Map<int, List<Hap<dynamic>>> grouped = {};
  final List<Hap<dynamic>> other = [];
  for (final hap in haps) {
    final midi = _midiFromHap(hap);
    if (midi == null) {
      other.add(hap);
      continue;
    }
    grouped.putIfAbsent(midi, () => []).add(hap);
  }
  final midiKeys = grouped.keys.toList()
    ..sort((a, b) => b.compareTo(a));
  final rows = <_VisualRow>[];
  for (final midi in midiKeys) {
    if (rows.length >= maxRows) break;
    final label = midi2note(midi);
    final events = _eventsForHaps(
      grouped[midi] ?? const [],
      color: _colorForKey(label),
    );
    rows.add(_VisualRow(label: label, events: events));
  }
  if (rows.length < maxRows && other.isNotEmpty) {
    rows.add(
      _VisualRow(
        label: 'other',
        events: _eventsForHaps(other, color: _colorForKey('other')),
      ),
    );
  }
  return rows;
}

List<_VisualEvent> _eventsForHaps(
  List<Hap<dynamic>> haps, {
  required Color color,
}) {
  return haps.map((hap) {
    final span = hap.wholeOrPart();
    final start = span.begin.toDouble();
    final end = span.end.toDouble();
    final clampedStart = start.clamp(0.0, 1.0);
    final clampedEnd = end.clamp(clampedStart, 1.0);
    return _VisualEvent(
      start: clampedStart,
      end: clampedEnd,
      color: color,
    );
  }).toList();
}

String _labelForHap(Hap<dynamic> hap) {
  final value = hap.value;
  if (value is Map) {
    final sound = value['s'] ?? value['sound'];
    if (sound != null) return _truncateLabel(sound.toString());
    final note = value['note'] ?? value['n'] ?? value['freq'];
    if (note != null) return _truncateLabel(note.toString());
  }
  return _truncateLabel(value.toString());
}

String _truncateLabel(String value) {
  if (value.length <= 12) return value;
  return value.substring(0, 12);
}

int? _midiFromHap(Hap<dynamic> hap) {
  final value = hap.value;
  if (value is Map) {
    final freq = value['freq'];
    if (freq is num && freq > 0) {
      return freqToMidi(freq).round();
    }
    final note = value['note'] ?? value['n'];
    if (note is num) return note.toInt();
    if (note is String && isNote(note)) {
      return noteToMidi(note);
    }
  }
  if (value is num) return value.toInt();
  if (value is String && isNote(value)) {
    return noteToMidi(value);
  }
  return null;
}

Color _colorForKey(String key) {
  final colors = Colors.primaries;
  if (colors.isEmpty) return Colors.blue;
  final hash = key.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return colors[hash % colors.length].shade400;
}
