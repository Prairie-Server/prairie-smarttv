import { useState, type FormEvent } from "react";
import { login, listProfiles, pickDefaultProfile } from "../api/auth";
import { ApiError } from "../api/client";
import { FocusButton } from "../components/FocusButton";
import { saveSession, type PrairieSession } from "../storage/session";

interface ConnectScreenProps {
  onConnected: (session: PrairieSession) => void;
  initialServerUrl?: string;
}

export function ConnectScreen({ onConnected, initialServerUrl = "" }: ConnectScreenProps) {
  const [serverUrl, setServerUrl] = useState(initialServerUrl);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const trimmedUrl = serverUrl.trim().replace(/\/+$/, "");
      if (!trimmedUrl) {
        throw new Error("Enter your Prairie server URL");
      }
      const auth = await login(trimmedUrl, { username: username.trim(), password });
      const profiles = await listProfiles(trimmedUrl, auth.access_token);
      const profile = pickDefaultProfile(profiles);
      if (!profile) {
        throw new Error("No household profile found on this account");
      }
      const session = saveSession({
        serverUrl: trimmedUrl,
        accessToken: auth.access_token,
        refreshToken: auth.refresh_token,
        username: auth.user.username,
        profileId: profile.id,
        profileName: profile.name,
      });
      onConnected(session);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else if (err instanceof Error) {
        setError(err.message);
      } else {
        setError("Could not connect");
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="screen connect-screen">
      <div className="connect-atmosphere" aria-hidden="true" />
      <div className="connect-panel">
        <p className="eyebrow">Smart TV</p>
        <h1 className="brand-hero">Prairie</h1>
        <p className="lede">
          Connect to your Prairie server. Remote-friendly — use the D-pad to move between fields.
        </p>

        <form className="connect-form" onSubmit={handleSubmit}>
          <label className="field">
            <span>Server URL</span>
            <input
              autoFocus
              className="focusable"
              type="url"
              inputMode="url"
              placeholder="https://prairie.example.com"
              value={serverUrl}
              onChange={(e) => setServerUrl(e.target.value)}
              required
            />
          </label>
          <label className="field">
            <span>Username</span>
            <input
              className="focusable"
              type="text"
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
            />
          </label>
          <label className="field">
            <span>Password</span>
            <input
              className="focusable"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </label>

          {error ? <p className="form-error" role="alert">{error}</p> : null}

          <FocusButton className="connect-submit" disabled={busy}>
            {busy ? "Connecting…" : "Connect"}
          </FocusButton>
        </form>
      </div>
    </section>
  );
}
