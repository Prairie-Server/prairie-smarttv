/// Tokens returned from `/api/v1/auth/login`, before a profile is chosen.
///
/// Mirrors `AuthTokens` from src/api/auth.ts / src/storage/session.ts.
class AuthTokens {
  const AuthTokens({
    required this.serverUrl,
    required this.accessToken,
    this.refreshToken,
    required this.username,
  });

  final String serverUrl;
  final String accessToken;
  final String? refreshToken;
  final String username;
}

/// A fully-established session: server + auth + selected profile.
///
/// Mirrors `PrairieSession` from src/storage/session.ts.
class PrairieSession {
  const PrairieSession({
    required this.serverUrl,
    required this.accessToken,
    this.refreshToken,
    required this.username,
    required this.profileId,
    this.profileName,
    this.profileAvatarUrl,
    this.profileToken,
  });

  final String serverUrl;
  final String accessToken;
  final String? refreshToken;
  final String username;
  final String profileId;
  final String? profileName;
  final String? profileAvatarUrl;
  final String? profileToken;

  AuthTokens get asAuthTokens => AuthTokens(
    serverUrl: serverUrl,
    accessToken: accessToken,
    refreshToken: refreshToken,
    username: username,
  );

  PrairieSession copyWith({
    String? serverUrl,
    String? accessToken,
    String? refreshToken,
    String? username,
    String? profileId,
    String? profileName,
    String? profileAvatarUrl,
    String? profileToken,
    bool clearProfileToken = false,
  }) => PrairieSession(
    serverUrl: serverUrl ?? this.serverUrl,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    username: username ?? this.username,
    profileId: profileId ?? this.profileId,
    profileName: profileName ?? this.profileName,
    profileAvatarUrl: profileAvatarUrl ?? this.profileAvatarUrl,
    profileToken: clearProfileToken ? null : (profileToken ?? this.profileToken),
  );
}
