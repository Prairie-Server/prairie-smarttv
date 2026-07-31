import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ManualServerScreen.tsx: enter a server URL directly (no
/// discovery/health probe ported yet — see `checkServer.ts`).
class ManualServerScreen extends ConsumerStatefulWidget {
  const ManualServerScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<ManualServerScreen> createState() => _ManualServerScreenState();
}

class _ManualServerScreenState extends ConsumerState<ManualServerScreen> {
  late final _controller = TextEditingController(text: widget.initialUrl ?? 'http://');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    ref.read(routeProvider.notifier).openLogin(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add server'),
        leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).goServers(autoScan: false)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Server URL'),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _continue(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: _continue, child: const Text('Continue')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
