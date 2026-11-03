import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ProfileSelectScreen.tsx — PIN-protected profiles require
/// [verifyProfilePin] and store the returned `profileToken` on the session.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key, required this.auth, this.atLaunch = false});

  final AuthTokens auth;

  /// Shown at launch (Profile Selection: Every Time): no Cancel back Home.
  final bool atLaunch;

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  late Future<List<Profile>> _profiles;
  Profile? _pinProfile;
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profiles = listProfiles(
      ref.read(apiClientProvider),
      widget.auth.serverUrl,
      widget.auth.accessToken,
      refreshToken: widget.auth.refreshToken,
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _finish(Profile profile, {String? profileToken}) async {
    final client = ref.read(apiClientProvider);
    final health = await fetchServerHealth(client, widget.auth.serverUrl);
    // Tokens refreshed while this screen was up land on the live session.
    final live = ref.read(sessionProvider);
    final tokens = live != null && live.serverUrl == widget.auth.serverUrl && live.username == widget.auth.username
        ? live.asAuthTokens
        : widget.auth;
    await ref.read(sessionProvider.notifier).set(
      PrairieSession(
        serverUrl: widget.auth.serverUrl,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        username: widget.auth.username,
        profileId: profile.id,
        profileName: profile.name,
        profileAvatarUrl: profile.avatarUrl,
        profileToken: profileToken,
      ),
      fetchedName: health?.serverName ?? '',
    );
    if (!mounted) return;
    await _offerRememberProfile(profile);
    if (!mounted) return;
    ref.read(routeProvider.notifier).go(const HomeRoute());
  }

  /// A new TV's first profile pick asks Apple TV's "Open `<profile>`
  /// automatically?" (Android #762): Ask Every Time or Remember, focus on
  /// Remember, Back answers Ask Every Time. An answer that can't be saved
  /// asks again; after a few tries the TV goes on without one.
  Future<void> _offerRememberProfile(Profile profile) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (!offersRememberProfile(await loadProfileLaunchBehavior(prefs))) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      final remember = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: PrairieColors.bgElevated,
          title: Text(rememberProfileOfferTitle(profile.name), style: const TextStyle(color: PrairieColors.ink)),
          content: Text(
            attempt == 0 ? rememberProfileOfferMessage : "Prairie couldn't save that. Please choose again.",
            style: const TextStyle(color: PrairieColors.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ask Every Time'),
            ),
            ElevatedButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remember'),
            ),
          ],
        ),
      );
      try {
        await saveProfileLaunchBehavior(
          prefs,
          remember == true ? ProfileLaunchBehavior.automatic : ProfileLaunchBehavior.askEveryLaunch,
        );
        return;
      } catch (e) {
        debugPrint('prairie.profiles: could not save Profile Selection: $e');
      }
    }
  }

  Future<void> _select(Profile profile) async {
    setState(() => _error = null);
    if (profile.hasPin ?? false) {
      setState(() {
        _pinProfile = profile;
        _pinController.clear();
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await _finish(profile);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPin() async {
    final pinProfile = _pinProfile;
    if (pinProfile == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await verifyProfilePin(
        ref.read(apiClientProvider),
        widget.auth.serverUrl,
        widget.auth.accessToken,
        pinProfile.id,
        _pinController.text.trim(),
      );
      if (!result.valid || result.profileToken == null || result.profileToken!.isEmpty) {
        throw StateError('Incorrect PIN');
      }
      await _finish(pinProfile, profileToken: result.profileToken);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = ref.read(sessionProvider) != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FutureBuilder<List<Profile>>(
            future: _profiles,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const PrairieLoadingIndicator();
              }
              if (snapshot.hasError) {
                return Text('${snapshot.error}', style: const TextStyle(color: PrairieColors.danger));
              }
              final profiles = snapshot.data ?? [];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('packages/prairie_core/assets/images/prairie-mark.png', width: 64, height: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'WHO\'S WATCHING',
                    style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2),
                  ),
                  const SizedBox(height: 8),
                  const Text('Prairie', style: TextStyle(fontFamily: 'Fraunces', fontSize: 36, color: PrairieColors.ink)),
                  const SizedBox(height: 8),
                  Text(widget.auth.username, style: const TextStyle(color: PrairieColors.muted)),
                  const SizedBox(height: 40),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                    const SizedBox(height: 16),
                  ],
                  if (_pinProfile == null)
                    Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < profiles.length; i++)
                          _ProfileCard(
                            profile: profiles[i],
                            autofocus: i == 0,
                            onTap: _busy ? null : () => _select(profiles[i]),
                          ),
                      ],
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Enter PIN for ${_pinProfile!.name}',
                            style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _pinController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'PIN'),
                            onSubmitted: (_) => _submitPin(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _busy ? null : _submitPin,
                                child: Text(_busy ? 'Checking…' : 'Continue'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _pinProfile = null;
                                        _pinController.clear();
                                        _error = null;
                                      }),
                                child: const Text('Cancel', style: TextStyle(color: PrairieColors.muted)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (hasSession && !widget.atLaunch && _pinProfile == null) ...[
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: () => ref.read(routeProvider.notifier).go(const HomeRoute()),
                      child: const Text('Cancel', style: TextStyle(color: PrairieColors.muted)),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onTap, this.autofocus = false});

  final Profile profile;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(14),
      focusColor: PrairieColors.ring.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: PrairieColors.bgElevated,
              backgroundImage: profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
              child: profile.avatarUrl == null
                  ? Text(
                      profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontFamily: 'Fraunces', fontSize: 32, color: PrairieColors.amber),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(profile.name, style: const TextStyle(color: PrairieColors.ink)),
            if (profile.hasPin ?? false) const Icon(Icons.lock_outline, size: 14, color: PrairieColors.muted),
          ],
        ),
      ),
    );
  }
}
