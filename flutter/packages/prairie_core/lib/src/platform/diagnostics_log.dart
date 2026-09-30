/// The last few player diagnostic events, kept on-device for the stats
/// overlay.
///
/// The server strips query strings from its request log, so the `dbg=` beacon
/// payload is never visible there. Keeping the events locally lets "stats for
/// nerds" show the native player's own story (init, errors, track selection,
/// seek failures) on the TV itself.
class DiagnosticsLog {
  DiagnosticsLog({this.capacity = 10, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int capacity;
  final DateTime Function() _clock;
  final List<String> _events = [];

  void add(String event) {
    final t = _clock();
    final stamp = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    _events.add('$stamp $event');
    if (_events.length > capacity) _events.removeAt(0);
  }

  /// Oldest first.
  List<String> get events => List.unmodifiable(_events);
}
