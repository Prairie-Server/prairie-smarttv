import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Mirrors ConnectScreen.tsx: username/password sign-in against [serverUrl],
/// plus a Quick Connect (device-code/QR) panel as an alternative.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key, required this.serverUrl, this.serverName, this.initialUsername, this.notice});

  final String serverUrl;
  final String? serverName;
  final String? initialUsername;

  /// Shown under the form on arrival (e.g. a server removal that failed).
  final String? notice;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final _username = TextEditingController(text: widget.initialUsername ?? '');
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  late String? _error = widget.notice;

  /// A sign-in is being handed on to Who's Watching: Change server must not
  /// remove the server under it.
  bool _completing = false;

  /// Change server is running; repeats are ignored.
  bool _leaving = false;

  _QuickConnectState _quickConnect = const _QuickConnectIdle();
  bool _pollCancelled = false;

  /// Bumped per code: a poll or start for an older code stops quietly.
  int _codeGeneration = 0;

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
      setState(() => _error = loginErrorMessage(e));
    } catch (e) {
      setState(() => _error = networkFailureMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _completeAuth(AuthTokens auth) {
    _completing = true;
    _pollCancelled = true;
    ref.read(routeProvider.notifier).go(ProfilesRoute(auth: auth));
  }

  /// "Change server" (Android #759): stop the code and leave. A server this
  /// TV never signed in to is forgotten first, so it doesn't stay listed and
  /// active; the removal lands before the server list opens. Ignored while a
  /// sign-in runs or is being handed on.
  Future<void> _changeServer() async {
    if (_leaving || _loading || _completing) return;
    _leaving = true;
    _pollCancelled = true;
    try {
      final store = ref.read(serverRegistryStoreProvider);
      final next = ServerRegistryStore.forgetIfNeverSignedIn(
        await store.load(),
        widget.serverUrl,
        ref.read(sessionProvider),
      );
      if (next != null) await store.save(next);
    } catch (e) {
      // A failed write keeps the server, as before; leave anyway.
      debugPrint('prairie.connect: could not forget ${widget.serverUrl}: $e');
    }
    if (!mounted) return;
    ref.read(routeProvider.notifier).goServers(autoScan: false);
  }

  /// Starts a sign-in code. [renewed] marks a code that replaced an expired
  /// one: it says "New code" for as long as it shows, as on Apple TV.
  Future<void> _startQuickConnect({bool renewed = false}) async {
    if (_leaving || _completing) return;
    _pollCancelled = false;
    final generation = ++_codeGeneration;
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
      if (!mounted || generation != _codeGeneration || _pollCancelled) return;
      setState(() => _quickConnect = _QuickConnectWaiting(session, renewed: renewed));
      unawaited(_poll(session, generation));
    } catch (e) {
      if (!mounted || generation != _codeGeneration || _pollCancelled) return;
      setState(
        () => _quickConnect = _QuickConnectFailed(
          e is ApiError ? e.message : networkFailureMessage(e),
        ),
      );
    }
  }

  Future<void> _poll(DeviceLoginStartResponse session, int generation) async {
    final client = ref.read(apiClientProvider);
    bool stale() => _pollCancelled || !mounted || generation != _codeGeneration;
    while (!stale()) {
      try {
        final result = await pollDeviceLogin(client, widget.serverUrl, session.deviceCode);
        if (stale()) return;
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
          // The decline may have come from a phone or a browser.
          setState(() => _quickConnect = const _QuickConnectDeclined());
          return;
        }
        if (result.status == 'expired' || result.status == 'consumed') {
          // Apple TV replaces an expired code by itself.
          unawaited(_startQuickConnect(renewed: true));
          return;
        }
        final waitSeconds = [2, result.pollAfter, session.interval].where((s) => s > 0).reduce((a, b) => a > b ? a : b);
        await Future<void>.delayed(Duration(seconds: waitSeconds));
      } catch (e) {
        if (stale()) return;
        if (e is ApiError && e.status == 404) {
          unawaited(_startQuickConnect(renewed: true));
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
                onPressed: _loading ? null : _changeServer,
                icon: const Icon(Icons.arrow_back, color: PrairieColors.muted),
                label: const Text('Change server', style: TextStyle(color: PrairieColors.muted)),
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
            _QuickConnectWaiting(:final session, :final renewed) => Column(
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
                SignInCodeText(session.matchCode),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    signInWaitingStatus(renewed: renewed),
                    style: const TextStyle(color: PrairieColors.muted),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _stopQuickConnect, child: const Text('Cancel')),
              ],
            ),
            _QuickConnectDeclined() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: const Text(signInDeclinedStatus, style: TextStyle(color: PrairieColors.danger)),
                ),
                const SizedBox(height: 4),
                const Text(signInDeclinedLead, style: TextStyle(color: PrairieColors.muted)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  autofocus: true,
                  onPressed: _startQuickConnect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Show a new code'),
                ),
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
  const _QuickConnectWaiting(this.session, {this.renewed = false});
  final DeviceLoginStartResponse session;

  /// This code replaced an expired one.
  final bool renewed;
}

class _QuickConnectDeclined extends _QuickConnectState {
  const _QuickConnectDeclined();
}

class _QuickConnectFailed extends _QuickConnectState {
  const _QuickConnectFailed(this.message);
  final String message;
}

/// Status under a waiting sign-in code, as Apple TV words it
/// (`TVSignInPresentation.statusLine`; Android #754).
String signInWaitingStatus({required bool renewed}) =>
    renewed ? 'New code. Waiting for approval.' : 'Waiting for approval';

/// A declined sign-in (Android #754): the decline may have come from a
/// phone or a browser, and the code is gone.
const signInDeclinedStatus = 'Sign-in was declined.';
const signInDeclinedLead = 'Show a new code to try again.';

/// The password sign-in error: Apple TV's wording for wrong credentials,
/// the server's message otherwise.
String loginErrorMessage(ApiError error) {
  final code = error.code?.toLowerCase();
  if (error.status == 401 || code == 'invalid_credentials' || code == 'unauthorized') {
    return 'Incorrect username or password.';
  }
  return error.message;
}

/// The sign-in code as one large monospaced line, no tiles (Android #656):
/// tabular, slashed-zero digits, an en space between groups, scaled down to
/// fit when a server sends a longer or wider code.
class SignInCodeText extends StatelessWidget {
  const SignInCodeText(this.code, {super.key});

  final String code;

  /// [code] as drawn: trimmed, upper case, spaces widened to en spaces.
  static String display(String code) => code.trim().toUpperCase().replaceAll(' ', '\u2002');

  @override
  Widget build(BuildContext context) {
    final text = code.trim().toUpperCase();
    return Semantics(
      label: 'Code: ${text.split('').where((c) => c != ' ').join(', ')}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          display(code),
          maxLines: 1,
          softWrap: false,
          // A code reads left to right in every locale.
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['DejaVu Sans Mono', 'Courier New', 'Courier'],
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: PrairieColors.ink,
            fontFeatures: [FontFeature.tabularFigures(), FontFeature.slashedZero()],
          ),
        ),
      ),
    );
  }
}
