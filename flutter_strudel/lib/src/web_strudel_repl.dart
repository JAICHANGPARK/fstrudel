import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class StrudelReplEmbed extends StatelessWidget {
  const StrudelReplEmbed({super.key, required this.code});

  final String code;

  static const String _viewType = 'strudel-repl-embed';
  static bool _registered = false;

  static void _ensureRegistered(String code) {
    if (_registered) return;
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container =
          web.document.createElement('div') as web.HTMLDivElement;
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.overflow = 'hidden';
      container.style.display = 'block';
      container.style.minHeight = '400px';

      final style =
          web.document.createElement('style') as web.HTMLStyleElement;
      style.textContent = '''
:root {
  --background: #0b0b0b;
  --foreground: #e6e2da;
}
strudel-editor {
  display: block;
  width: 100%;
  height: 100%;
}
.cm-editor {
  color: var(--foreground);
}
.cm-content {
  caret-color: var(--foreground);
}
.cm-gutters {
  background: transparent;
  color: #7d7b76;
  border-right: 1px solid #1f1f1f;
}
.strudel-toolbar {
  display: flex;
  gap: 8px;
  padding: 8px 0;
}
.strudel-btn {
  background: #1f1f1f;
  color: var(--foreground);
  border: 1px solid #333;
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
  font: 12px/1.2 sans-serif;
}
''';

      final toolbar =
          web.document.createElement('div') as web.HTMLDivElement;
      toolbar.className = 'strudel-toolbar';

      final playBtn =
          web.document.createElement('button') as web.HTMLButtonElement;
      playBtn.className = 'strudel-btn';
      playBtn.textContent = 'Play';

      final stopBtn =
          web.document.createElement('button') as web.HTMLButtonElement;
      stopBtn.className = 'strudel-btn';
      stopBtn.textContent = 'Stop';

      playBtn.addEventListener(
        'click',
        ((web.Event _) => web.document.dispatchEvent(
              web.Event('repl-evaluate'),
            )).toJS,
      );
      stopBtn.addEventListener(
        'click',
        ((web.Event _) => web.document.dispatchEvent(
              web.Event('repl-stop'),
            )).toJS,
      );

      toolbar.append(playBtn);
      toolbar.append(stopBtn);

      final script =
          web.document.createElement('script') as web.HTMLScriptElement;
      script.src = 'https://unpkg.com/@strudel/repl@1.2.6';
      script.type = 'module';

      final editor =
          web.document.createElement('strudel-editor') as web.HTMLElement;
      editor.setAttribute(
        'style',
        'display:block;width:100%;height:100%;min-height:360px;',
      );
      editor.setAttribute('code', code);

      container.append(style);
      container.append(script);
      container.append(toolbar);
      script.addEventListener(
        'load',
        ((web.Event _) => container.append(editor)).toJS,
      );
      web.window.customElements.whenDefined('strudel-editor');
      return container;
    });
    _registered = true;
  }

  @override
  Widget build(BuildContext context) {
    _ensureRegistered(code);
    return const HtmlElementView(viewType: _viewType);
  }
}
