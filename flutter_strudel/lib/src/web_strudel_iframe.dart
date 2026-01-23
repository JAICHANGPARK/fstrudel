import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class StrudelIframeEmbed extends StatelessWidget {
  const StrudelIframeEmbed({super.key, required this.src});

  final String src;

  static const String _viewType = 'strudel-iframe-embed';
  static bool _registered = false;
  static String _src = 'https://strudel.cc/';

  static void _ensureRegistered(String src) {
    _src = src;
    if (_registered) {
      final iframe = web.document.getElementById('strudel-iframe');
      if (iframe is web.HTMLIFrameElement) {
        iframe.src = _src;
      }
      return;
    }
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container =
          web.document.createElement('div') as web.HTMLDivElement;
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.minHeight = '500px';
      container.style.overflow = 'hidden';

      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.id = 'strudel-iframe';
      iframe.src = _src;
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      iframe.style.border = '0';
      iframe.setAttribute('allow', 'autoplay');

      container.append(iframe);
      return container;
    });
    _registered = true;
  }

  @override
  Widget build(BuildContext context) {
    _ensureRegistered(src);
    return const HtmlElementView(viewType: _viewType);
  }
}
