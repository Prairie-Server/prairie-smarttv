import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ProfileSelectScreen.tsx — PIN-protected profiles require
/// [verifyProfilePin] and store the returned `profileToken` on the session.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key, required this.auth});

  final AuthTokens auth;

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
    _profiles = listProfiles(ref.read(apiClientProvider), widget.auth.serverUrl, widget.auth.accessToken);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _finish(Profile profile, {String? profileToken}) async {
    final client = ref.read(apiClientProvider);
    final health = await fetchServerHealth(client, widget.auth.serverUrl);
    await ref.read(sessionProvider.notifier).set(
      PrairieSession(
        serverUrl: widget.auth.serverUrl,
        accessToken: widget.auth.accessToken,
        refreshToken: widget.auth.refreshToken,
        username: widget.auth.username,
        profileId: profile.id,
        profileName: profile.name,
        profileAvatarUrl: profile.avatarUrl,
        profileToken: profileToken,
      ),
      fetchedName: health?.serverName ?? '',
    );
    if (!mounted) return;
    ref.read(routeProvider.notifier).go(const HomeRoute());
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
                  if (hasSession && _pinProfile == null) ...[
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
