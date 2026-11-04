import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Shared by the requests screens: they re-check that requests are still on
/// when they open and when the app resumes, and close to Home once the
/// server reports them off (status off, or a call answering a capability
/// problem). Mirrors Android TV leaving its Requests tab when requests turn
/// off.
mixin _RequestsGuard<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  AppLifecycleListener? _lifecycle;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkRequestsOn);
    _checkRequestsOn();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _checkRequestsOn() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final status = await fetchRequestsStatus(ref.read(apiClientProvider), session);
      if (status.available) return;
    } catch (e) {
      // A network hiccup isn't the server turning requests off.
      if (!isRequestsOffError(e)) return;
    }
    _closeRequests();
  }

  /// After a failed call: close at once on a capability problem, otherwise
  /// ask the server whether requests are still on.
  Future<void> _afterRequestsError(Object error) async {
    if (isRequestsOffError(error)) {
      _closeRequests();
    } else {
      await _checkRequestsOn();
    }
  }

  void _closeRequests() {
    if (!mounted || _closing) return;
    _closing = true;
    ref.invalidate(requestsAvailableProvider);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Requests are turned off on this server.')));
    ref.read(routeProvider.notifier).go(const HomeRoute());
  }
}

/// Where opening [title] goes: its library page once it's in the library,
/// otherwise its request page. Android TV's Discover card does the same.
Route requestTitleDestination(RequestTitle title, Route back) {
  final contentId = title.libraryContentId;
  if (title.inLibrary && contentId != null) return DetailRoute(contentId: contentId, back: back);
  return RequestTitleRoute(title: title, back: back);
}

/// The caption under a request card: the request's state when there is
/// one, else the year.
String? requestTitleCaption(RequestTitle title) {
  if (title.inLibrary) return 'In your library';
  final state = title.request.state;
  if (state != null) return requestStateLabel(state);
  final kind = title.mediaType == 'series' ? 'Series' : 'Movie';
  return title.year == null ? kind : '${title.year} · $kind';
}

/// A TMDB title as a poster card.
class RequestTitleCard extends StatelessWidget {
  const RequestTitleCard({super.key, required this.title, required this.serverUrl, required this.onTap, this.autofocus = false, this.focusNode});

  final RequestTitle title;
  final String serverUrl;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return PosterCard(
      title: title.title,
      subtitle: requestTitleCaption(title),
      posterUrl: tmdbImageUrl(title.posterPath),
      serverUrl: serverUrl,
      autofocus: autofocus,
      focusNode: focusNode,
      watched: title.inLibrary,
      onTap: onTap,
    );
  }
}

