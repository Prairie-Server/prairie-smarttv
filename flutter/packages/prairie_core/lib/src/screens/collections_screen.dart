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
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final personalFuture = fetchPersonalCollections(client, session).catchError((_) => <CollectionCard>[]);
      final libraries = await fetchLibraries(client, session);
      final libraryCards = (await _mapWithConcurrency(
        libraries,
        _collectionFetchConcurrency,
        (library) => fetchLibraryCollections(client, session, library.id),
      )).expand((c) => c).toList();
      final personalCards = await personalFuture;
      if (!mounted) return;
      setState(() {
        _libraryCollections = libraryCards;
        _personal = personalCards;
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

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      active: ShellTab.collections,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
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
