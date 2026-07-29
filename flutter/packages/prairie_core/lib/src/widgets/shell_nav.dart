import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ShellNav.tsx: brand mark, main tabs, and profile/settings/
/// disconnect actions across the top of every signed-in "shell" screen.
///
/// The overflow menu (profiles/settings/disconnect as a dropdown, closed on
/// Escape/outside-click) isn't ported 1:1 — these are plain icon buttons
/// instead, since the TS version's menu interaction model is mouse/keyboard
/// specific and needs its own D-pad-friendly design pass.
class ShellNav extends StatelessWidget implements PreferredSizeWidget {
  const ShellNav({
    super.key,
    required this.active,
    this.profileName,
    this.profileAvatarUrl,
    this.showLiveTv = false,
    required this.onNavigate,
    required this.onProfiles,
    required this.onSettings,
    required this.onDisconnect,
  });

  final ShellTab active;
  final String? profileName;
  final String? profileAvatarUrl;
  final bool showLiveTv;
  final ValueChanged<ShellTab> onNavigate;
  final VoidCallback onProfiles;
  final VoidCallback onSettings;
  final VoidCallback onDisconnect;

  static const _tabs = <(ShellTab, String, IconData)>[
    (ShellTab.home, 'Home', Icons.home_outlined),
    (ShellTab.libraries, 'Libraries', Icons.video_library_outlined),
    (ShellTab.collections, 'Collections', Icons.folder_open_outlined),
    (ShellTab.search, 'Search', Icons.search),
  ];

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final tabs = showLiveTv
        ? [..._tabs.sublist(0, 3), (ShellTab.livetv, 'Live TV', Icons.live_tv_outlined), _tabs[3]]
        : _tabs;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        // Mirrors `.shell-nav`: a translucent scrim bar with a hairline
        // bottom border, not a fully transparent header — it needs to stay
        // legible when a poster rail scrolls underneath it.
        decoration: BoxDecoration(
          color: const Color(0xFF0C1016).withValues(alpha: 0.72),
          border: Border(bottom: BorderSide(color: PrairieColors.ink.withValues(alpha: 0.08))),
        ),
        child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Row(
            children: [
              const SizedBox(width: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('packages/prairie_core/assets/images/prairie-mark.png', width: 40, height: 40, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              const Text('PRAIRIE', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2)),
              const SizedBox(width: 32),
              for (final (tab, label, icon) in tabs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _NavTab(label: label, icon: icon, active: tab == active, onPressed: () => onNavigate(tab)),
                ),
              const Spacer(),
              IconButton(
                icon: profileAvatarUrl != null
                    ? CircleAvatar(radius: 14, backgroundImage: NetworkImage(profileAvatarUrl!))
                    : const CircleAvatar(radius: 14, backgroundColor: PrairieColors.bgSoft, child: Icon(Icons.person, size: 16, color: PrairieColors.muted)),
                tooltip: profileName ?? 'Profiles',
                onPressed: onProfiles,
              ),
              IconButton(icon: const Icon(Icons.settings_outlined, color: PrairieColors.muted), tooltip: 'Settings', onPressed: onSettings),
              IconButton(icon: const Icon(Icons.logout, color: PrairieColors.muted), tooltip: 'Disconnect', onPressed: onDisconnect),
              const SizedBox(width: 16),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({required this.label, required this.icon, required this.active, required this.onPressed});

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // `active` (the current route's tab) and D-pad focus are two distinct
    // states that both need to read clearly at a glance: active uses a
    // solid amber fill, focus (which can land on any tab regardless of
    // which one is active) gets its own ring so it's never ambiguous which
    // tab a remote press will activate.
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: _focused ? Border.all(color: PrairieColors.ring, width: 2) : null,
        ),
        child: TextButton.icon(
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: widget.active ? PrairieColors.bg : PrairieColors.ink,
            backgroundColor: widget.active ? PrairieColors.amber : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(widget.icon, size: 18),
          label: Text(widget.label),
        ),
      ),
    );
  }
}
