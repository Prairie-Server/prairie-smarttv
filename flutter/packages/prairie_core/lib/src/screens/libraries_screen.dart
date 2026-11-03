import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// A library-type tab (Movies, Series, Music, Audiobooks): the profile's
/// libraries of that type. Movies and Series end with a Collections tile,
/// since Collections is no longer a tab of its own. Mirrors
/// LibrariesScreen.tsx.
class LibrariesScreen extends ConsumerWidget {
  const LibrariesScreen({super.key, required this.type});

  final LibraryTabType type;

  bool get _showsCollections => type == LibraryTabType.movies || type == LibraryTabType.series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraries = ref.watch(librariesProvider);
    return ShellScaffold(
      active: type.shellTab,
      body: libraries.when(
        data: (all) => _grid(ref, all.where(type.matches).toList()),
        error: (error, _) => Center(child: Text('$error', style: const TextStyle(color: PrairieColors.danger))),
        loading: () => const Center(child: PrairieLoadingIndicator()),
      ),
    );
  }

  Widget _grid(WidgetRef ref, List<Library> libraries) {
    if (libraries.isEmpty) {
      return Center(
        child: Text('No ${type.label.toLowerCase()} libraries.', style: const TextStyle(color: PrairieColors.muted)),
      );
    }
    final count = libraries.length + (_showsCollections ? 1 : 0);
    return GridView.builder(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisExtent: 140, crossAxisSpacing: 16, mainAxisSpacing: 16),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index == libraries.length) {
          return _LibraryCard(
            name: 'Collections',
            icon: Icons.folder_open_outlined,
            onTap: () => ref.read(routeProvider.notifier).go(CollectionsRoute(tab: type)),
          );
        }
        final library = libraries[index];
        return _LibraryCard(
          name: library.name,
          icon: _iconFor(type),
          autofocus: index == 0,
          onTap: () => ref.read(routeProvider.notifier).go(LibraryRoute(library: library, tab: type)),
        );
      },
    );
  }

  static IconData _iconFor(LibraryTabType type) => switch (type) {
    LibraryTabType.movies => Icons.movie_outlined,
    LibraryTabType.series => Icons.tv_outlined,
    LibraryTabType.music => Icons.music_note_outlined,
    LibraryTabType.audiobooks => Icons.headphones_outlined,
  };
}

class _LibraryCard extends StatefulWidget {
  const _LibraryCard({required this.name, required this.icon, required this.onTap, this.autofocus = false});

  final String name;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<_LibraryCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused ? prairieCardFocusScale : 1.0,
      duration: prairieCardFocusDuration,
      child: Material(
        color: PrairieColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          autofocus: widget.autofocus,
          onFocusChange: (value) => setState(() => _focused = value),
          // The theme's default focusColor (a light amber overlay) would
          // otherwise paint on top of the outline below.
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: AnimatedContainer(
            duration: prairieCardFocusDuration,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _focused ? prairieCardFocusOutline : Colors.transparent, width: prairieCardFocusOutlineWidth),
              boxShadow: _focused ? prairieCardFocusShadow : null,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: PrairieColors.amber, size: 28),
                  const SizedBox(height: 8),
                  Text(widget.name, style: const TextStyle(fontFamily: 'Fraunces', color: PrairieColors.ink, fontSize: 18)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
