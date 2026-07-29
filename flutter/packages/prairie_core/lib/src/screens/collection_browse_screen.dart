import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors CollectionBrowseScreen.tsx.
class CollectionBrowseScreen extends ConsumerStatefulWidget {
  const CollectionBrowseScreen({super.key, required this.title, required this.collectionId, this.libraryId});

  final String title;
  final String collectionId;
  final int? libraryId;

  @override
  ConsumerState<CollectionBrowseScreen> createState() => _CollectionBrowseScreenState();
}

class _CollectionBrowseScreenState extends ConsumerState<CollectionBrowseScreen> {
  List<CatalogItem> _items = [];
  bool _hasMore = false;
  String? _snapshot;
  bool _loading = true;
  bool _loadingMore = false;
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
      final session = ref.read(sessionProvider)!;
      final page = await fetchCatalog(
        ref.read(apiClientProvider),
        session,
        CatalogQuery(
          source: widget.libraryId != null ? 'library_collection' : 'user_collection',
          collectionId: widget.collectionId,
          libraryId: widget.libraryId,
          offset: 0,
          limit: 80,
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore ?? false;
        _snapshot = page.snapshot;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load collection');
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
          source: widget.libraryId != null ? 'library_collection' : 'user_collection',
          collectionId: widget.collectionId,
          libraryId: widget.libraryId,
          offset: _items.length,
          limit: 80,
          snapshot: _snapshot,
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(const CollectionsRoute());
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontFamily: 'Fraunces')),
        leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(const CollectionsRoute())),
      ),
      body: Column(
        children: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('${_items.length}${_hasMore ? '+' : ''} title${_items.length == 1 ? '' : 's'}', style: const TextStyle(color: PrairieColors.muted)),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
                : _items.isEmpty
                ? const Center(child: Text('This collection is empty.', style: TextStyle(color: PrairieColors.muted)))
                : PosterGrid(
                    items: _items,
                    serverUrl: session.serverUrl,
                    onOpen: (item) => ref.read(routeProvider.notifier).go(
                      DetailRoute(
                        contentId: item.contentId,
                        seed: item,
                        back: CollectionRoute(
                          collection: CollectionCard(id: widget.collectionId, title: widget.title, libraryId: widget.libraryId),
                        ),
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
