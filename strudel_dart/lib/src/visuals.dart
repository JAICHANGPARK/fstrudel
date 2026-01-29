import 'pattern.dart';

typedef VisualRequestHandler = void Function(StrudelVisualRequest request);

class StrudelVisuals {
  static VisualRequestHandler? onVisualRequest;

  static void emit(
    String type,
    Pattern<dynamic> pattern, {
    Map<String, dynamic>? options,
    bool inline = false,
  }) {
    final handler = onVisualRequest;
    if (handler == null) return;
    handler(
      StrudelVisualRequest(
        type: type,
        pattern: pattern,
        options: options ?? const {},
        inline: inline,
      ),
    );
  }
}

class StrudelVisualRequest {
  final String type;
  final Pattern<dynamic> pattern;
  final Map<String, dynamic> options;
  final bool inline;

  const StrudelVisualRequest({
    required this.type,
    required this.pattern,
    this.options = const {},
    this.inline = false,
  });
}
