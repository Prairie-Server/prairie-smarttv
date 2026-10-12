import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Upcoming episodes and releases for the next two weeks, one rail per local
/// day. Mirrors the web app's Calendar page, minus its week navigator and
/// filters.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  List<CalendarDay> _days = [];
  bool _loading = true;
  String? _error;

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
      final now = DateTime.now();
      final events = await fetchCalendar(ref.read(apiClientProvider), ref.read(sessionProvider)!, from: now);
      if (!mounted) return;
      setState(() => _days = groupCalendarEvents(events, now));
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load the calendar');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(CalendarEvent event) {
    ref.read(routeProvider.notifier).go(
      DetailRoute(contentId: event.detailContentId, back: CalendarRoute(restoreContentId: event.contentId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ref.watch(sessionProvider)!.serverUrl;
    final restoreId = widget.restoreContentId;
    final restorable = restoreId != null && _days.any((d) => d.events.any((e) => e.contentId == restoreId));
    return ShellScaffold(
      active: ShellTab.calendar,
      body: _loading
          ? const Center(child: PrairieLoadingIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        autofocus: true,
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : _days.isEmpty
                  ? const Center(
                      child: Text(
                        'Nothing airing in the next two weeks.',
                        style: TextStyle(color: PrairieColors.muted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      children: [
                        for (final (dayIndex, day) in _days.indexed)
                          MediaRow<CalendarEvent>(
                            title: day.label,
                            items: day.events,
                            itemBuilder: (context, event, index) => PosterCard(
                              title: event.title,
                              subtitle: event.episodeLabel,
                              posterUrl: event.posterUrl,
                              serverUrl: serverUrl,
                              watched: event.watched,
                              autofocus: restorable
                                  ? event.contentId == restoreId
                                  : dayIndex == 0 && index == 0,
                              onTap: () => _open(event),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
