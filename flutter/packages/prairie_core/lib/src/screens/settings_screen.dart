import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Section { servers, playback, display, subtitles, about }

/// Focus fill for settings rows/sidebar — noticeably darker than
/// [PrairieColors.amberDeep] (which is a fairly bright orange used elsewhere
/// as a border/accent color, not meant to fill a large area behind text) and
/// used without the amber glow shadow, which stacked with the fill to read
/// as "obnoxiously bright."
const _focusFill = Color(0xFF6C4D19);

/// Common ISO 639-2/B subtitle language codes for the preferred-language picker.
const _subtitleLanguageChoices = <(String code, String label)>[
  ('', 'Off / none'),
  ('eng', 'English'),
  ('spa', 'Spanish'),
  ('fra', 'French'),
  ('deu', 'German'),
  ('ita', 'Italian'),
  ('por', 'Portuguese'),
  ('jpn', 'Japanese'),
  ('kor', 'Korean'),
  ('chi', 'Chinese'),
  ('nld', 'Dutch'),
  ('pol', 'Polish'),
  ('rus', 'Russian'),
  ('swe', 'Swedish'),
  ('nor', 'Norwegian'),
  ('dan', 'Danish'),
  ('fin', 'Finnish'),
  ('ara', 'Arabic'),
  ('hin', 'Hindi'),
];

