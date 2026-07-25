import { useEffect, useState, type FormEvent } from "react";
import {
  listProfiles,
  verifyProfilePin,
  type Profile,
} from "../api/auth";
import { ApiError } from "../api/client";
import { FocusButton } from "../components/FocusButton";
import {
  saveSession,
  type AuthTokens,
  type PrairieSession,
} from "../storage/session";

interface ProfileSelectScreenProps {
  auth: AuthTokens;
  onSelected: (session: PrairieSession) => void;
  onCancel: () => void;
}

export function ProfileSelectScreen({
  auth,
  onSelected,
  onCancel,
}: ProfileSelectScreenProps) {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pinProfile, setPinProfile] = useState<Profile | null>(null);
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const list = await listProfiles(auth.serverUrl, auth.accessToken);
        if (!cancelled) setProfiles(list);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load profiles");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [auth]);

  async function finish(profile: Profile, profileToken?: string) {
    const session = saveSession({
      ...auth,
      profileId: profile.id,
      profileName: profile.name,
      profileToken,
    });
    onSelected(session);
  }

  async function selectProfile(profile: Profile) {
    setError(null);
    if (profile.has_pin) {
      setPinProfile(profile);
      setPin("");
      return;
    }
    setBusy(true);
    try {
      await finish(profile);
    } finally {
      setBusy(false);
    }
  }

  async function submitPin(event: FormEvent) {
    event.preventDefault();
    if (!pinProfile) return;
    setBusy(true);
    setError(null);
    try {
      const result = await verifyProfilePin(
        auth.serverUrl,
        auth.accessToken,
        pinProfile.id,
        pin.trim(),
      );
      if (!result.valid || !result.profile_token) {
        throw new Error("Incorrect PIN");
      }
      await finish(pinProfile, result.profile_token);
    } catch (err) {
      setError(err instanceof ApiError || err instanceof Error ? err.message : "PIN failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="screen profile-screen">
      <header className="browse-header">
        <div>
          <p className="eyebrow">Who’s watching</p>
          <h1 className="browse-title">Choose a profile</h1>
          <p className="muted">{auth.username}</p>
        </div>
        <FocusButton variant="ghost" onClick={onCancel}>
          Back
        </FocusButton>
      </header>

      {loading ? <p className="muted">Loading profiles…</p> : null}
      {error ? <p className="form-error" role="alert">{error}</p> : null}

      {!pinProfile ? (
        <div className="profile-grid">
          {profiles.map((profile, index) => (
            <button
              key={profile.id}
              type="button"
              className="profile-card"
              autoFocus={index === 0}
              disabled={busy}
              onClick={() => void selectProfile(profile)}
            >
              <span className="profile-card__avatar" aria-hidden="true">
                {profile.name.slice(0, 1).toUpperCase()}
              </span>
              <span className="profile-card__name">{profile.name}</span>
              <span className="profile-card__meta muted">
                {profile.is_primary ? "Primary" : profile.is_child ? "Child" : "Profile"}
                {profile.has_pin ? " · PIN" : ""}
              </span>
            </button>
          ))}
        </div>
      ) : (
        <form className="pin-form" onSubmit={(e) => void submitPin(e)}>
          <h2>Enter PIN for {pinProfile.name}</h2>
          <label className="field">
            <span>PIN</span>
            <input
              className="focusable"
              type="password"
              inputMode="numeric"
              autoFocus
              value={pin}
              onChange={(e) => setPin(e.target.value)}
              required
            />
          </label>
          <div className="row-actions">
            <FocusButton type="submit" disabled={busy}>
              {busy ? "Checking…" : "Continue"}
            </FocusButton>
            <FocusButton
              variant="ghost"
              onClick={() => {
                setPinProfile(null);
                setPin("");
              }}
            >
              Cancel
            </FocusButton>
          </div>
        </form>
      )}
    </section>
  );
}
