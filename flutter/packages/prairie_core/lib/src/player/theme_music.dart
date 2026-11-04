import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/src/api/catalog_api.dart' show ThemeSongSet;
import 'package:prairie_core/src/api/theme_music_api.dart';
import 'package:prairie_core/src/platform/video_backend.dart';
import 'package:prairie_core/src/state/session_provider.dart';
import 'package:prairie_core/src/state/video_backend_provider.dart';

/// One theme's audio player. The production output plays through the TV's
/// media pipeline ([VideoBackendThemeOutput]); tests use a fake.
abstract class ThemeAudioOutput {
  /// Loads and starts the audio, silent when [setVolume] is supported.
  /// Throws when it can't play.
  Future<void> start();

  /// Whether [setVolume] changes anything; without it the theme plays at the
  /// TV's volume and isn't faded.
  bool get supportsVolume;
  Future<void> setVolume(double volume);

  /// Plays again from the start. Only original audio can: converted audio
  /// has no byte ranges.
  Future<void> replay();

  /// Fires once the audio plays to its end.
  Stream<void> get ended;

  /// Fires when the stream fails after [start].
  Stream<void> get failed;

  /// Stops for good, releasing the player (and the TV's decoder).
  Future<void> dispose();
}

typedef ThemeMusicGrantRequest = Future<ThemeMusicGrant> Function(String ownerId, String themeId);
typedef ThemeAudioOutputFactory = ThemeAudioOutput Function(ThemeMusicGrant grant);

/// Plays a title page's local theme music, after Apple TV's
/// `ThemeMusicController` and the web player: the first theme of the page's
/// set, faded in to a background level, kept playing across pages with the
/// same owner and theme (a series and its seasons and episodes), looped in
/// place when original or with a fresh grant when converted, and retried once
/// with a fresh grant after a failure. Themes are optional: a refused grant
/// or a failed stream only leaves the page silent.
class ThemeMusicController {
  ThemeMusicController({required this.grant, required this.makeOutput, this.fadeStep = const Duration(milliseconds: 80)});

  final ThemeMusicGrantRequest grant;
  final ThemeAudioOutputFactory makeOutput;

  /// Time between fade-in volume steps; zero in tests.
  final Duration fadeStep;

  /// Background level under the page, as on the web and Apple TV.
  static const themeVolume = 0.35;
  static const _fadeSteps = 12;

  ThemeAudioOutput? _output;
  final _subscriptions = <StreamSubscription<void>>[];
  Timer? _fade;

  /// Bumped by every load and stop; a callback or grant from an older one is
  /// ignored.
  int _generation = 0;
  String _owner = '';
  String _theme = '';
  bool _loop = false;
  bool _converted = false;
  bool _retried = false;

  /// The theme played to its end and nothing replays it: staying on (or
  /// returning to) a page of the same owner doesn't start it again.
  bool _finished = false;

  /// Whether a theme is loading or playing. For tests and diagnostics.
  bool get active => _owner.isNotEmpty && !_finished;

  /// Plays [selection]'s first theme, or stops when there is none.
  void select(ThemeSongSet? selection, {required bool loop}) {
    _loop = loop;
    final song = selection?.items.firstOrNull;
    if (selection == null || song == null) {
      unawaited(stop());
      return;
    }
    if (_owner == selection.ownerId && _theme == song.id) return;
    unawaited(_release());
    _generation++;
    _owner = selection.ownerId;
    _theme = song.id;
    _retried = false;
    _finished = false;
    _load();
  }

  /// Ends the theme at once and frees the player. Awaited before a video
  /// starts or the TV hands off to another app, so the single hardware
  /// decoder is free for it.
  Future<void> stop() async {
    _generation++;
    _owner = '';
    _theme = '';
    _finished = false;
    await _release();
  }

