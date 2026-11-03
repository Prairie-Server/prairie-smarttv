import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors SearchScreen.tsx.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.restoreContentId});

  final String? restoreContentId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _fieldFocus = FocusNode();
  final _entryFocus = FocusNode();
  String _submitted = '';
  List<CatalogItem> _items = [];
  bool _hasMore = false;
  String? _snapshot;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  /// Box sets matching the query, listed above the titles.
  List<BoxSet> _boxSets = [];

  /// Bumped per search so a slow answer to an older query is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _controller.dispose();
    _fieldFocus.dispose();
    _entryFocus.dispose();
    super.dispose();
  }

  /// Same rationale as ConnectScreen's handler: a focused `TextField`
  /// swallows arrow keys for cursor movement, so escaping it (down into the
  /// results grid) needs geometry-based directional focus driven explicitly.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || !identical(focused, _fieldFocus)) return false;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return false;
    return focused.focusInDirection(direction);
  }

  Future<void> _submit() async {
    final q = _controller.text.trim();
    final generation = ++_generation;
    setState(() {
      _submitted = q;
      _boxSets = [];
    });
    if (q.isEmpty) {
      setState(() {
        _items = [];
        _hasMore = false;
        _snapshot = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Box sets only add to the titles, so a slow answer never holds them up.
    _searchBoxSets(q, generation);
    try {
      final session = ref.read(sessionProvider)!;
      final page = await fetchCatalog(ref.read(apiClientProvider), session, CatalogQuery(q: q, offset: 0, limit: 48));
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore ?? false;
        _snapshot = page.snapshot;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Search failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchBoxSets(String q, int generation) async {
    try {
      final libraries = await ref.read(librariesProvider.future);
      if (!librariesHaveBoxSets(libraries)) return;
      final sets = await searchBoxSets(ref.read(apiClientProvider), ref.read(sessionProvider)!, q);
      if (!mounted || generation != _generation) return;
      setState(() => _boxSets = sets);
    } catch (_) {
      // Optional: the titles still show.
    }
  }

  /// Rows above the titles. Always a widget, even an empty one, so the grid
  /// keeps one scroll view (and its focus) when a row arrives late.
  Widget _resultsHeader(String serverUrl) {
    if (_boxSets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: MediaRow<BoxSet>(
        title: 'Box sets',
        items: _boxSets,
        escapeUpFocusNode: _entryFocus,
        itemBuilder: (context, boxSet, index) => PosterCard(
          title: boxSet.title,
          subtitle: boxSet.cardCaption,
          posterUrl: boxSet.posterUrl,
          serverUrl: serverUrl,
          onTap: () => ref.read(routeProvider.notifier).go(BoxSetRoute(boxSet: boxSet, back: const SearchRoute())),
        ),
      ),
    );
  }

  Future<void> _loadMore() async {
    if (_submitted.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final session = ref.read(sessionProvider)!;
      final page = await fetchCatalog(
        ref.read(apiClientProvider),
        session,
        CatalogQuery(q: _submitted, offset: _items.length, limit: 48, snapshot: _snapshot),
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
    return ShellScaffold(
      active: ShellTab.search,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _fieldFocus,
                    decoration: InputDecoration(
                      labelText: 'Query',
                      hintText: 'Title…',
                      // Default focus lands here (see below) rather than on
                      // the field itself, so opening this screen doesn't pop
                      // the on-screen keyboard until the viewer opts in.
                      suffixIcon: IconButton(
                        focusNode: _entryFocus,
                        autofocus: true,
                        icon: const Icon(Icons.keyboard),
                        tooltip: 'Enter search text',
                        onPressed: () => _fieldFocus.requestFocus(),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.search), label: const Text('Search')),
              ],
            ),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
          if (!_loading && _submitted.isNotEmpty && _items.isEmpty && _boxSets.isEmpty)
            Text('No matches for "$_submitted".', style: const TextStyle(color: PrairieColors.muted)),
          Expanded(
            child: _loading
                ? const Center(child: PrairieLoadingIndicator())
                : PosterGrid(
                    items: _items,
                    serverUrl: session.serverUrl,
                    restoreContentId: widget.restoreContentId,
                    header: _resultsHeader(session.serverUrl),
                    onOpen: (item) => ref.read(routeProvider.notifier).go(
                      DetailRoute(
                        contentId: item.contentId,
                        seed: item,
                        back: SearchRoute(restoreContentId: item.contentId),
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
    );
  }
}