/// The Requests hub: the viewer's own requests, then each of the server's
/// Discover title rows in the admin's order, each ending in a See all card.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key, required this.route});

  final RequestsRoute route;

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> with _RequestsGuard {
  List<MediaRequest> _mine = [];
  List<DiscoverSection> _rows = [];
  bool _loading = true;
  String? _error;
  final _restoreFocus = FocusNode(debugLabel: 'requests-restore');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _restoreFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(apiClientProvider);
    final session = ref.read(sessionProvider)!;
    try {
      // My requests are optional: Discover still shows without them.
      final mineRequest = fetchMyRequests(client, session).catchError((Object _) => const <MediaRequest>[]);
      final rows = await fetchDiscoverRows(client, session);
      final mine = await mineRequest;
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _rows = rows;
      });
      if (widget.route.restoreKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _restoreFocus.context == null) return;
          _restoreFocus.requestFocus();
          Scrollable.ensureVisible(_restoreFocus.context!, alignment: 0.35);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiError ? e.message : 'Could not load requests');
      _afterRequestsError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _back() => ref.read(routeProvider.notifier).go(widget.route.back);

  void _open(RequestTitle title) {
    ref.read(routeProvider.notifier).go(requestTitleDestination(title, widget.route.withRestore(title.key)));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final restoreKey = widget.route.restoreKey;
    final mine = [for (final request in _mine) request.asTitle];
    // Without a card to return to, focus starts on the first card.
    final firstRow = mine.isNotEmpty ? mine : _rows.firstOrNull?.results;
    final firstCard = restoreKey == null ? firstRow?.firstOrNull : null;
    // A title can sit in more than one row; only its first card takes the
    // restore node. Rows are numbered from My requests (-1).
    final rowsWithMine = [(-1, mine), for (final (index, row) in _rows.indexed) (index, row.results)];
    final restoreRow = restoreKey == null
        ? null
        : rowsWithMine.where((entry) => entry.$2.any((title) => title.key == restoreKey)).firstOrNull?.$1;

    Widget card(RequestTitle title, {required int row, bool first = false}) {
      final restore = row == restoreRow && title.key == restoreKey;
      return RequestTitleCard(
        title: title,
        serverUrl: session.serverUrl,
        autofocus: first && identical(title, firstCard),
        focusNode: restore ? _restoreFocus : null,
        onTap: () => _open(title),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Requests', style: TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: _back),
        ),
        body: _loading
            ? const Center(child: PrairieLoadingIndicator())
            : _rows.isEmpty && mine.isEmpty
            ? Center(
                child: Text(
                  _error ?? 'Nothing to discover right now.',
                  style: TextStyle(color: _error == null ? PrairieColors.muted : PrairieColors.danger),
                ),
              )
            : ListView(
                clipBehavior: Clip.none,
                padding: const EdgeInsets.only(top: 16, bottom: 32),
                children: [
                  if (mine.isNotEmpty)
                    MediaRow<RequestTitle>(
                      title: 'My requests',
                      items: mine,
                      itemBuilder: (context, title, index) => card(title, row: -1, first: index == 0),
                    ),
                  for (final (rowIndex, row) in _rows.indexed)
                    MediaRow<RequestTitle>(
                      title: row.title,
                      items: row.results,
                      itemBuilder: (context, title, index) => card(title, row: rowIndex, first: index == 0),
                      trailing: row.followingPage == null
                          ? null
                          : ExploreAllCard(
                              focusNode: restoreKey == 'row:${row.key}' ? _restoreFocus : null,
                              onTap: () => ref.read(routeProvider.notifier).go(
                                RequestsRowRoute(
                                  rowKey: row.key,
                                  title: row.title,
                                  back: widget.route.withRestore('row:${row.key}'),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A Discover row's See all page: its titles, a page at a time.
class RequestsRowScreen extends ConsumerStatefulWidget {
  const RequestsRowScreen({super.key, required this.route});

  final RequestsRowRoute route;

  @override
  ConsumerState<RequestsRowScreen> createState() => _RequestsRowScreenState();
}

class _RequestsRowScreenState extends ConsumerState<RequestsRowScreen> with _RequestsGuard {
  /// How many pages a return from a title reads looking for its card.
  static const _restorePageBudget = 5;

  List<RequestTitle> _items = [];
  int? _nextPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _gone = false;
  String? _error;
  final _restoreFocus = FocusNode(debugLabel: 'requests-row-restore');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _restoreFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final restoreKey = widget.route.restoreKey;
      var pages = 0;
      do {
        await _readPage();
        pages++;
      } while (mounted &&
          restoreKey != null &&
          _nextPage != null &&
          pages < _restorePageBudget &&
          !_items.any((title) => title.key == restoreKey));
      if (restoreKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _restoreFocus.context == null) return;
          _restoreFocus.requestFocus();
          Scrollable.ensureVisible(_restoreFocus.context!, alignment: 0.35);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiError && e.status == 404 && !isRequestsOffError(e)) {
          _gone = true;
        } else {
          _error = e is ApiError ? e.message : 'Could not load ${widget.route.title}';
        }
      });
      _afterRequestsError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readPage() async {
    final page = _nextPage;
    if (page == null) return;
    final section = await fetchDiscoverRow(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.route.rowKey, page: page);
    if (!mounted) return;
    // Pages of a chart can overlap as it moves; keep each title once.
    final seen = {for (final title in _items) title.key};
    setState(() {
      _items = [..._items, ...section.results.where((title) => seen.add(title.key))];
      _nextPage = section.results.isEmpty ? null : section.followingPage;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      await _readPage();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load more');
      _afterRequestsError(e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _back() => ref.read(routeProvider.notifier).go(widget.route.back);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final restoreKey = widget.route.restoreKey;
    final restoreIndex = restoreKey == null ? -1 : _items.indexWhere((title) => title.key == restoreKey);
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
                  ? Center(child: Text(_error == null ? 'This row is empty.' : '', style: const TextStyle(color: PrairieColors.muted)))
                  : GridView.builder(
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisExtent: 300,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final title = _items[index];
                        final restore = index == restoreIndex;
                        return RequestTitleCard(
                          title: title,
                          serverUrl: session.serverUrl,
                          autofocus: restore || (restoreIndex < 0 && index == 0),
                          focusNode: restore ? _restoreFocus : null,
                          onTap: () => ref.read(routeProvider.notifier).go(
                            requestTitleDestination(title, widget.route.withRestore(title.key)),
                          ),
                        );
                      },
                    ),
            ),
            if (_nextPage != null && !_loading && _items.isNotEmpty)
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

/// One TMDB title: its poster, overview and request state, with Request,
/// Cancel request (the viewer's own pending request) or Open in library.
class RequestTitleScreen extends ConsumerStatefulWidget {
  const RequestTitleScreen({super.key, required this.route});

  final RequestTitleRoute route;

  @override
  ConsumerState<RequestTitleScreen> createState() => _RequestTitleScreenState();
}

class _RequestTitleScreenState extends ConsumerState<RequestTitleScreen> with _RequestsGuard {
  late RequestTitle _title = widget.route.title;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final title = await fetchRequestTitle(
        ref.read(apiClientProvider),
        ref.read(sessionProvider)!,
        mediaType: widget.route.title.mediaType,
        tmdbId: widget.route.title.tmdbId,
      );
      if (mounted) setState(() => _title = title);
    } catch (e) {
      // The card's own state still shows.
      _afterRequestsError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await createRequest(ref.read(apiClientProvider), ref.read(sessionProvider)!, _title);
      _notify('Requested “${_title.title}”');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not request this title');
      _afterRequestsError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(String requestId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel request?',
      message: 'Your request for “${_title.title}” will be cancelled.',
      confirmLabel: 'Cancel request',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await cancelRequest(ref.read(apiClientProvider), ref.read(sessionProvider)!, requestId);
      _notify('Cancelled your request');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not cancel the request');
      _afterRequestsError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() => ref.read(routeProvider.notifier).go(widget.route.back);

  @override
  Widget build(BuildContext context) {
    final title = _title;
    final request = title.request;
    final requestId = request.requestId;
    final contentId = title.libraryContentId;
    final canOpen = title.inLibrary && contentId != null;
    final canCancel = requestId != null && request.requestedByViewer && request.state == 'pending';
    final poster = tmdbImageUrl(title.posterPath, width: 'w500');
    final backdrop = tmdbImageUrl(title.backdropPath, width: 'w1280');
    final facts = [
      ?title.year?.toString(),
      title.mediaType == 'series' ? 'Series' : 'Movie',
      if (title.inLibrary) 'In your library' else if (request.state != null) requestStateLabel(request.state),
    ];
    final status = switch (request) {
      _ when title.inLibrary => null,
      RequestState(requestId: _?, requestedByViewer: true) => 'You requested this title.',
      RequestState(requestId: _?) => 'Someone has already requested this title.',
      RequestState(requestable: false, :final reason?) => _reasonLabel(reason),
      _ => null,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop != null)
              Opacity(
                opacity: 0.28,
                child: Image.network(backdrop, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 24, 48, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BackButton(onPressed: _back),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              width: 220,
                              height: 330,
                              child: poster == null
                                  ? const PosterFallback()
                                  : Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, _, _) => const PosterFallback()),
                            ),
                          ),
                          const SizedBox(width: 40),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title.title,
                                    style: const TextStyle(fontFamily: 'Fraunces', fontSize: 36, color: PrairieColors.ink),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(facts.join(' · '), style: const TextStyle(color: PrairieColors.muted, fontSize: 15)),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      if (canOpen)
                                        ElevatedButton.icon(
                                          autofocus: true,
                                          onPressed: () => ref.read(routeProvider.notifier).go(
                                            DetailRoute(contentId: contentId, back: widget.route.back),
                                          ),
                                          icon: const Icon(Icons.play_arrow),
                                          label: const Text('Open in library'),
                                        )
                                      else if (request.requestable)
                                        ElevatedButton.icon(
                                          autofocus: true,
                                          onPressed: _busy || _loading ? null : _request,
                                          icon: const Icon(Icons.add),
                                          label: Text(_busy ? 'Requesting…' : 'Request'),
                                        ),
                                      if (canCancel && !canOpen)
                                        OutlinedButton.icon(
                                          autofocus: !request.requestable,
                                          onPressed: _busy ? null : () => _cancel(requestId),
                                          icon: const Icon(Icons.close),
                                          label: const Text('Cancel request'),
                                        ),
                                    ],
                                  ),
                                  if (status != null) ...[
                                    const SizedBox(height: 12),
                                    Text(status, style: const TextStyle(color: PrairieColors.muted)),
                                  ],
                                  if (_error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                                  ],
                                  if (title.overview != null) ...[
                                    const SizedBox(height: 24),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 900),
                                      child: Text(
                                        title.overview!,
                                        style: const TextStyle(color: PrairieColors.ink, fontSize: 17, height: 1.5),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _reasonLabel(String reason) => switch (reason) {
    'requests_disabled' => 'Requests are turned off.',
    'already_available' || 'available' => 'This title is already in the library.',
    'already_requested' => 'This title has already been requested.',
    'not_permitted' || 'forbidden' => "Your profile can't request titles.",
    'rating_restricted' => "This title's rating is above your profile's limit.",
    _ => "This title can't be requested right now.",
  };
}
