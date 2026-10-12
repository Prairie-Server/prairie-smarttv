import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// The profile's personalized recommendation rows. Mirrors the web app's
/// For You (Discover) page, minus the rows Home already shows and the taste
/// profile card. A profile with no personalized rows yet gets the taste
/// picker instead, as the web app's /taste-seed onboarding.
class ForYouScreen extends ConsumerStatefulWidget {
  const ForYouScreen({super.key, this.restoreContentId});

  /// When returning from item details, focus the card with this content id.
  final String? restoreContentId;

  @override
  ConsumerState<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends ConsumerState<ForYouScreen> {
  List<RecommendationRow> _rows = [];
  bool _personalized = false;
  bool _loading = true;
  String? _error;
  /// Set once the picker has posted: the server refreshes the taste profile
  /// in the background, so rows can stay cold for a few minutes.
  bool _preparing = false;
  /// The picker was opened from "Tune recommendations"; Back returns to the rows.
  bool _tuning = false;
  final _tuneFocus = FocusNode(debugLabel: 'for-you-tune');
  /// See [CalendarScreen]: rails build lazily, so the restored card is
  /// focused and scrolled into view explicitly after the first frame.
  final _restoreFocus = FocusNode(debugLabel: 'for-you-restore-item');
  bool _restoreApplied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tuneFocus.dispose();
    _restoreFocus.dispose();
    super.dispose();
  }

