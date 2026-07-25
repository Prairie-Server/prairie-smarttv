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

export async function login(
  serverUrl: string,
  credentials: LoginRequest,
  fetchImpl?: typeof fetch,
): Promise<LoginResponse> {
  return apiRequest<LoginResponse>(
    { serverUrl, fetchImpl },
    "/api/v1/auth/login",
    {
      method: "POST",
      body: JSON.stringify(credentials),
    },
  );
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
