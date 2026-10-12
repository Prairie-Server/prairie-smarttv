import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Concurrent per-library collection requests, matching
/// `COLLECTION_FETCH_CONCURRENCY` in CollectionsScreen.tsx.
const _collectionFetchConcurrency = 4;

Future<List<R>> _mapWithConcurrency<T, R>(List<T> items, int limit, Future<R> Function(T) run) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await run(items[index]);
    }
  }

  await Future.wait(List.generate(limit.clamp(0, items.length), (_) => worker()));
  return results.cast<R>();
}

/// Mirrors CollectionsScreen.tsx.
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  List<CollectionCard> _libraryCollections = [];
  List<CollectionCard> _personal = [];
  CollectionCapabilities? _capabilities;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  final _newFocus = FocusNode(debugLabel: 'collections-new');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newFocus.dispose();
    super.dispose();
  }

  /// [quiet] keeps the current rows (and the focused button) on screen
  /// instead of swapping in the loading spinner.
  Future<void> _load({bool quiet = false}) async {
    setState(() {
      if (!quiet) _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      // Unknown capabilities hide the editing actions rather than failing the page.
      final capabilitiesFuture = fetchCollectionCapabilities(client, session).then<CollectionCapabilities?>((c) => c, onError: (_) => null);
      final personalFuture = fetchPersonalCollections(client, session).catchError((_) => <CollectionCard>[]);
      final libraries = await fetchLibraries(client, session);
      final libraryCards = (await _mapWithConcurrency(
        libraries,
        _collectionFetchConcurrency,
        (library) => fetchLibraryCollections(client, session, library.id),
      )).expand((c) => c).toList();
      final personalCards = await personalFuture;
      final capabilities = await capabilitiesFuture;
      if (!mounted) return;
      setState(() {
        _libraryCollections = libraryCards;
        _personal = personalCards;
        _capabilities = capabilities;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load collections');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(CollectionCard card) {
    ref.read(routeProvider.notifier).go(CollectionRoute(collection: card));
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    final name = await showCollectionNameDialog(context, title: 'New collection', confirmLabel: 'Create');
    if (name == null || !mounted) return;
    setState(() => _creating = true);
    try {
      await createCollection(ref.read(apiClientProvider), ref.read(sessionProvider)!, name);
      _notify('Created “$name”');
      await _load(quiet: true);
    } catch (e) {
      _notify(e is ApiError ? e.message : 'Could not create the collection');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      active: ShellTab.collections,
      body: _loading
          ? const Center(child: PrairieLoadingIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                if (_capabilities?.allowed ?? false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        focusNode: _newFocus,
                        // Nothing else to focus on an empty page.
                        autofocus: _libraryCollections.isEmpty && _personal.isEmpty,
                        onPressed: _creating ? null : _create,
                        icon: const Icon(Icons.add),
                        label: Text(_creating ? 'Creating…' : 'New collection'),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                  ),
                if (_libraryCollections.isEmpty && _personal.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('No collections yet.', style: TextStyle(color: PrairieColors.muted)),
                  ),
                MediaRow<CollectionCard>(
                  title: 'Library collections',
                  items: _libraryCollections,
                  escapeUpFocusNode: (_capabilities?.allowed ?? false) ? _newFocus : null,
                  itemBuilder: (context, card, index) => PosterCard(
                    title: card.displayTitle,
                    subtitle: card.itemCount != null ? '${card.itemCount} titles' : null,
                    posterUrl: card.posterUrl,
                    serverUrl: ref.read(sessionProvider)!.serverUrl,
                    onTap: () => _open(card),
                  ),
                ),
                MediaRow<CollectionCard>(
                  title: 'Your collections',
                  items: _personal,
                  escapeUpFocusNode: (_capabilities?.allowed ?? false) && _libraryCollections.isEmpty ? _newFocus : null,
                  itemBuilder: (context, card, index) => PosterCard(
                    title: card.displayTitle,
                    subtitle: card.itemCount != null ? '${card.itemCount} titles' : null,
                    posterUrl: card.posterUrl,
                    serverUrl: ref.read(sessionProvider)!.serverUrl,
                    onTap: () => _open(card),
                  ),
                ),
              ],
            ),
    );
  }
}
