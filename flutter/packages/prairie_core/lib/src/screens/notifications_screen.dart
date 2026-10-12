import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Short relative time for an inbox row. Mirrors `formatNotificationTime` in
/// the web app's pages/Notifications.tsx (absolute "Mon D" past a week).
String formatNotificationTime(DateTime at, {DateTime? now}) {
  final minutes = (now ?? DateTime.now()).difference(at).inSeconds / 60;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '${minutes.round()}m ago';
  final hours = (minutes / 60).round();
  if (hours < 24) return '${hours}h ago';
  final days = (hours / 24).round();
  if (days < 7) return '${days}d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final local = at.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}

/// The profile's notification inbox, with a pinned "update available" notice
/// on top when a newer sideload release exists. Mirrors pages/Notifications.tsx:
/// selecting a row marks it read and opens its catalog item, if it has one.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, required this.back});

  final Route back;

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _items = [];
  String _readCutoff = '';
  bool _loading = true;
  String? _error;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await fetchNotifications(ref.read(apiClientProvider), ref.read(sessionProvider)!);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _readCutoff = page.readCutoff;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load notifications');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _readCutoff.isEmpty) return;
    setState(() => _markingAll = true);
    try {
      await markAllNotificationsRead(ref.read(apiClientProvider), ref.read(sessionProvider)!, _readCutoff);
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _items = [for (final n in _items) n.markedRead(now)]);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not mark notifications read');
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _open(AppNotification notification) {
    if (notification.unread) {
      final now = DateTime.now();
      setState(() => _items = [for (final n in _items) n.id == notification.id ? n.markedRead(now) : n]);
      // Fire-and-forget: a failed mark-read only leaves the server's unread
      // count stale until the next inbox load.
      markNotificationRead(ref.read(apiClientProvider), ref.read(sessionProvider)!, notification.id)
          .catchError((_) {});
    }
    final contentId = notification.contentId;
    if (contentId != null) {
      ref.read(routeProvider.notifier).go(DetailRoute(contentId: contentId, back: NotificationsRoute(back: widget.back)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider).valueOrNull;
    final hasUnread = _items.any((n) => n.unread);
    final empty = _items.isEmpty && update == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(widget.back);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications', style: TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(widget.back)),
          actions: [
            if (hasUnread)
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: TextButton.icon(
                  onPressed: _markingAll ? null : _markAllRead,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Mark all read'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: PrairieLoadingIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 48),
                children: [
                  if (update != null)
                    _NotificationRow(
                      autofocus: true,
                      icon: Icons.system_update_alt,
                      title: 'Update available: Prairie ${update.version}',
                      body: 'Install the new Tizen / webOS package from ${update.url}',
                      unread: true,
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(_error!, style: const TextStyle(color: PrairieColors.danger))),
                          TextButton(autofocus: update == null, onPressed: _load, child: const Text('Try again')),
                        ],
                      ),
                    )
                  else if (empty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text("You're all caught up.", style: TextStyle(color: PrairieColors.muted, fontSize: 18)),
                      ),
                    ),
                  for (final (index, n) in _items.indexed)
                    _NotificationRow(
                      autofocus: index == 0 && update == null && _error == null,
                      icon: n.type.startsWith('request.') ? Icons.inbox_outlined : Icons.new_releases_outlined,
                      title: n.title,
                      body: n.description,
                      time: formatNotificationTime(n.createdAt),
                      unread: n.unread,
                      onTap: () => _open(n),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Full-width inbox row with the same solid focus fill as Settings' rows.
class _NotificationRow extends StatefulWidget {
  const _NotificationRow({
    required this.icon,
    required this.title,
    required this.body,
    this.time,
    required this.unread,
    this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? time;
  final bool unread;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _focused
            ? PrairieColors.focusFill
            : widget.unread
                ? PrairieColors.amber.withValues(alpha: 0.12)
                : PrairieColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          // Always provide onTap so InkWell stays in the TV focus traversal order.
          onTap: widget.onTap ?? () {},
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(14),
          onFocusChange: (value) => setState(() => _focused = value),
          focusColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? PrairieColors.ink.withValues(alpha: 0.85) : PrairieColors.ink.withValues(alpha: 0.1),
                width: _focused ? 3 : 1,
              ),
            ),
            child: Row(
              children: [
                // Unread marker.
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.unread ? PrairieColors.amber : Colors.transparent,
                  ),
                ),
                const SizedBox(width: 14),
                Icon(widget.icon, color: PrairieColors.muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: PrairieColors.ink,
                          fontSize: 17,
                          fontWeight: widget.unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(widget.body, style: const TextStyle(color: PrairieColors.muted, fontSize: 14)),
                    ],
                  ),
                ),
                if (widget.time != null) ...[
                  const SizedBox(width: 16),
                  Text(widget.time!, style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
