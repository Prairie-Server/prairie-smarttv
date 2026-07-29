import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ProfileSelectScreen.tsx. PIN-protected profiles
/// (`verifyProfilePin`) aren't wired up yet — selecting a PIN profile logs
/// in without verification for now.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key, required this.auth});

  final AuthTokens auth;

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  late Future<List<Profile>> _profiles;

  @override
  void initState() {
    super.initState();
    _profiles = listProfiles(ref.read(apiClientProvider), widget.auth.serverUrl, widget.auth.accessToken);
  }

  Future<void> _select(Profile profile) async {
    await ref
        .read(sessionProvider.notifier)
        .set(
          PrairieSession(
            serverUrl: widget.auth.serverUrl,
            accessToken: widget.auth.accessToken,
            refreshToken: widget.auth.refreshToken,
            username: widget.auth.username,
            profileId: profile.id,
            profileName: profile.name,
            profileAvatarUrl: profile.avatarUrl,
          ),
        );
    if (!mounted) return;
    ref.read(routeProvider.notifier).go(const HomeRoute());
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
                return const CircularProgressIndicator(color: PrairieColors.amber);
              }
              if (snapshot.hasError) {
                return Text('${snapshot.error}', style: const TextStyle(color: PrairieColors.danger));
              }
              final profiles = snapshot.data ?? [];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('WHO\'S WATCHING', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  const Text('Prairie', style: TextStyle(fontFamily: 'Fraunces', fontSize: 36, color: PrairieColors.ink)),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < profiles.length; i++)
                        _ProfileCard(profile: profiles[i], autofocus: i == 0, onTap: () => _select(profiles[i])),
                    ],
                  ),
                  if (hasSession) ...[
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
  final VoidCallback onTap;
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