  Future<void> _release() async {
    _fade?.cancel();
    _fade = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final output = _output;
    _output = null;
    if (output != null) {
      try {
        await output.dispose();
      } catch (_) {}
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    final ThemeMusicGrant granted;
    try {
      granted = await grant(_owner, _theme);
    } catch (_) {
      return;
    }
    if (generation != _generation) return;
    await _release();
    if (generation != _generation) return;
    final output = makeOutput(granted);
    _output = output;
    _converted = granted.converted;
    _subscriptions
      ..add(output.ended.listen((_) => _onEnded(generation)))
      ..add(output.failed.listen((_) => _onFailed(generation)));
    try {
      await output.start();
    } catch (_) {
      _onFailed(generation);
      return;
    }
    if (generation != _generation || !output.supportsVolume) return;
    _fadeIn(output, generation);
  }

  void _fadeIn(ThemeAudioOutput output, int generation) {
    var step = 0;
    _fade?.cancel();
    _fade = Timer.periodic(fadeStep, (timer) {
      if (generation != _generation || !identical(output, _output)) {
        timer.cancel();
        return;
      }
      step++;
      unawaited(output.setVolume(themeVolume * step / _fadeSteps).catchError((Object _) {}));
      if (step >= _fadeSteps) timer.cancel();
    });
  }

  void _onEnded(int generation) {
    if (generation != _generation) return;
    if (_loop) {
      if (_converted) {
        // Converted audio can't seek back and its grant may have expired.
        unawaited(_release().then((_) {
          if (generation == _generation) _load();
        }));
      } else {
        unawaited(_output?.replay().catchError((Object _) => _onFailed(generation)));
      }
      return;
    }
    _finished = true;
    unawaited(_release());
  }

  void _onFailed(int generation) {
    if (generation != _generation) return;
    unawaited(_release().then((_) {
      if (generation != _generation || _retried) return;
      _retried = true;
      _load();
    }));
  }
}

/// A theme played through the TV's own media pipeline: a [VideoBackend]
/// whose surface is mounted 1x1 by [ThemeMusicSurface], because Tizen's
/// player sizes its plane from a laid-out surface before it prepares.
class VideoBackendThemeOutput implements ThemeAudioOutput {
  VideoBackendThemeOutput({required this.backend, required this.url, required this.surface});

  final VideoBackend backend;
  final String url;

  /// Where the player's surface is mounted while it plays.
  final ValueNotifier<Widget?> surface;

  Widget? _mounted;

  @override
  Future<void> start() async {
    backend.attach(url);
    final mounted = KeyedSubtree(key: ObjectKey(backend), child: backend.buildSurface());
    _mounted = mounted;
    surface.value = mounted;
    // Let the surface lay out before the player prepares.
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
    await backend.initialize();
    if (supportsVolume) await setVolume(0);
    await backend.play();
  }

  @override
  bool get supportsVolume => backend is VideoBackendVolume;

  @override
  Future<void> setVolume(double volume) async {
    final backend = this.backend;
    if (backend is VideoBackendVolume) await backend.setVolume(volume);
  }

  @override
  Future<void> replay() async {
    await backend.seekTo(Duration.zero);
    await backend.play();
  }

  @override
  Stream<void> get ended => backend.completedStream;

  @override
  Stream<void> get failed => backend.errorStream.map((_) {});

  @override
  Future<void> dispose() async {
    // Only this player's surface: the next theme may have mounted its own.
    if (_mounted != null && identical(surface.value, _mounted)) surface.value = null;
    _mounted = null;
    await backend.dispose();
  }
}

/// Where the playing theme's player surface is mounted; see
/// [ThemeMusicSurface].
final themeMusicSurfaceProvider = Provider<ValueNotifier<Widget?>>((ref) {
  final notifier = ValueNotifier<Widget?>(null);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// The app's one theme music player. Every route other than a title page
/// stops it (see `AppRoot`).
final themeMusicControllerProvider = Provider<ThemeMusicController>((ref) {
  final controller = ThemeMusicController(
    grant: (ownerId, themeId) {
      final session = ref.read(sessionProvider);
      if (session == null) return Future.error(StateError('Signed out'));
      return requestThemeMusic(ref.read(apiClientProvider), session, ownerId: ownerId, themeId: themeId);
    },
    makeOutput: (granted) => VideoBackendThemeOutput(
      backend: ref.read(videoBackendFactoryProvider)(),
      url: granted.url,
      surface: ref.read(themeMusicSurfaceProvider),
    ),
  );
  ref.onDispose(() => unawaited(controller.stop()));
  return controller;
});

/// The profile's theme music preferences on this TV, or null when this
/// server has no theme music for the viewer (or doesn't know the settings).
/// Settings invalidates it after a change.
final themeMusicPreferencesProvider = FutureProvider<ThemeMusicSettings?>((ref) async {
  final key = ref.watch(sessionProvider.select((s) => s == null ? null : (s.serverUrl, s.profileId)));
  if (key == null) return null;
  final client = ref.read(apiClientProvider);
  final session = ref.read(sessionProvider)!;
  final capability = await fetchThemeMusicCapability(client, session);
  if (!capability.available) return null;
  return fetchThemeMusicSettings(client, session);
});

/// Mounts the playing theme's player surface as a single pixel in the
/// bottom-right corner, under everything else in the app's [Stack].
class ThemeMusicSurface extends ConsumerWidget {
  const ThemeMusicSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<Widget?>(
      valueListenable: ref.watch(themeMusicSurfaceProvider),
      builder: (context, surface, _) => surface == null
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.bottomRight,
              child: IgnorePointer(child: ExcludeFocus(child: SizedBox(width: 1, height: 1, child: surface))),
            ),
    );
  }
}
