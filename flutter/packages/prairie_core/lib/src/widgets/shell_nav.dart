import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ShellNav.tsx: brand mark, main tabs, and a profile avatar that
/// opens a dropdown (Switch profile / Settings / Disconnect).
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
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (tab, label, icon) in tabs)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _NavTab(label: label, icon: icon, active: tab == active, onPressed: () => onNavigate(tab)),
                        ),
                    ],
                  ),
                ),
                // Themed locally so the captured ambient Theme (PopupMenuButton
                // reapplies it around the overlay route) gives each item's
                // InkWell the same solid dark-orange TV focus fill as
                // Settings' rows/sidebar, instead of the app-wide light-amber
                // focusColor/highlightColor washing out on D-pad focus.
                Theme(
                  data: Theme.of(context).copyWith(
                    focusColor: PrairieColors.focusFill,
                    highlightColor: PrairieColors.focusFill,
                  ),
                  child: PopupMenuButton<_ProfileAction>(
                  tooltip: profileName != null ? 'Profile menu for $profileName' : 'Profile menu',
                  offset: const Offset(0, 12),
                  color: const Color(0xFA10151C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: PrairieColors.amber.withValues(alpha: 0.35)),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ProfileAction.profiles:
                        onProfiles();
                      case _ProfileAction.settings:
                        onSettings();
                      case _ProfileAction.disconnect:
                        onDisconnect();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: false,
                      height: 36,
                      child: Text(profileName ?? 'Profile', style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _ProfileAction.profiles,
                      child: _MenuRow(icon: Icons.people_outline, label: 'Switch profile'),
                    ),
                    const PopupMenuItem(
                      value: _ProfileAction.settings,
                      child: _MenuRow(icon: Icons.settings_outlined, label: 'Settings'),
                    ),
                    const PopupMenuItem(
                      value: _ProfileAction.disconnect,
                      child: _MenuRow(icon: Icons.power_settings_new, label: 'Disconnect'),
                    ),
                  ],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: PrairieColors.amber.withValues(alpha: 0.35), width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: profileAvatarUrl != null
                          ? CircleAvatar(radius: 16, backgroundImage: NetworkImage(profileAvatarUrl!))
                          : const CircleAvatar(
                              radius: 16,
                              backgroundColor: PrairieColors.bgSoft,
                              child: Icon(Icons.person, size: 18, color: PrairieColors.muted),
                            ),
                    ),
                  ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ProfileAction { profiles, settings, disconnect }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: PrairieColors.muted),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: PrairieColors.ink)),
      ],
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
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => _focused = value),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: _focused ? Border.all(color: PrairieColors.ring, width: 3) : null,
          boxShadow: _focused ? prairieFocusRing(width: 2) : null,
        ),
        child: TextButton.icon(
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: widget.active
                ? PrairieColors.bg
                : _focused
                    ? PrairieColors.bg
                    : PrairieColors.ink,
            backgroundColor: widget.active
                ? PrairieColors.amber
                : _focused
                    ? PrairieColors.ink
                    : Colors.transparent,
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
