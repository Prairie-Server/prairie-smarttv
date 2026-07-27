import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import {
  fetchSetupStatus,
  login,
  pollDeviceLogin,
  startDeviceLogin,
  type DeviceLoginStartResponse,
} from "../api/auth";
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

type QuickConnectState =
  | { status: "idle" }
  | { status: "starting" }
  | { status: "waiting"; session: DeviceLoginStartResponse }
  | { status: "failed"; message: string };

function devicePlatformLabel(): string {
  const ua = typeof navigator !== "undefined" ? navigator.userAgent.toLowerCase() : "";
  if (ua.includes("web0s") || ua.includes("webos")) return "webos";
  if (ua.includes("tizen")) return "tizen";
  return "smarttv";
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
  const [quickConnect, setQuickConnect] = useState<QuickConnectState>({ status: "idle" });
  const pollCancelled = useRef(false);

  const trimmedUrl = serverUrl.trim().replace(/\/+$/, "");
  const title = serverName.trim() || trimmedUrl;

  const completeAuth = useCallback(
    (auth: AuthTokens) => {
      onAuthenticated(auth);
    },
    [onAuthenticated],
  );

  const startQuickConnect = useCallback(async () => {
    if (!trimmedUrl) {
      setQuickConnect({ status: "failed", message: "No server selected" });
      return;
    }
    pollCancelled.current = false;
    setQuickConnect({ status: "starting" });
    setError(null);
    try {
      const setup = await fetchSetupStatus(trimmedUrl);
      if (setup.needs_setup) {
        throw new Error(
          "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.",
        );
      }
      const session = await startDeviceLogin(trimmedUrl, {
        device_name: "Prairie Smart TV",
        device_platform: devicePlatformLabel(),
      });
      setQuickConnect({ status: "waiting", session });
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : err instanceof Error
            ? err.message
            : "Could not start Quick Connect";
      setQuickConnect({ status: "failed", message });
    }
  }, [trimmedUrl]);

  useEffect(() => {
    void startQuickConnect();
    return () => {
      pollCancelled.current = true;
    };
  }, [startQuickConnect]);

  useEffect(() => {
    if (quickConnect.status !== "waiting") {
      return;
    }
    const session = quickConnect.session;
    let cancelled = false;
    let timer: number | undefined;

    const poll = async () => {
      if (cancelled || pollCancelled.current) {
        return;
      }
      try {
        const result = await pollDeviceLogin(trimmedUrl, session.device_code);
        if (cancelled || pollCancelled.current) {
          return;
        }
        if (result.status === "approved" && result.access_token && result.user) {
          completeAuth({
            serverUrl: trimmedUrl,
            accessToken: result.access_token,
            refreshToken: result.refresh_token,
            username: result.user.username,
          });
          return;
        }
        if (result.status === "denied") {
          setQuickConnect({ status: "failed", message: "Sign-in was denied on the other device." });
          return;
        }
        if (result.status === "expired" || result.status === "consumed") {
          setQuickConnect({
            status: "failed",
            message: "Quick Connect code expired. Generate a new one.",
          });
          return;
        }
        const waitMs = Math.max(2, result.poll_after || session.interval || 3) * 1000;
        timer = window.setTimeout(() => {
          void poll();
        }, waitMs);
      } catch (err) {
        if (cancelled || pollCancelled.current) {
          return;
        }
        // Transient network errors: keep polling.
        const waitMs = Math.max(2, session.interval || 3) * 1000;
        timer = window.setTimeout(() => {
          void poll();
        }, waitMs);
        if (err instanceof ApiError && err.status === 404) {
          setQuickConnect({
            status: "failed",
            message: "Quick Connect code expired. Generate a new one.",
          });
        }
      }
    };

    void poll();
    return () => {
      cancelled = true;
      if (timer !== undefined) {
        window.clearTimeout(timer);
      }
    };
  }, [quickConnect, trimmedUrl, completeAuth]);

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
      const setup = await fetchSetupStatus(trimmedUrl);
      if (setup.needs_setup) {
        // Do not echo the server URL here — the connect field already shows it,
        // and repeating it in an action prompt aids phishing of mistyped hosts.
        throw new Error(
          "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.",
        );
      }
      const auth = await login(trimmedUrl, { username: username.trim(), password });
      completeAuth({
        serverUrl: trimmedUrl,
        accessToken: auth.access_token,
        refreshToken: auth.refresh_token,
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
      <div className="connect-panel connect-panel--split">
        <div className="connect-credentials">
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

        <aside className="quick-connect-panel" aria-live="polite">
          <p className="eyebrow">Quick Connect</p>
          <h2 className="quick-connect-title">Approve from another device</h2>
          <p className="quick-connect-copy">
            On a signed-in phone or browser, open Settings → Quick Connect and enter this code.
          </p>

          {quickConnect.status === "starting" || quickConnect.status === "idle" ? (
            <p className="quick-connect-status">Generating code…</p>
          ) : null}

          {quickConnect.status === "waiting" ? (
            <div className="quick-connect-codes">
              <div>
                <div className="quick-connect-label">Code</div>
                <div className="quick-connect-code">{quickConnect.session.user_code}</div>
              </div>
              <div>
                <div className="quick-connect-label">Match</div>
                <div className="quick-connect-match">{quickConnect.session.match_code}</div>
              </div>
              <p className="quick-connect-status">Waiting for approval…</p>
            </div>
          ) : null}

          {quickConnect.status === "failed" ? (
            <div className="quick-connect-codes">
              <p className="form-error" role="alert">
                {quickConnect.message}
              </p>
              <FocusButton type="button" onClick={() => void startQuickConnect()}>
                Try Quick Connect again
              </FocusButton>
            </div>
          ) : null}
        </aside>
      </div>
    </section>
  );
}
