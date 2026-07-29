import 'api_client.dart';

/// Mirrors `LoginRequest`/`LoginResponse`/`LoginUser` from src/api/auth.ts.
class LoginRequest {
  const LoginRequest({required this.username, required this.password});
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {'username': username, 'password': password};
}

class LoginUser {
  const LoginUser({required this.id, required this.username});
  final int id;
  final String username;

  factory LoginUser.fromJson(Map<String, dynamic> json) =>
      LoginUser(id: json['id'] as int, username: json['username'] as String);
}

class LoginResponse {
  const LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final LoginUser user;

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresIn: json['expires_in'] as int,
    user: LoginUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}

/// Mirrors `login` from src/api/auth.ts.
Future<LoginResponse> login(ApiClient client, String serverUrl, LoginRequest credentials) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl),
    '/api/v1/auth/login',
    method: 'POST',
    body: credentials.toJson(),
  );
  return LoginResponse.fromJson(json);
}

/// Mirrors `Profile` from src/api/auth.ts.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.isChild,
    this.hasPin,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final bool isPrimary;
  final bool isChild;
  final bool? hasPin;
  final String? avatarUrl;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    name: json['name'] as String,
    isPrimary: json['is_primary'] as bool? ?? false,
    isChild: json['is_child'] as bool? ?? false,
    hasPin: json['has_pin'] as bool?,
    avatarUrl: json['avatar_url'] as String?,
  );
}

/// Mirrors `listProfiles` from src/api/auth.ts.
Future<List<Profile>> listProfiles(ApiClient client, String serverUrl, String accessToken) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl, accessToken: accessToken),
    '/api/v1/profiles',
  );
  final profiles = json['profiles'] as List<dynamic>?;
  return profiles?.map((p) => Profile.fromJson(p as Map<String, dynamic>)).toList() ?? [];
}

/// Mirrors `SetupStatusResponse` + `fetchSetupStatus` from src/api/auth.ts.
class SetupStatusResponse {
  const SetupStatusResponse({required this.needsSetup});
  final bool needsSetup;

  factory SetupStatusResponse.fromJson(Map<String, dynamic> json) =>
      SetupStatusResponse(needsSetup: json['needs_setup'] as bool? ?? false);
}

Future<SetupStatusResponse> fetchSetupStatus(
  ApiClient client,
  String serverUrl, {
  Duration? timeout,
}) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl, timeout: timeout ?? const Duration(seconds: 30)),
    '/api/v1/auth/setup',
  );
  return SetupStatusResponse.fromJson(json);
}

/// Mirrors `DeviceLoginStartResponse` from src/api/auth.ts — the "Quick
/// Connect" QR flow.
class DeviceLoginStartResponse {
  const DeviceLoginStartResponse({
    required this.deviceCode,
    required this.userCode,
    required this.matchCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresAt,
    required this.expiresIn,
    required this.interval,
    required this.deviceName,
    required this.devicePlatform,
  });

  final String deviceCode;
  final String userCode;
  final String matchCode;
  final String verificationUri;
  final String verificationUriComplete;
  final String expiresAt;
  final int expiresIn;
  final int interval;
  final String deviceName;
  final String devicePlatform;

  factory DeviceLoginStartResponse.fromJson(Map<String, dynamic> json) => DeviceLoginStartResponse(
    deviceCode: json['device_code'] as String,
    userCode: json['user_code'] as String,
    matchCode: json['match_code'] as String,
    verificationUri: json['verification_uri'] as String,
    verificationUriComplete: json['verification_uri_complete'] as String,
    expiresAt: json['expires_at'] as String,
    expiresIn: json['expires_in'] as int,
    interval: json['interval'] as int,
    deviceName: json['device_name'] as String,
    devicePlatform: json['device_platform'] as String,
  );
}

/// Mirrors `DeviceLoginPollResponse` from src/api/auth.ts.
class DeviceLoginPollResponse {
  const DeviceLoginPollResponse({
    required this.status,
    required this.pollAfter,
    this.accessToken,
    this.refreshToken,
    this.username,
  });

  final String status;
  final int pollAfter;
  final String? accessToken;
  final String? refreshToken;
  final String? username;

  factory DeviceLoginPollResponse.fromJson(Map<String, dynamic> json) => DeviceLoginPollResponse(
    status: json['status'] as String,
    pollAfter: json['poll_after'] as int? ?? 0,
    accessToken: json['access_token'] as String?,
    refreshToken: json['refresh_token'] as String?,
    username: (json['user'] as Map<String, dynamic>?)?['username'] as String?,
  );
}

/// Mirrors `startDeviceLogin` from src/api/auth.ts.
Future<DeviceLoginStartResponse> startDeviceLogin(
  ApiClient client,
  String serverUrl, {
  required String deviceName,
  required String devicePlatform,
}) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl),
    '/api/v1/auth/device/start',
    method: 'POST',
    body: {'device_name': deviceName, 'device_platform': devicePlatform},
  );
  return DeviceLoginStartResponse.fromJson(json);
}

/// Mirrors `pollDeviceLogin` from src/api/auth.ts.
Future<DeviceLoginPollResponse> pollDeviceLogin(ApiClient client, String serverUrl, String deviceCode) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(serverUrl: serverUrl),
    '/api/v1/auth/device/poll',
    method: 'POST',
    body: {'device_code': deviceCode},
  );
  return DeviceLoginPollResponse.fromJson(json);
}
