import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Section { playback, subtitles, server }

/// Mirrors the applicable parts of PlaybackSettingsScreen.tsx.
///
/// Player-backend preference (html5/native) isn't ported — Flutter has a
/// single native [VideoBackend] per platform, not a runtime choice between
/// a web `<video>` element and a native player. Subtitle appearance is
/// persisted and fed to `buildPlaybackStartRequest`'s codec flags where
/// applicable, but the appearance fields themselves (size/color/position)
/// have no visible effect until the player screen renders an actual
/// subtitle overlay (a known gap, see `player_screen.dart`'s doc comment) —
/// changing them here is safe to do now regardless of that.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.back});

  final Route back;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PerformanceMode _mode = defaultPerformanceMode;
  PlaybackSettings _settings = const PlaybackSettings();
  bool _loaded = false;
  _Section _section = _Section.playback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = SharedPreferencesAsync();
    final mode = await loadPerformanceMode(prefs);
    final settings = await loadPlaybackSettings(prefs);
    if (mounted) {
      setState(() {
        _mode = mode;
        _settings = settings;
        _loaded = true;
      });
    }
  }

  Future<void> _setMode(PerformanceMode mode) async {
    setState(() => _mode = mode);
    await savePerformanceMode(mode, SharedPreferencesAsync());
  }

  Future<void> _updateSettings(PlaybackSettings Function(PlaybackSettings) update) async {
    final next = update(_settings);
    setState(() => _settings = next);
    await savePlaybackSettings(next, SharedPreferencesAsync());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(widget.back);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings', style: TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(widget.back)),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      children: [
                        _SectionButton(label: 'Playback', selected: _section == _Section.playback, onTap: () => setState(() => _section = _Section.playback)),
                        _SectionButton(label: 'Subtitles', selected: _section == _Section.subtitles, onTap: () => setState(() => _section = _Section.subtitles)),
                        _SectionButton(label: 'Server', selected: _section == _Section.server, onTap: () => setState(() => _section = _Section.server)),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: switch (_section) {
                        _Section.playback => _playbackSection(),
                        _Section.subtitles => _subtitlesSection(),
                        _Section.server => _serverSection(session),
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _playbackSection() => [
    const Text('Performance mode', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 20)),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: [
        for (final mode in PerformanceMode.values)
          ChoiceChip(label: Text(_performanceLabel(mode)), selected: _mode == mode, onSelected: (_) => _setMode(mode)),
      ],
    ),
    const SizedBox(height: 32),
    const Text('Troubleshooting', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 20)),
    const SizedBox(height: 4),
    const Text('Only one of these should be on at a time — turning one on turns the other off.', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
    const SizedBox(height: 8),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Force direct play', style: TextStyle(color: PrairieColors.ink)),
      subtitle: const Text('Skip Prairie remux/transcode and stream the file as-is.', style: TextStyle(color: PrairieColors.muted)),
      value: _settings.forceDirectPlay,
      onChanged: (v) => _updateSettings((s) => s.copyWith(forceDirectPlay: v)),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Force transcode', style: TextStyle(color: PrairieColors.ink)),
      subtitle: const Text('Always ask Prairie to transcode, even if this TV could play it directly.', style: TextStyle(color: PrairieColors.muted)),
      value: _settings.forceTranscode,
      onChanged: (v) => _updateSettings((s) => s.copyWith(forceTranscode: v)),
    ),
    const SizedBox(height: 12),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Force AV1', style: TextStyle(color: PrairieColors.ink)),
      subtitle: const Text('Advertise AV1 support even if this TV usually reports otherwise.', style: TextStyle(color: PrairieColors.muted)),
      value: _settings.forceAv1,
      onChanged: (v) => _updateSettings((s) => s.copyWith(forceAv1: v)),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Disable AV1', style: TextStyle(color: PrairieColors.ink)),
      subtitle: const Text('Never advertise AV1 support, even if this TV claims it.', style: TextStyle(color: PrairieColors.muted)),
      value: _settings.disableAv1,
      onChanged: (v) => _updateSettings((s) => s.copyWith(disableAv1: v)),
    ),
  ];

  List<Widget> _subtitlesSection() {
    final appearance = _settings.subtitleAppearance;
    void updateAppearance(SubtitleAppearance Function(SubtitleAppearance) update) {
      _updateSettings((s) => s.copyWith(subtitleAppearance: update(appearance)));
    }

    return [
      const Text('Subtitle appearance', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 20)),
      const SizedBox(height: 4),
      const Text('Applied once subtitles are turned on for a title.', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
      const SizedBox(height: 16),
      const Text('Size', style: TextStyle(color: PrairieColors.muted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final size in SubtitleFontSize.values)
            ChoiceChip(label: Text(size.name), selected: appearance.fontSize == size, onSelected: (_) => updateAppearance((a) => a.copyWith(fontSize: size))),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Background', style: TextStyle(color: PrairieColors.muted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final style in SubtitleBackgroundStyle.values)
            ChoiceChip(label: Text(style.name), selected: appearance.backgroundStyle == style, onSelected: (_) => updateAppearance((a) => a.copyWith(backgroundStyle: style))),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Position', style: TextStyle(color: PrairieColors.muted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final position in SubtitlePosition.values)
            ChoiceChip(
              label: Text(subtitlePositionWire(position)),
              selected: appearance.position == position,
              onSelected: (_) => updateAppearance((a) => a.copyWith(position: position)),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Text color', style: TextStyle(color: PrairieColors.muted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final (hex, label) in subtitleColorChoices)
            ChoiceChip(
              label: Text(label),
              avatar: CircleAvatar(backgroundColor: Color(int.parse('FF${hex.substring(1)}', radix: 16))),
              selected: appearance.fontColor == hex,
              onSelected: (_) => updateAppearance((a) => a.copyWith(fontColor: hex)),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text('Background opacity: ${appearance.backgroundOpacity}%', style: const TextStyle(color: PrairieColors.muted)),
      Slider(
        value: appearance.backgroundOpacity.toDouble(),
        min: 0,
        max: 100,
        activeColor: PrairieColors.amber,
        onChanged: (v) => updateAppearance((a) => a.copyWith(backgroundOpacity: v.round())),
      ),
    ];
  }

  List<Widget> _serverSection(PrairieSession? session) => [
    if (session != null) Text(session.serverUrl, style: const TextStyle(color: PrairieColors.muted)),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () async {
        await ref.read(sessionProvider.notifier).clear();
        if (!context.mounted) return;
        ref.read(routeProvider.notifier).goServers();
      },
      icon: const Icon(Icons.swap_horiz),
      label: const Text('Switch server'),
    ),
  ];

  String _performanceLabel(PerformanceMode mode) => switch (mode) {
    PerformanceMode.auto => 'Auto',
    PerformanceMode.high => 'High quality',
    PerformanceMode.balanced => 'Balanced',
    PerformanceMode.low => 'Performance',
  };
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: PrairieColors.bgElevated,
      title: Text(label, style: TextStyle(color: selected ? PrairieColors.amber : PrairieColors.ink)),
      onTap: onTap,
    );
  }
}
