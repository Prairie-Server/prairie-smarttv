import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors LibrariesScreen.tsx.
class LibrariesScreen extends ConsumerStatefulWidget {
  const LibrariesScreen({super.key});

  @override
  ConsumerState<LibrariesScreen> createState() => _LibrariesScreenState();
}

class _LibrariesScreenState extends ConsumerState<LibrariesScreen> {
  late Future<List<Library>> _libraries;

  @override
  void initState() {
    super.initState();
    _libraries = fetchLibraries(ref.read(apiClientProvider), ref.read(sessionProvider)!);
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      active: ShellTab.libraries,
      body: FutureBuilder<List<Library>>(
        future: _libraries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: PrairieColors.amber));
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}', style: const TextStyle(color: PrairieColors.danger)));
          }
          final libraries = snapshot.data ?? [];
          return GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisExtent: 140, crossAxisSpacing: 16, mainAxisSpacing: 16),
            itemCount: libraries.length,
            itemBuilder: (context, index) {
              final library = libraries[index];
              return Card(
                color: PrairieColors.bgElevated,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => ref.read(routeProvider.notifier).go(LibraryRoute(library: library)),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.video_library_outlined, color: PrairieColors.amber, size: 28),
                        const SizedBox(height: 8),
                        Text(library.name, style: const TextStyle(fontFamily: 'Fraunces', color: PrairieColors.ink, fontSize: 18)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
