import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors `LIBRARY_SORT_OPTIONS` from src/lib/browseCards.ts.
class _SortOption {
  const _SortOption(this.value, this.label, this.order);
  final String value;
  final String label;
  final String order;
}

const _sortOptions = [
  _SortOption('title', 'Title', 'asc'),
  _SortOption('date_added', 'Date Added', 'desc'),
  _SortOption('release_date', 'Release Date', 'desc'),
  _SortOption('year', 'Year', 'desc'),
  _SortOption('rating_imdb', 'IMDb Rating', 'desc'),
];

/// Mirrors LibraryBrowseScreen.tsx.
class LibraryBrowseScreen extends ConsumerStatefulWidget {
  const LibraryBrowseScreen({super.key, required this.library, this.restoreContentId});

  final Library library;
  final String? restoreContentId;

  @override
  ConsumerState<LibraryBrowseScreen> createState() => _LibraryBrowseScreenState();
}

class _LibraryBrowseScreenState extends ConsumerState<LibraryBrowseScreen> {
  List<CatalogItem> _items = [];
  int? _total;
  bool _hasMore = false;
  String? _snapshot;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _sortIndex = 0;
  String _typeFilter = 'series';

  bool get _showTypeFilter => const {'series', 'show', 'tv'}.contains(widget.library.type);
  String? get _effectiveType => _showTypeFilter ? _typeFilter : null;
  _SortOption get _sort => _sortOptions[_sortIndex];

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
      final session = ref.read(sessionProvider)!;
      final page = await fetchCatalog(
        ref.read(apiClientProvider),
        session,
        CatalogQuery(libraryId: widget.library.id, type: _effectiveType, offset: 0, limit: 60, sort: _sort.value, order: _sort.order),
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total ?? page.items.length;
        _hasMore = page.hasMore ?? false;
        _snapshot = page.snapshot;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load library');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final session = ref.read(sessionProvider)!;
      final page = await fetchCatalog(
        ref.read(apiClientProvider),
        session,
        CatalogQuery(
          libraryId: widget.library.id,
          type: _effectiveType,
          offset: _items.length,
          limit: 60,
          snapshot: _snapshot,
          sort: _sort.value,
          order: _sort.order,
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.hasMore ?? false;
        if (page.snapshot != null) _snapshot = page.snapshot;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load more');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _reload({int? sortIndex, String? typeFilter}) {
    setState(() {
      if (sortIndex != null) _sortIndex = sortIndex;
      if (typeFilter != null) _typeFilter = typeFilter;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(const LibrariesRoute());
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.library.name, style: const TextStyle(fontFamily: 'Fraunces')),
        leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(const LibrariesRoute())),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var i = 0; i < _sortOptions.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(label: Text(_sortOptions[i].label), selected: _sortIndex == i, onSelected: (_) => _reload(sortIndex: i)),
                  ),
                if (_showTypeFilter) ...[
                  const VerticalDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(label: const Text('Series'), selected: _typeFilter == 'series', onSelected: (_) => _reload(typeFilter: 'series')),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(label: const Text('Episodes'), selected: _typeFilter == 'episode', onSelected: (_) => _reload(typeFilter: 'episode')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_total != null && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('$_total title${_total == 1 ? '' : 's'} · Sorted by ${_sort.label}', style: const TextStyle(color: PrairieColors.muted)),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
          Expanded(
            child: _loading
                ? const Center(child: PrairieLoadingIndicator())
                : _items.isEmpty
                ? const Center(child: Text('No titles in this library yet.', style: TextStyle(color: PrairieColors.muted)))
                : PosterGrid(
                    items: _items,
                    serverUrl: session.serverUrl,
                    restoreContentId: widget.restoreContentId,
                    onOpen: (item) => ref.read(routeProvider.notifier).go(
                      DetailRoute(
                        contentId: item.contentId,
                        seed: item,
                        back: LibraryRoute(library: widget.library, restoreContentId: item.contentId),
                      ),
                    ),
                  ),
          ),
          if (_hasMore && !_loading)
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
