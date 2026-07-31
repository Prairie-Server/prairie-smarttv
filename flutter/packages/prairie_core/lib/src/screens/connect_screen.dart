import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Mirrors ConnectScreen.tsx: username/password sign-in against [serverUrl],
/// plus a Quick Connect (device-code/QR) panel as an alternative.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key, required this.serverUrl, this.serverName, this.initialUsername});

  final String serverUrl;
  final String? serverName;
  final String? initialUsername;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final _username = TextEditingController(text: widget.initialUsername ?? '');
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String? _error;

  _QuickConnectState _quickConnect = const _QuickConnectIdle();
  bool _pollCancelled = false;

  final _usernameEntryFocus = FocusNode();
  final _passwordEntryFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    // QR / Quick Connect starts by default on login (intentional vs old TS
    // opt-in "Show QR code" gate).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startQuickConnect();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _pollCancelled = true;
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _usernameEntryFocus.dispose();
    _passwordEntryFocus.dispose();
    super.dispose();
  }

  /// A focused `TextField` unconditionally intercepts arrow keys for cursor
  /// movement, before Flutter's own directional-focus-traversal ever sees
  /// them — so D-pad up/down can't move focus out of a field on its own.
  /// `HardwareKeyboard` handlers see every key event regardless of what a
  /// focused widget's `Actions`/`Shortcuts` already did with it, so this
  /// runs independently and drives focus explicitly.
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return false;

    if (identical(focused, _usernameEntryFocus) && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _passwordEntryFocus.requestFocus();
      return true;
    }
    if (identical(focused, _passwordEntryFocus) && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _usernameEntryFocus.requestFocus();
      return true;
    }

    final isField = identical(focused, _usernameFocus) || identical(focused, _passwordFocus);
    if (!isField) return false;

    if (identical(focused, _usernameFocus) && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _passwordFocus.requestFocus();
      return true;
    }
    if (identical(focused, _passwordFocus) && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _usernameFocus.requestFocus();
      return true;
    }
    // Escape the field via geometry-based directional focus for every other
    // direction (down out of the password field, or sideways into the Quick
    // Connect panel) — the field itself only needed to hand off up/down
    // between the two fields above.
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return false;
    return focused.focusInDirection(direction);
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final setup = await fetchSetupStatus(client, widget.serverUrl);
      if (setup.needsSetup) {
        throw StateError(
          'This server has not been set up yet. Open its web UI in a browser on another '
          'device to create the first account, then return here to sign in.',
        );
      }
      final response = await login(
        client,
        widget.serverUrl,
        LoginRequest(username: _username.text.trim(), password: _password.text),
      );
      if (!mounted) return;
      _completeAuth(
        AuthTokens(
          serverUrl: widget.serverUrl,
          accessToken: response.accessToken,
          refreshToken: response.refreshToken,
          username: response.user.username,
        ),
      );
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = networkFailureMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _completeAuth(AuthTokens auth) {
    ref.read(routeProvider.notifier).go(ProfilesRoute(auth: auth));
  }

  Future<void> _startQuickConnect() async {
    _pollCancelled = false;
    setState(() => _quickConnect = const _QuickConnectStarting());
    try {
      final client = ref.read(apiClientProvider);
      final setup = await fetchSetupStatus(client, widget.serverUrl);
      if (setup.needsSetup) {
        throw StateError(
          'This server has not been set up yet. Open its web UI in a browser on another '
          'device to create the first account, then return here to sign in.',
        );
      }
      final identity = ref.read(clientIdentityProvider);
      final session = await startDeviceLogin(
        client,
        widget.serverUrl,
        deviceName: identity.deviceName,
        devicePlatform: identity.devicePlatform,
      );
      if (!mounted) return;
      setState(() => _quickConnect = _QuickConnectWaiting(session));
      _poll(session);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _quickConnect = _QuickConnectFailed(
          e is ApiError ? e.message : networkFailureMessage(e),
        ),
      );
    }
  }

  Future<void> _poll(DeviceLoginStartResponse session) async {
    final client = ref.read(apiClientProvider);
    while (!_pollCancelled && mounted) {
      try {
        final result = await pollDeviceLogin(client, widget.serverUrl, session.deviceCode);
        if (_pollCancelled || !mounted) return;
        if (result.status == 'approved' && result.accessToken != null) {
          _completeAuth(
            AuthTokens(
              serverUrl: widget.serverUrl,
              accessToken: result.accessToken!,
              refreshToken: result.refreshToken,
              username: result.username ?? '',
            ),
          );
          return;
        }
        if (result.status == 'denied') {
          setState(() => _quickConnect = const _QuickConnectFailed('Sign-in was denied on the other device.'));
          return;
        }
        if (result.status == 'expired' || result.status == 'consumed') {
          setState(() => _quickConnect = const _QuickConnectFailed('Quick Connect code expired. Generate a new one.'));
          return;
        }
        final waitSeconds = [2, result.pollAfter, session.interval].where((s) => s > 0).reduce((a, b) => a > b ? a : b);
        await Future<void>.delayed(Duration(seconds: waitSeconds));
      } catch (e) {
        if (_pollCancelled || !mounted) return;
        if (e is ApiError && e.status == 404) {
          setState(() => _quickConnect = const _QuickConnectFailed('Quick Connect code expired. Generate a new one.'));
          return;
        }
        await Future<void>.delayed(Duration(seconds: session.interval > 0 ? session.interval : 3));
      }
    }
  }

  void _stopQuickConnect() {
    _pollCancelled = true;
    setState(() => _quickConnect = const _QuickConnectIdle());
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.serverName?.trim().isNotEmpty ?? false) ? widget.serverName!.trim() : widget.serverUrl;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _credentialsPanel(title)),
                  const SizedBox(width: 32),
                  Expanded(flex: 2, child: _quickConnectPanel()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _credentialsPanel(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('packages/prairie_core/assets/images/prairie-mark.png', width: 64, height: 64),
        const SizedBox(height: 16),
        Text(
          'SIGN IN',
          style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2),
        ),
        const SizedBox(height: 4),
        const Text('Prairie', style: TextStyle(fontFamily: 'Fraunces', fontSize: 40, color: PrairieColors.ink)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(color: PrairieColors.muted),
            children: [const TextSpan(text: 'Sign in to '), TextSpan(text: title, style: const TextStyle(color: PrairieColors.ink))],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Username', style: TextStyle(color: PrairieColors.muted)),
        const SizedBox(height: 4),
        TextField(
          controller: _username,
          focusNode: _usernameFocus,
          textInputAction: TextInputAction.next,
          onEditingComplete: () => _passwordFocus.requestFocus(),
          // Arrow keys move the text cursor while a field is actively
          // editing, so D-pad directional navigation can't escape it, and
          // the platform keyboard's "Next" action isn't guaranteed to be
          // wired up on every TV embedder. This button is a separately
          // focusable widget the remote can always reach and select,
          // regardless of either of those. It also holds the screen's
          // default focus (see below) so landing here doesn't pop the
          // on-screen keyboard until the viewer actually opts into typing.
          decoration: InputDecoration(
            suffixIcon: IconButton(
              focusNode: _usernameEntryFocus,
              autofocus: true,
              icon: const Icon(Icons.keyboard),
              tooltip: 'Enter username',
              onPressed: () => _usernameFocus.requestFocus(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Password', style: TextStyle(color: PrairieColors.muted)),
        const SizedBox(height: 4),
        TextField(
          controller: _password,
          focusNode: _passwordFocus,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            suffixIcon: IconButton(
              focusNode: _passwordEntryFocus,
              icon: const Icon(Icons.keyboard),
              tooltip: 'Enter password',
              onPressed: () => _passwordFocus.requestFocus(),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Flexible(
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: Text(_loading ? 'Signing in…' : 'Sign in'),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: TextButton.icon(
                onPressed: _loading ? null : () => ref.read(routeProvider.notifier).goServers(autoScan: false),
                icon: const Icon(Icons.arrow_back, color: PrairieColors.muted),
                label: const Text('Back to servers', style: TextStyle(color: PrairieColors.muted)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickConnectPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x8C10151C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PrairieColors.amber.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('QUICK CONNECT', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2)),
          const SizedBox(height: 6),
          const Text('Use your phone instead', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
          const SizedBox(height: 8),
          const Text(
            'Scan a code, sign in there, and approve this TV.',
            style: TextStyle(color: PrairieColors.muted),
          ),
          const SizedBox(height: 20),
          switch (_quickConnect) {
            _QuickConnectIdle() => ElevatedButton(onPressed: _startQuickConnect, child: const Text('Show QR code')),
            _QuickConnectStarting() => const Text('Generating code…', style: TextStyle(color: PrairieColors.muted)),
            _QuickConnectWaiting(:final session) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: QrImageView(
                    data: session.verificationUriComplete,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('MATCH', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
                Text(
                  session.matchCode,
                  style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, color: PrairieColors.ink),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _stopQuickConnect, child: const Text('Cancel')),
              ],
            ),
            _QuickConnectFailed(:final message) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: const TextStyle(color: PrairieColors.danger)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _startQuickConnect, child: const Text('Try again')),
              ],
            ),
          },
        ],
      ),
    );
  }
}

sealed class _QuickConnectState {
  const _QuickConnectState();
}

class _QuickConnectIdle extends _QuickConnectState {
  const _QuickConnectIdle();
}

class _QuickConnectStarting extends _QuickConnectState {
  const _QuickConnectStarting();
}

class _QuickConnectWaiting extends _QuickConnectState {
  const _QuickConnectWaiting(this.session);
  final DeviceLoginStartResponse session;
}

class _QuickConnectFailed extends _QuickConnectState {
  const _QuickConnectFailed(this.message);
  final String message;
}
