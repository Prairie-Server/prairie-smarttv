import { useState, type FormEvent } from "react";
import { login } from "../api/auth";
import { ApiError } from "../api/client";
import { FocusButton } from "../components/FocusButton";
import type { AuthTokens } from "../storage/session";

interface ConnectScreenProps {
  onAuthenticated: (auth: AuthTokens) => void;
  initialServerUrl?: string;
}

export function ConnectScreen({ onAuthenticated, initialServerUrl = "" }: ConnectScreenProps) {
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
      let parsed: URL;
      try {
        parsed = new URL(trimmedUrl);
      } catch {
        throw new Error("Server URL must be a valid http(s) address");
      }
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
        throw new Error("Server URL must use http or https");
      }
      if (parsed.username || parsed.password) {
        throw new Error("Server URL must not include credentials");
      }
      const auth = await login(trimmedUrl, { username: username.trim(), password });
      // Do not persist refresh_token until client-side refresh is implemented.
      onAuthenticated({
        serverUrl: trimmedUrl,
        accessToken: auth.access_token,
        username: auth.user.username,
      });
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

          {error ? (
            <p className="form-error" role="alert">
              {error}
            </p>
          ) : null}

          <FocusButton type="submit" className="connect-submit" disabled={busy}>
            {busy ? "Connecting…" : "Connect"}
          </FocusButton>
        </form>
      </div>
    </section>
  );
}
