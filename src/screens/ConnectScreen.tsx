import { useState, type FormEvent } from "react";
import { login } from "../api/auth";
import { ApiError } from "../api/client";
import { FocusButton } from "../components/FocusButton";
import type { AuthTokens } from "../storage/session";

interface ConnectScreenProps {
  /** Server already chosen on the launch list / manual URL step. */
  serverUrl: string;
  serverName?: string;
  initialUsername?: string;
  onAuthenticated: (auth: AuthTokens) => void;
  onBack: () => void;
}

export function ConnectScreen({
  serverUrl,
  serverName = "",
  initialUsername = "",
  onAuthenticated,
  onBack,
}: ConnectScreenProps) {
  const [username, setUsername] = useState(initialUsername);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const trimmedUrl = serverUrl.trim().replace(/\/+$/, "");
  const title = serverName.trim() || trimmedUrl;

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      if (!trimmedUrl) {
        throw new Error("No server selected");
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
        <img className="connect-mark" src="/prairie-mark.png" alt="" width={72} height={72} />
        <p className="eyebrow">Sign in</p>
        <h1 className="brand-hero brand-hero--compact">Prairie</h1>
        <p className="lede">
          Sign in to <strong className="connect-server-name">{title}</strong>
        </p>

        <form className="connect-form" onSubmit={handleSubmit}>
          <label className="field">
            <span>Username</span>
            <input
              autoFocus
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

          <div className="connect-actions">
            <FocusButton type="submit" className="connect-submit" disabled={busy}>
              {busy ? "Signing in…" : "Sign in"}
            </FocusButton>
            <FocusButton type="button" variant="ghost" disabled={busy} onClick={onBack}>
              Back to servers
            </FocusButton>
          </div>
        </form>
      </div>
    </section>
  );
}