  void _applyRestoreFocus() {
    if (_restoreApplied) return;
    _restoreApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _restoreFocus.context;
      if (!mounted || ctx == null) return;
      _restoreFocus.requestFocus();
      Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await fetchDiscover(ref.read(apiClientProvider), ref.read(sessionProvider)!);
      if (!mounted) return;
      setState(() {
        _personalized = rows.any((r) => r.personalized);
        _rows = rows.where((r) => !homeDuplicateRowKinds.contains(r.kind)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load recommendations');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPicked() {
    setState(() {
      _tuning = false;
      _preparing = true;
    });
    _load();
  }

  void _open(CatalogItem item) {
    ref.read(routeProvider.notifier).go(
      DetailRoute(contentId: item.contentId, seed: item, back: ForYouRoute(restoreContentId: item.contentId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      active: ShellTab.forYou,
      onBack: _tuning ? () => setState(() => _tuning = false) : null,
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
              : _tuning || (!_personalized && !_preparing)
                  ? TastePicker(onDone: _onPicked, onCancel: _tuning ? () => setState(() => _tuning = false) : null)
                  : _buildRows(),
    );
  }

  Widget _buildRows() {
    final serverUrl = ref.watch(sessionProvider)!.serverUrl;
    final restoreId = widget.restoreContentId;
    final restorable = restoreId != null && _rows.any((r) => r.items.any((i) => i.contentId == restoreId));
    if (restorable) _applyRestoreFocus();
    // A card can sit in several rows; only the first copy takes the restore.
    final restoreRow = restorable ? _rows.indexWhere((r) => r.items.any((i) => i.contentId == restoreId)) : -1;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _preparing
                        ? 'Thanks! Your recommendations are being prepared — this can take a few minutes.'
                        : 'Picks based on what you watch and love.',
                    style: const TextStyle(color: PrairieColors.muted, fontSize: 16),
                  ),
                ),
                if (_preparing) ...[
                  OutlinedButton.icon(
                    autofocus: _rows.isEmpty,
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(width: 12),
                ],
                OutlinedButton.icon(
                  focusNode: _tuneFocus,
                  autofocus: _rows.isEmpty && !_preparing,
                  onPressed: () => setState(() => _tuning = true),
                  icon: const Icon(Icons.tune),
                  label: const Text('Tune recommendations'),
                ),
              ],
            ),
          ),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing new to recommend right now.', style: TextStyle(color: PrairieColors.muted)),
            ),
          // Not a ListView: a handful of rails, and every rail must be built
          // for the restored card to exist wherever it is.
          for (final (rowIndex, row) in _rows.indexed)
            MediaRow<CatalogItem>(
              title: row.title,
              items: row.items,
              escapeUpFocusNode: rowIndex == 0 ? _tuneFocus : null,
              // ponytail: builds the whole rail, as on Calendar — fine for a
              // recommendation row's ~20 cards.
              cacheExtent: rowIndex == restoreRow ? 100000 : null,
              itemBuilder: (context, item, index) => PosterCard(
                title: item.title,
                subtitle: item.subtitle,
                posterUrl: item.posterUrl,
                serverUrl: serverUrl,
                watched: item.userState?.played ?? false,
                favorite: item.userState?.isFavorite ?? false,
                progress: item.progress,
                focusNode: rowIndex == restoreRow && item.contentId == restoreId ? _restoreFocus : null,
                autofocus: !restorable && rowIndex == 0 && index == 0,
                onTap: () => _open(item),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fewest picks the picker accepts, as on the web app.
const minTastePicks = 3;

/// The taste picker's selection. Titles the profile already favourited
/// start selected unless the user deselects them, as on the web app.
class TastePicks {
  final _favorites = <String>{};
  final _toggled = <String, bool>{};

  /// Records a loaded page's existing favourites.
  void addPage(Iterable<CatalogItem> items) {
    for (final item in items) {
      if (item.userState?.isFavorite ?? false) _favorites.add(item.contentId);
    }
  }

  bool isPicked(String contentId) => _toggled[contentId] ?? _favorites.contains(contentId);

  void toggle(String contentId) => _toggled[contentId] = !isPicked(contentId);

  int get count => {..._favorites, ..._toggled.keys}.where(isPicked).length;

  /// Picks that aren't favourites yet — all the server needs to be sent.
  List<String> get newPicks => [
    for (final MapEntry(:key, :value) in _toggled.entries)
      if (value && !_favorites.contains(key)) key,
  ];
}

/// A grid of `taste-seed/items` cards to favourite with OK, loading more
/// pages while scrolling. "Done" posts the picks and calls [onDone].
class TastePicker extends ConsumerStatefulWidget {
  const TastePicker({super.key, required this.onDone, this.onCancel});

  final VoidCallback onDone;

  /// Shows a Cancel button when set.
  final VoidCallback? onCancel;

  @override
  ConsumerState<TastePicker> createState() => _TastePickerState();
}

class _TastePickerState extends ConsumerState<TastePicker> {
  final _items = <CatalogItem>[];
  final _picks = TastePicks();
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await fetchTasteSeedItems(ref.read(apiClientProvider), ref.read(sessionProvider)!, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _picks.addPage(page.items);
        _cursor = page.nextCursor;
      });
    } catch (e) {
      // A failed later page just stops paging; the error shows in the header.
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load titles');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// Called from the grid's builder as it nears the end; fetches after the build.
  void _maybeLoadMore() {
    if (_cursor == null || _loadingMore || _error != null) return;
    _loadingMore = true;
    Future.microtask(_loadPage);
  }

  Future<void> _submit() async {
    final picks = _picks.newPicks;
    if (picks.isEmpty) {
      widget.onDone();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await submitTasteSeed(ref.read(apiClientProvider), ref.read(sessionProvider)!, picks);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e is ApiError ? e.message : 'Could not save your picks';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PrairieLoadingIndicator());
    if (_items.isEmpty) {
      final back = _error == null ? widget.onCancel : null;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? 'Nothing to pick from yet — add some titles to your libraries.',
              style: TextStyle(color: _error != null ? PrairieColors.danger : PrairieColors.muted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              autofocus: true,
              onPressed: back ?? _loadPage,
              icon: Icon(back != null ? Icons.arrow_back : Icons.refresh),
              label: Text(back != null ? 'Back' : 'Try again'),
            ),
          ],
        ),
      );
    }
    final serverUrl = ref.watch(sessionProvider)!.serverUrl;
    final count = _picks.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pick a few titles you love',
                      style: TextStyle(fontFamily: 'Fraunces', fontSize: 26, color: PrairieColors.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _error ??
                          (count == 0
                              ? 'Select at least $minTastePicks to personalize your recommendations.'
                              : '$count selected${count < minTastePicks ? ' — ${minTastePicks - count} more to continue' : ''}'),
                      style: TextStyle(color: _error != null ? PrairieColors.danger : PrairieColors.muted),
                    ),
                  ],
                ),
              ),
              if (widget.onCancel != null) ...[
                OutlinedButton(onPressed: _submitting ? null : widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
              ],
              ElevatedButton.icon(
                onPressed: count >= minTastePicks && !_submitting ? _submit : null,
                icon: const Icon(Icons.check),
                label: Text(_submitting ? 'Saving…' : 'Done'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisExtent: 300, crossAxisSpacing: 16, mainAxisSpacing: 20),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              if (index >= _items.length - 12) _maybeLoadMore();
              final item = _items[index];
              final picked = _picks.isPicked(item.contentId);
              return PosterCard(
                title: item.title,
                subtitle: picked ? 'Selected' : item.subtitle,
                posterUrl: item.posterUrl,
                serverUrl: serverUrl,
                favorite: picked,
                autofocus: index == 0,
                onTap: () => setState(() => _picks.toggle(item.contentId)),
              );
            },
          ),
        ),
      ],
    );
  }
}
