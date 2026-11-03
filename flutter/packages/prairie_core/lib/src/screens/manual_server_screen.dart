import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ManualServerScreen.tsx: enter a server address directly, with
/// Apple TV's Advanced options for the protocol (Auto, HTTPS, HTTP) and port
/// (Android #758). The address is probed with [checkServerCandidates] so
/// only a Prairie server reaches the login screen.
class ManualServerScreen extends ConsumerStatefulWidget {
  const ManualServerScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<ManualServerScreen> createState() => _ManualServerScreenState();
}

class _ManualServerScreenState extends ConsumerState<ManualServerScreen> {
  late final _controller = TextEditingController(text: widget.initialUrl ?? '');
  final _portController = TextEditingController();
  ServerSetupScheme _scheme = ServerSetupScheme.auto;
  bool _showsAdvanced = false;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_checking) return;
    final List<String> candidates;
    try {
      candidates = buildServerSetupCandidateUrls(_controller.text, scheme: _scheme, port: _portController.text);
    } on ServerSetupValidationException catch (e) {
      // A blank Continue still answers. A port error opens Advanced options
      // so the field at fault is on screen.
      setState(() {
        _error = e.message;
        if (e.isPortError) _showsAdvanced = true;
      });
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final probe = await checkServerCandidates(ref.read(apiClientProvider), candidates);
      if (!mounted) return;
      switch (probe) {
        // The typed address stays as typed: a tried URL carries its port,
        // which would override the Port field on the next try.
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

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final cleartext = serverSetupUsesCleartext(_controller.text, scheme: _scheme, port: _portController.text);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add server'),
        leading: BackButton(
          // Leaving mid-probe would let a late answer open sign-in anyway.
          onPressed: _checking ? null : () => ref.read(routeProvider.notifier).goServers(autoScan: false),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Server address'),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_checking,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(hintText: 'prairie.example.com or 192.168.1.20'),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _continue(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _checking ? null : () => setState(() => _showsAdvanced = !_showsAdvanced),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(_showsAdvanced ? 'Hide advanced options' : 'Advanced options'),
                ),
                if (_showsAdvanced) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final scheme in ServerSetupScheme.values)
                        ChoiceChip(
                          label: Text(scheme.label),
                          selected: _scheme == scheme,
                          onSelected: _checking
                              ? null
                              : (_) {
                                  setState(() => _scheme = scheme);
                                  _clearError();
                                },
                        ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _portController,
                          enabled: !_checking,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Port: auto', prefixIcon: Icon(Icons.tag)),
                          onChanged: (_) => setState(() => _error = null),
                          onSubmitted: (_) => _continue(),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  cleartext
                      ? 'This connection is not encrypted. Use HTTP only on a network you trust.'
                      : 'Secure HTTPS is tried automatically.',
                  style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
                ),
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