/// Mirrors the applicable parts of PlaybackSettingsScreen.tsx with Prairie
/// full-width settings rows (label + hint / amber value) rather than Material
/// SwitchListTiles alone.
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
  final _sidebarFocusNodes = {for (final s in _Section.values) s: FocusNode()};

  @override
  void dispose() {
    for (final node in _sidebarFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

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
        if (didPop) return;
        // First back press drops focus to the sidebar (on the current
        // section) rather than leaving the screen outright; only a second
        // press, from the sidebar itself, actually navigates away.
        final primary = FocusManager.instance.primaryFocus;
        final inSidebar = _sidebarFocusNodes.values.any((node) => identical(node, primary));
        if (!inSidebar) {
          _sidebarFocusNodes[_section]?.requestFocus();
          return;
        }
        ref.read(routeProvider.notifier).go(widget.back);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings', style: TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(widget.back)),
        ),
        body: !_loaded
            ? const Center(child: PrairieLoadingIndicator())
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      children: [
                        if (session != null)
                          _SectionButton(
                            label: 'Servers',
                            selected: _section == _Section.servers,
                            focusNode: _sidebarFocusNodes[_Section.servers],
                            onTap: () => setState(() => _section = _Section.servers),
                          ),
                        _SectionButton(
                          label: 'Playback',
                          selected: _section == _Section.playback,
                          focusNode: _sidebarFocusNodes[_Section.playback],
                          onTap: () => setState(() => _section = _Section.playback),
                        ),
                        _SectionButton(
                          label: 'Display',
                          selected: _section == _Section.display,
                          focusNode: _sidebarFocusNodes[_Section.display],
                          onTap: () => setState(() => _section = _Section.display),
                        ),
                        _SectionButton(
                          label: 'Subtitles',
                          selected: _section == _Section.subtitles,
                          focusNode: _sidebarFocusNodes[_Section.subtitles],
                          onTap: () => setState(() => _section = _Section.subtitles),
                        ),
                        _SectionButton(
                          label: 'About',
                          selected: _section == _Section.about,
                          focusNode: _sidebarFocusNodes[_Section.about],
                          onTap: () => setState(() => _section = _Section.about),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: switch (_section) {
                        _Section.servers => _serversSection(session),
                        _Section.playback => _playbackSection(),
                        _Section.display => _displaySection(),
                        _Section.subtitles => _subtitlesSection(),
                        _Section.about => _aboutSection(),
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _serversSection(PrairieSession? session) => [
    const Text('Servers', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 22)),
    const SizedBox(height: 8),
    const Text('Switch servers or scan the LAN for new ones.', style: TextStyle(color: PrairieColors.muted, fontSize: 13)),
    const SizedBox(height: 16),
    if (session != null)
      _SettingsRow(
        label: 'Connected',
        hint: session.serverUrl,
      ),
    const SizedBox(height: 10),
    _SettingsRow(
      label: 'Servers / Scan LAN',
      hint: 'Disconnect and discover Prairie servers on your network.',
      trailing: const Icon(Icons.radar, color: PrairieColors.amber, size: 20),
      onTap: () async {
        await ref.read(sessionProvider.notifier).clear();
        if (!context.mounted) return;
        ref.read(routeProvider.notifier).goServers();
      },
    ),
  ];

  List<Widget> _playbackSection() {
    final caps = ref.watch(tvCapabilitiesProvider);
    final playMethod = resolveForcedPlayMethod(_settings);
    return [
      const Text('Playback', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 22)),
      const SizedBox(height: 4),
      const Text('Only one of Force direct play / Force transcode should be on at a time.', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
      const SizedBox(height: 16),
      _SettingsToggleRow(
        label: 'Force direct play',
        hint: 'Ask Prairie for Direct Play only (clears Force transcode).',
        value: _settings.forceDirectPlay,
        onChanged: (v) => _updateSettings((s) => s.copyWith(forceDirectPlay: v, forceTranscode: v ? false : s.forceTranscode)),
      ),
      const SizedBox(height: 10),
      _SettingsToggleRow(
        label: 'Force transcode',
        hint: 'Ask Prairie to transcode (clears Force direct play).',
        value: _settings.forceTranscode,
        onChanged: (v) => _updateSettings((s) => s.copyWith(forceTranscode: v, forceDirectPlay: v ? false : s.forceDirectPlay)),
      ),
      const SizedBox(height: 10),
      _SettingsToggleRow(
        label: 'Advertise AV1 (override)',
        hint: 'Force-advertise av1 when the panel probe is wrong.',
        value: _settings.forceAv1,
        onChanged: (v) => _updateSettings((s) => s.copyWith(forceAv1: v, disableAv1: v ? false : s.disableAv1)),
      ),
      const SizedBox(height: 10),
      _SettingsToggleRow(
        label: 'Disable AV1',
        hint: 'Never advertise av1, even when the probe says yes.',
        value: _settings.disableAv1,
        onChanged: (v) => _updateSettings((s) => s.copyWith(disableAv1: v, forceAv1: v ? false : s.forceAv1)),
      ),
      const SizedBox(height: 24),
      const Text('Diagnostics', style: TextStyle(color: PrairieColors.amber, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      // Diagnostics must be focusable: InkWell with onTap: null used to be
      // skipped by focus traversal (_SettingsRow now always supplies a tap).
      _SettingsRow(label: 'Play method', value: _playMethodLabel(playMethod)),
      const SizedBox(height: 10),
      _SettingsRow(
        label: 'Video codecs',
        hint: _codecListLabel(caps.codecsVideo),
      ),
      const SizedBox(height: 10),
      _SettingsRow(
        label: 'Audio / display',
        hint: '${_codecListLabel(caps.codecsAudio)} · Max ${caps.maxResolution} · HDR ${caps.hdr ? 'Yes' : 'No'}',
      ),
    ];
  }

  String _playMethodLabel(String? method) => switch (method) {
    'direct' => 'Direct Play',
    'transcode' => 'Transcode',
    null || 'auto' => 'Automatic',
    final other => other,
  };

  String _codecListLabel(List<String> codecs) => codecs.isEmpty ? 'None' : codecs.map((c) => c.toUpperCase()).join(', ');

  List<Widget> _displaySection() => [
    const Text('Display', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 22)),
    const SizedBox(height: 8),
    Text(
      'Resolved: ${_performanceLabel(_mode)}. Lower tiers reduce focus scale, shadows, and animations.',
      style: const TextStyle(color: PrairieColors.muted, fontSize: 12),
    ),
    const SizedBox(height: 16),
    for (final mode in PerformanceMode.values) ...[
      _SettingsRow(
        label: _performanceLabel(mode),
        value: _mode == mode ? 'On' : null,
        isOn: _mode == mode,
        onTap: () => _setMode(mode),
      ),
      const SizedBox(height: 10),
    ],
  ];

  List<Widget> _subtitlesSection() {
    final appearance = _settings.subtitleAppearance;
    void updateAppearance(SubtitleAppearance Function(SubtitleAppearance) update) {
      _updateSettings((s) => s.copyWith(subtitleAppearance: update(appearance)));
    }

    final preferred = _settings.preferredSubtitleLanguage;
    String preferredLabel = preferred.isEmpty ? 'Off / none' : preferred;
    for (final (code, label) in _subtitleLanguageChoices) {
      if (code == preferred) {
        preferredLabel = label;
        break;
      }
    }

    return [
      const Text('Subtitles', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 22)),
      const SizedBox(height: 4),
      const Text('Applied once subtitles are turned on for a title.', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
      const SizedBox(height: 16),
      _SettingsRow(
        label: 'Preferred language',
        value: preferredLabel,
        onTap: () async {
          final choice = await showModalBottomSheet<String>(
            context: context,
            backgroundColor: PrairieColors.bgElevated,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (code, label) in _subtitleLanguageChoices)
                    ListTile(
                      title: Text(label, style: const TextStyle(color: PrairieColors.ink)),
                      trailing: preferred == code ? const Icon(Icons.check, color: PrairieColors.amber) : null,
                      onTap: () => Navigator.pop(context, code),
                    ),
                ],
              ),
            ),
          );
          if (choice != null) {
            await _updateSettings((s) => s.copyWith(preferredSubtitleLanguage: choice));
          }
        },
      ),
      const SizedBox(height: 24),
      const Text('Appearance', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 18)),
      const SizedBox(height: 12),
      _SettingsRow(
        label: 'Size',
        value: subtitleFontSizeLabel(appearance.fontSize),
        onTap: () async {
          final choice = await _pickEnum(SubtitleFontSize.values, appearance.fontSize, subtitleFontSizeLabel);
          if (choice != null) updateAppearance((a) => a.copyWith(fontSize: choice));
        },
      ),
      const SizedBox(height: 10),
      _SettingsRow(
        label: 'Background',
        value: subtitleBackgroundStyleLabel(appearance.backgroundStyle),
        onTap: () async {
          final choice = await _pickEnum(SubtitleBackgroundStyle.values, appearance.backgroundStyle, subtitleBackgroundStyleLabel);
          if (choice != null) updateAppearance((a) => a.copyWith(backgroundStyle: choice));
        },
      ),
      const SizedBox(height: 10),
      _SettingsRow(
        label: 'Position',
        value: subtitlePositionLabel(appearance.position),
        onTap: () async {
          final choice = await _pickEnum(SubtitlePosition.values, appearance.position, subtitlePositionLabel);
          if (choice != null) updateAppearance((a) => a.copyWith(position: choice));
        },
      ),
      const SizedBox(height: 10),
      Builder(
        builder: (context) {
          var colorLabel = appearance.fontColor;
          for (final (hex, label) in subtitleColorChoices) {
            if (hex == appearance.fontColor) {
              colorLabel = label;
              break;
            }
          }
          return _SettingsRow(
            label: 'Text color',
            value: colorLabel,
            onTap: () async {
              final choice = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: PrairieColors.bgElevated,
                builder: (context) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (hex, label) in subtitleColorChoices)
                        ListTile(
                          leading: CircleAvatar(backgroundColor: Color(int.parse('FF${hex.substring(1)}', radix: 16))),
                          title: Text(label, style: const TextStyle(color: PrairieColors.ink)),
                          trailing: appearance.fontColor == hex ? const Icon(Icons.check, color: PrairieColors.amber) : null,
                          onTap: () => Navigator.pop(context, hex),
                        ),
                    ],
                  ),
                ),
              );
              if (choice != null) updateAppearance((a) => a.copyWith(fontColor: choice));
            },
          );
        },
      ),
      const SizedBox(height: 10),
      _OpacitySettingsRow(
        label: 'Background opacity',
        hint: 'Left / Right to adjust (Up / Down keeps scrolling)',
        value: appearance.backgroundOpacity,
        onChanged: (v) => updateAppearance((a) => a.copyWith(backgroundOpacity: v)),
      ),
    ];
  }

  Future<T?> _pickEnum<T>(List<T> values, T current, String Function(T) label) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: PrairieColors.bgElevated,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final value in values)
              ListTile(
                title: Text(label(value), style: const TextStyle(color: PrairieColors.ink)),
                trailing: current == value ? const Icon(Icons.check, color: PrairieColors.amber) : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _aboutSection() {
    final identity = ref.watch(clientIdentityProvider);
    return [
      const Text('About', style: TextStyle(color: PrairieColors.ink, fontFamily: 'Fraunces', fontSize: 22)),
      const SizedBox(height: 16),
      _SettingsRow(label: 'Client', value: identity.deviceName),
      const SizedBox(height: 10),
      _SettingsRow(
        label: 'Play method',
        value: _playMethodLabel(resolveForcedPlayMethod(_settings)),
      ),
    ];
  }

  String _performanceLabel(PerformanceMode mode) => switch (mode) {
    PerformanceMode.auto => 'Auto',
    PerformanceMode.high => 'High quality',
    PerformanceMode.balanced => 'Balanced',
    PerformanceMode.low => 'Performance',
  };
}

