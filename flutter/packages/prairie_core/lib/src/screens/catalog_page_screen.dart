import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// A full, paged poster grid for a [CatalogPageRoute]: a Home row's Explore
/// all page (titled with the row's title) or the profile's History. Pages
/// through `GET /api/v2/catalog?source=…`; a row the profile can no longer
/// see answers 404 and reads as "no longer available".
class CatalogPageScreen extends ConsumerStatefulWidget {
  const CatalogPageScreen({super.key, required this.route});

  final CatalogPageRoute route;

  @override
  ConsumerState<CatalogPageScreen> createState() => _CatalogPageScreenState();
}

class _CatalogPageScreenState extends ConsumerState<CatalogPageScreen> {
  static const _pageSize = 60;

  /// How many pages a return from details reads looking for the card the
  /// viewer opened, before settling for the first card.
  static const _restorePageBudget = 10;

  List<CatalogItem> _items = [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _gone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<CatalogSourcePage> _fetch(String? cursor) {
    final route = widget.route;
    return fetchCatalogSourcePage(
      ref.read(apiClientProvider),
      ref.read(sessionProvider)!,
      source: switch (route.source) {
        CatalogPageSource.homeSection => 'section',
        CatalogPageSource.history => 'history',
      },
      scope: route.source == CatalogPageSource.homeSection ? 'home' : null,
      sectionId: route.sectionId,
      cursor: cursor,
      limit: _pageSize,
    );
  }

  Future<void> _load() async {
    try {
      var page = await _fetch(null);
      final items = [...page.items];
      // Returning from details: read on until the opened card is loaded so
      // focus can go back to it.
      final restoreId = widget.route.restoreContentId;
      var pages = 1;
      while (restoreId != null &&
          page.nextCursor != null &&
          pages < _restorePageBudget &&
          !items.any((item) => item.contentId == restoreId)) {
        page = await _fetch(page.nextCursor);
        items.addAll(page.items);
        pages++;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _nextCursor = page.nextCursor;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiError && e.status == 404) {
          _gone = true;
        } else {
          _error = e is ApiError ? e.message : 'Could not load ${widget.route.title}';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(cursor);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _nextCursor = page.nextCursor;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load more');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _back() => ref.read(routeProvider.notifier).go(widget.route.back);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final emptyText = widget.route.source == CatalogPageSource.history ? 'Nothing watched yet.' : 'This row is empty.';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.route.title, style: const TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: _back),
        ),
        body: Column(
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
            Expanded(
              child: _loading
                  ? const Center(child: PrairieLoadingIndicator())
                  : _gone
                  ? const Center(child: Text('This row is no longer available.', style: TextStyle(color: PrairieColors.muted)))
                  : _items.isEmpty
                  ? Center(child: Text(_error == null ? emptyText : '', style: const TextStyle(color: PrairieColors.muted)))
                  : PosterGrid(
                      items: _items,
                      serverUrl: session.serverUrl,
                      restoreContentId: widget.route.restoreContentId,
                      onOpen: (item) => ref.read(routeProvider.notifier).go(
                        DetailRoute(contentId: item.contentId, seed: item, back: widget.route.withRestore(item.contentId)),
                      ),
                    ),
            ),
            if (_nextCursor != null && !_loading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: const Icon(Icons.more_horiz),
                  label: Text(_loadingMore ? 'Loading…' : 'Load more'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
