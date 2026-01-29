import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class StrudelScopeCanvas extends StatelessWidget {
  const StrudelScopeCanvas({super.key});

  static const String _viewType = 'strudel-scope-canvas';
  static bool _registered = false;

  static void _ensureRegistered() {
    if (_registered) return;
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.pointerEvents = 'none';

      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      canvas.id = 'test-canvas';
      canvas.style.width = '100%';
      canvas.style.height = '100%';

      container.append(canvas);
      _resizeCanvas(canvas);
      web.window.requestAnimationFrame(
        ((num _) => _resizeCanvas(canvas)).toJS,
      );
      web.window.addEventListener(
        'resize',
        ((web.Event _) => _resizeCanvas(canvas)).toJS,
      );
      return container;
    });
    _registered = true;
  }

  static void _resizeCanvas(web.HTMLCanvasElement canvas) {
    final rect = canvas.getBoundingClientRect();
    final ratio = web.window.devicePixelRatio;
    canvas.width = (rect.width * ratio).round();
    canvas.height = (rect.height * ratio).round();
  }

  @override
  Widget build(BuildContext context) {
    _ensureRegistered();
    return const HtmlElementView(viewType: _viewType);
  }
}
