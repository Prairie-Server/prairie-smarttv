import { apiRequest } from "./client";

export interface LoginRequest {
  username: string;
  password: string;
}

export interface LoginUser {
  id: number;
  username: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  user: LoginUser;
}

export interface Profile {
  id: string;
  name: string;
  is_primary: boolean;
  is_child: boolean;
  has_pin?: boolean;
  avatar_url?: string | null;
}

export interface ProfileListResponse {
  profiles: Profile[];
}

export interface VerifyPinResponse {
  valid: boolean;
  profile_token?: string;
  expires_at?: string;
}

export interface SetupStatusResponse {
  needs_setup: boolean;
}

export interface DeviceLoginStartResponse {
  device_code: string;
  user_code: string;
  match_code: string;
  verification_uri: string;
  verification_uri_complete: string;
  expires_at: string;
  expires_in: number;
  interval: number;
  device_name: string;
  device_platform: string;
}

export interface DeviceLoginPollResponse {
  status: string;
  poll_after: number;
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  user?: LoginUser;
}

export async function fetchSetupStatus(
  serverUrl: string,
  fetchImpl?: typeof fetch,
  timeoutMs?: number,
): Promise<SetupStatusResponse> {
  return apiRequest<SetupStatusResponse>({ serverUrl, fetchImpl, timeoutMs }, "/api/v1/auth/setup");
}

export async function startDeviceLogin(
  serverUrl: string,
  payload: { device_name: string; device_platform: string },
  fetchImpl?: typeof fetch,
): Promise<DeviceLoginStartResponse> {
  return apiRequest<DeviceLoginStartResponse>(
    { serverUrl, fetchImpl },
    "/api/v1/auth/device/start",
    {
      method: "POST",
      body: JSON.stringify(payload),
    },
  );
}

export async function pollDeviceLogin(
  serverUrl: string,
  deviceCode: string,
  fetchImpl?: typeof fetch,
): Promise<DeviceLoginPollResponse> {
  return apiRequest<DeviceLoginPollResponse>({ serverUrl, fetchImpl }, "/api/v1/auth/device/poll", {
    method: "POST",
    body: JSON.stringify({ device_code: deviceCode }),
  });
}

export interface RefreshResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

export async function login(
  serverUrl: string,
  credentials: LoginRequest,
  fetchImpl?: typeof fetch,
): Promise<LoginResponse> {
  return apiRequest<LoginResponse>({ serverUrl, fetchImpl }, "/api/v1/auth/login", {
    method: "POST",
    body: JSON.stringify(credentials),
  });
}

/**
 * Renew access + refresh tokens. Uses raw fetch (not apiRequest) so a failed
 * refresh cannot recurse through the 401→refresh path.
 */
export async function refreshAccessToken(
  serverUrl: string,
  refreshToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<RefreshResponse | null> {
  const base = serverUrl.replace(/\/+$/, "");
  try {
    const response = await fetchImpl(`${base}/api/v1/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
    if (!response.ok) return null;
    return (await response.json()) as RefreshResponse;
  } catch {
    return null;
  }
}

export async function listProfiles(
  serverUrl: string,
  accessToken: string,
  fetchImpl?: typeof fetch,
): Promise<Profile[]> {
  const data = await apiRequest<ProfileListResponse>(
    { serverUrl, accessToken, fetchImpl },
    "/api/v1/profiles",
  );
  return data.profiles ?? [];
}

export async function verifyProfilePin(
  serverUrl: string,
  accessToken: string,
  profileId: string,
  pin: string,
  fetchImpl?: typeof fetch,
): Promise<VerifyPinResponse> {
  return apiRequest<VerifyPinResponse>(
    { serverUrl, accessToken, fetchImpl },
    `/api/v1/profiles/${encodeURIComponent(profileId)}/verify-pin`,
    {
      method: "POST",
      body: JSON.stringify({ pin }),
    },
  );
}

export function pickDefaultProfile(profiles: Profile[]): Profile | null {
  if (!profiles.length) return null;
  return profiles.find((p) => p.is_primary) ?? profiles[0] ?? null;
}