/// Mirrors `.settings-row`: full-width prairie row with label/hint and optional amber value.
class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.label,
    this.hint,
    this.value,
    this.trailing,
    this.isOn = false,
    this.onTap,
  });

  final String label;
  final String? hint;
  final String? value;
  final Widget? trailing;
  final bool isOn;
  /// Null = read-only diagnostic row. Still focusable so D-pad can scroll here.
  final VoidCallback? onTap;

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final actionable = widget.onTap != null;
    return Material(
      // Solid (not washed-out) when focused — light ink text needs a genuinely
      // dark-orange fill behind it, not a pale amber tint, to stay readable.
      color: focused
          ? _focusFill
          : widget.isOn
              ? PrairieColors.amber.withValues(alpha: 0.14)
              : PrairieColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        // Always provide onTap so InkWell stays in the TV focus traversal order.
        onTap: widget.onTap ?? () {},
        borderRadius: BorderRadius.circular(14),
        onFocusChange: (value) => setState(() => _focused = value),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused
                  ? PrairieColors.ink.withValues(alpha: 0.85)
                  : widget.isOn
                      ? PrairieColors.amber.withValues(alpha: 0.4)
                      : PrairieColors.ink.withValues(alpha: 0.1),
              width: focused ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: PrairieColors.ink,
                        fontWeight: focused ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (widget.hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.hint!,
                        style: TextStyle(color: focused ? PrairieColors.ink.withValues(alpha: 0.85) : PrairieColors.muted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.value != null) ...[
                const SizedBox(width: 12),
                Text(
                  widget.value!,
                  // Focused text stays ink (white), not amber — amber-on-amber
                  // (the focus fill) was nearly unreadable.
                  style: TextStyle(
                    color: focused ? PrairieColors.ink : PrairieColors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (actionable) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: PrairieColors.muted.withValues(alpha: 0.7), size: 18),
                ],
              ] else if (widget.trailing != null)
                widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: label,
      hint: hint,
      value: value ? 'On' : 'Off',
      isOn: value,
      onTap: () => onChanged(!value),
    );
  }
}

