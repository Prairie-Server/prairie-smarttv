import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors SearchScreen.tsx.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

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
    setState(() => _submitted = q);
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
    try {
      final session = ref.read(sessionProvider)!;
      final page = await fetchCatalog(ref.read(apiClientProvider), session, CatalogQuery(q: q, offset: 0, limit: 48));
      if (!mounted) return;
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
          if (!_loading && _submitted.isNotEmpty && _items.isEmpty)
            Text('No matches for "$_submitted".', style: const TextStyle(color: PrairieColors.muted)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
                : PosterGrid(
                    items: _items,
                    serverUrl: session.serverUrl,
                    onOpen: (item) =>
                        ref.read(routeProvider.notifier).go(DetailRoute(contentId: item.contentId, seed: item, back: const SearchRoute())),
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
