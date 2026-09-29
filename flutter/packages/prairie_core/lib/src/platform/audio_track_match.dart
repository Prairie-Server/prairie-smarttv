import '../models/watch_detail.dart';

/// One audio stream as a native player lists it.
typedef NativeAudioTrack = ({String language, int channels, int bitrate});

/// Maps the server's source audio ordinal onto a native player's track list.
///
/// When the player lists every source stream, the ordinal is the index. Some
/// players (Tizen videohole) omit streams they cannot decode, e.g. TrueHD, so
/// the ordinal lands on a later track: on a Blu-ray remux that picked a
/// commentary instead of the DD 5.1 main mix. Then [track] is matched by
/// channel count, then bitrate (within 10%, in kbps or bps), then language.
/// Returns null when no candidate has the right channel count.
int? matchNativeAudioTrack(
  List<NativeAudioTrack> native,
  int ordinal, {
  AudioTrackInfo? track,
  int sourceTrackCount = 0,
}) {
  if (native.isEmpty || ordinal < 0) return null;
  final complete = sourceTrackCount > 0 && native.length == sourceTrackCount;
  if (complete || track == null) return ordinal < native.length ? ordinal : null;

  final wantChannels = track.channels;
  final wantKbps = track.bitrateKbps;
  final wantLang = _lang2(track.language);
  int? best;
  var bestScore = -1;
  for (var i = 0; i < native.length; i++) {
    final t = native[i];
    if (wantChannels != null && t.channels > 0 && t.channels != wantChannels) continue;
    var score = 0;
    if (wantKbps != null && wantKbps > 0 && t.bitrate > 0) {
      final kbps = t.bitrate > 100000 ? t.bitrate / 1000 : t.bitrate.toDouble();
      if ((kbps - wantKbps).abs() <= wantKbps * 0.1) score += 2;
    }
    if (wantLang.isNotEmpty && _lang2(t.language) == wantLang) score += 1;
    if (score > bestScore) {
      best = i;
      bestScore = score;
    }
  }
  return best;
}

String _lang2(String? language) {
  final l = (language ?? '').trim().toLowerCase();
  return l.length >= 2 ? l.substring(0, 2) : l;
}
