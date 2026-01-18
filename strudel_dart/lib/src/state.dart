import 'timespan.dart';

class StrudelState {
  final TimeSpan span;
  final Map<String, dynamic> controls;

  StrudelState(this.span, {this.controls = const {}});

  StrudelState setSpan(TimeSpan newSpan) {
    return StrudelState(newSpan, controls: controls);
  }

  StrudelState withSpan(TimeSpan Function(TimeSpan) func) {
    return setSpan(func(span));
  }

  StrudelState setControls(Map<String, dynamic> newControls) {
    return StrudelState(span, controls: {...controls, ...newControls});
  }
}
