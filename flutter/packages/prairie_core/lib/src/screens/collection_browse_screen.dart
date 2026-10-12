import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors CollectionBrowseScreen.tsx. A personal collection the acting
/// profile created also gets Rename / Delete, and (manual collections only)
/// a "Remove titles" mode in which selecting a poster removes it.
class CollectionBrowseScreen extends ConsumerStatefulWidget {
  const CollectionBrowseScreen({
    super.key,
    required this.title,
    required this.collectionId,
    this.libraryId,
    this.restoreContentId,
  });

  final String title;
  final String collectionId;
  final int? libraryId;
  final String? restoreContentId;

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

  late String _title = widget.title;
  /// Set once the collection is known to be the acting profile's own and
  /// capabilities allow editing; null hides every editing action.
  CollectionCard? _editable;
  bool _removing = false;
  bool _busy = false;
  /// Card to focus when the grid mounts (returning from details, or the
  /// neighbour of a removed title). Bumping [_gridGeneration] remounts the
  /// grid so it applies this again.
  late String? _focusContentId = widget.restoreContentId;
  int _gridGeneration = 0;
  final _renameFocus = FocusNode(debugLabel: 'collection-rename');

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.libraryId == null) _loadEditing();
  }

  @override
  void dispose() {
    _renameFocus.dispose();
    super.dispose();
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

  /// Best effort: any failure just leaves the collection read-only.
  Future<void> _loadEditing() async {
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final (capabilities, card) = await (
        fetchCollectionCapabilities(client, session),
        fetchPersonalCollection(client, session, widget.collectionId),
      ).wait;
      if (!mounted || !canEditCollection(capabilities, card, session.profileId)) return;
      setState(() => _editable = card);
    } catch (_) {}
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

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename() async {
    final name = await showCollectionNameDialog(context, title: 'Rename collection', confirmLabel: 'Rename', initialName: _title);
    if (name == null || name == _title || !mounted) return;
    setState(() => _busy = true);
    try {
      await renameCollection(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.collectionId, name);
      if (mounted) setState(() => _title = name);
      _notify('Renamed to “$name”');
    } catch (e) {
      _notify(e is ApiError ? e.message : 'Could not rename the collection');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete collection?',
      message: '“$_title” will be deleted. Its titles stay in your library.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await deleteCollection(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.collectionId);
      _notify('Deleted “$_title”');
      if (mounted) ref.read(routeProvider.notifier).go(const CollectionsRoute());
    } catch (e) {
      _notify(e is ApiError ? e.message : 'Could not delete the collection');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeItem(CatalogItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove from collection?',
      message: 'Remove “${item.title}” from “$_title”?',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    try {
      await removeCollectionItem(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.collectionId, item.contentId);
      if (!mounted) return;
      final index = _items.indexOf(item);
      final remaining = [..._items]..removeAt(index);
      setState(() {
        _items = remaining;
        // Focus the title that slid into its place, else the one before it.
        _focusContentId = remaining.isEmpty ? null : remaining[index.clamp(0, remaining.length - 1)].contentId;
        _gridGeneration++;
        if (remaining.isEmpty) _removing = false;
      });
      // Rename is disabled until this frame leaves "Remove titles".
      if (remaining.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _renameFocus.requestFocus());
      _notify('Removed “${item.title}”');
    } catch (e) {
      _notify(e is ApiError ? e.message : 'Could not remove the title');
    }
  }

  void _openItem(CatalogItem item) {
    ref.read(routeProvider.notifier).go(
      DetailRoute(
        contentId: item.contentId,
        seed: item,
        back: CollectionRoute(
          collection: CollectionCard(id: widget.collectionId, title: _title, libraryId: widget.libraryId),
          restoreContentId: item.contentId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final editable = _editable;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back leaves "Remove titles" first, then the screen.
        if (_removing) {
          setState(() => _removing = false);
        } else {
          ref.read(routeProvider.notifier).go(const CollectionsRoute());
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontFamily: 'Fraunces')),
        leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(const CollectionsRoute())),
        actions: [
          if (editable != null) ...[
            if (editable.isManual && _items.isNotEmpty)
              TextButton.icon(
                onPressed: _busy ? null : () => setState(() => _removing = !_removing),
                icon: Icon(_removing ? Icons.check : Icons.playlist_remove),
                label: Text(_removing ? 'Done' : 'Remove titles'),
              ),
            TextButton.icon(
              focusNode: _renameFocus,
              onPressed: _busy || _removing ? null : _rename,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Rename'),
            ),
            TextButton.icon(
              onPressed: _busy || _removing ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: Column(
        children: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                _removing
                    ? 'Select a title to remove it from this collection.'
                    : '${_items.length}${_hasMore ? '+' : ''} title${_items.length == 1 ? '' : 's'}',
                style: TextStyle(color: _removing ? PrairieColors.amber : PrairieColors.muted),
              ),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
          Expanded(
            child: _loading
                ? const Center(child: PrairieLoadingIndicator())
                : _items.isEmpty
                ? const Center(child: Text('This collection is empty.', style: TextStyle(color: PrairieColors.muted)))
                : PosterGrid(
                    key: ValueKey(_gridGeneration),
                    items: _items,
                    serverUrl: session.serverUrl,
                    restoreContentId: _focusContentId,
                    onOpen: _removing ? _removeItem : _openItem,
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
