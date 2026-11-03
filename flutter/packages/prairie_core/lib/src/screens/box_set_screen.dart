import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// One movie box set: its overview and facts over its films in release
/// order (`GET /api/v2/catalog/box-sets/{id}`). A set the library turned off,
/// or one with too few of its films left, answers 404 and reads as
/// unavailable. Mirrors Android's BoxSetScreen.
class BoxSetScreen extends ConsumerStatefulWidget {
  const BoxSetScreen({super.key, required this.route});

  final BoxSetRoute route;

  @override
  ConsumerState<BoxSetScreen> createState() => _BoxSetScreenState();
}

class _BoxSetScreenState extends ConsumerState<BoxSetScreen> {
  late BoxSet _boxSet = widget.route.boxSet;
  List<CatalogItem> _items = [];
  bool _loading = true;
  bool _gone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await fetchBoxSet(
        ref.read(apiClientProvider),
        ref.read(sessionProvider)!,
        id: widget.route.boxSet.id,
        libraryId: widget.route.boxSet.libraryId,
      );
      if (!mounted) return;
      setState(() {
        _boxSet = detail.boxSet;
        _items = detail.items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiError && e.status == 404) {
          _gone = true;
        } else {
          _error = e is ApiError ? e.message : 'Could not load the box set';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _back() => ref.read(routeProvider.notifier).go(widget.route.back);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final overview = _boxSet.overview?.trim() ?? '';
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_boxSet.heroFacts.join(' · '), style: const TextStyle(color: PrairieColors.muted, fontSize: 14)),
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Text(
                overview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PrairieColors.ink, fontSize: 16, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_boxSet.title, style: const TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: _back),
        ),
        body: Column(
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
            Expanded(
              child: _loading
                  ? const Center(child: PrairieLoadingIndicator())
                  : _gone
                  ? const Center(
                      child: Text(
                        "This box set isn't available. Box sets may be turned off for this library, or too few of its movies are here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PrairieColors.muted),
                      ),
                    )
                  : _items.isEmpty
                  ? Center(child: Text(_error == null ? 'This box set is empty.' : '', style: const TextStyle(color: PrairieColors.muted)))
                  : PosterGrid(
                      items: _items,
                      serverUrl: session.serverUrl,
                      restoreContentId: widget.route.restoreContentId,
                      header: header,
                      onOpen: (item) => ref.read(routeProvider.notifier).go(
                        DetailRoute(contentId: item.contentId, seed: item, back: widget.route.withRestore(item.contentId)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
