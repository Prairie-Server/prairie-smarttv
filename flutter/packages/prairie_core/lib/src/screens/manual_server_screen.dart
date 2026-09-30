import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ManualServerScreen.tsx: enter a server URL directly. The address
/// is probed with [checkServerCandidates] so only a Prairie server reaches
/// the login screen.
class ManualServerScreen extends ConsumerStatefulWidget {
  const ManualServerScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<ManualServerScreen> createState() => _ManualServerScreenState();
}

class _ManualServerScreenState extends ConsumerState<ManualServerScreen> {
  late final _controller = TextEditingController(text: widget.initialUrl ?? 'http://');
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_checking) return;
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final probe = await checkServerCandidates(ref.read(apiClientProvider), buildManualUrlCandidates(url));
      if (!mounted) return;
      switch (probe) {
        case CheckServerFailure(:final message):
          setState(() => _error = message);
        case CheckServerSuccess(needsSetup: true):
          setState(
            () => _error =
                'This server has not been set up yet. Open its web UI in a browser on another '
                'device to create the first account, then return here to sign in.',
          );
        case CheckServerSuccess(:final serverUrl, :final serverName):
          ref.read(routeProvider.notifier).openLogin(serverUrl, serverName: serverName);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
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
                  enabled: !_checking,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _continue(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _checking ? null : _continue,
                  child: Text(_checking ? 'Checking…' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