/// Opacity control that only consumes Left/Right so Up/Down can scroll the list.
class _OpacitySettingsRow extends StatefulWidget {
  const _OpacitySettingsRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_OpacitySettingsRow> createState() => _OpacitySettingsRowState();
}

class _OpacitySettingsRowState extends State<_OpacitySettingsRow> {
  bool _focused = false;
  static const _step = 5;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onChanged((widget.value - _step).clamp(0, 100));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onChanged((widget.value + _step).clamp(0, 100));
      return KeyEventResult.handled;
    }
    // Up/Down intentionally ignored so focus traversal / list scroll continues.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: focused ? _focusFill : PrairieColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focused ? PrairieColors.ink.withValues(alpha: 0.85) : PrairieColors.ink.withValues(alpha: 0.1),
            width: focused ? 3 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: PrairieColors.ink,
                      fontWeight: focused ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.hint,
                    style: TextStyle(color: focused ? PrairieColors.ink.withValues(alpha: 0.85) : PrairieColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left,
              color: focused ? PrairieColors.ink : PrairieColors.muted,
            ),
            SizedBox(
              width: 56,
              child: Text(
                '${widget.value}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: focused ? PrairieColors.ink : PrairieColors.amber,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: focused ? PrairieColors.ink : PrairieColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionButton extends StatefulWidget {
  const _SectionButton({required this.label, required this.selected, required this.onTap, this.focusNode});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final selected = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: focused
            ? _focusFill
            : selected
                ? PrairieColors.amber.withValues(alpha: 0.14)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          onFocusChange: (value) => setState(() => _focused = value),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused
                    ? PrairieColors.ink.withValues(alpha: 0.85)
                    : selected
                        ? PrairieColors.amber.withValues(alpha: 0.45)
                        : Colors.transparent,
                width: focused ? 3 : 1,
              ),
            ),
            child: Text(
              widget.label,
              // Focused text stays high-contrast ink (white) — using amber
              // here nearly matched the amber focus wash/ring, making the
              // label hard to read. Amber is reserved for the unfocused
              // "selected section" indicator, which never overlaps focus.
              style: TextStyle(
                color: focused ? PrairieColors.ink : selected ? PrairieColors.amberBright : PrairieColors.ink,
                fontWeight: focused || selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
