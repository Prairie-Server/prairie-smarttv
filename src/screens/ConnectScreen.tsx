import { ArrowLeft, LogIn, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import {
  fetchSetupStatus,
  login,
  pollDeviceLogin,
  startDeviceLogin,
  type DeviceLoginStartResponse,
} from "../api/auth";
import { networkFailureMessage } from "../api/checkServer";
import { ApiError } from "../api/client";
import { FocusButton } from "../components/FocusButton";
import { QrCode } from "../components/QrCode";
import { validateServerUrl } from "../storage/serverUrl";
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
  const [showTextFallback, setShowTextFallback] = useState(false);
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
    const validated = validateServerUrl(trimmedUrl);
    if (!validated.ok) {
      setQuickConnect({ status: "failed", message: validated.message });
      return;
    }
    pollCancelled.current = false;
    setShowTextFallback(false);
    setQuickConnect({ status: "starting" });
    setError(null);
    try {
      const setup = await fetchSetupStatus(validated.url);
      if (setup.needs_setup) {
        throw new Error(
          "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.",
        );
      }
      const session = await startDeviceLogin(validated.url, {
        device_name: "Prairie Smart TV",
        device_platform: devicePlatformLabel(),
      });
      setQuickConnect({ status: "waiting", session });
    } catch (err) {
      const message =
        err instanceof ApiError && err.code !== "timeout"
          ? err.message || "Could not start Quick Connect"
          : networkFailureMessage(err);
      setQuickConnect({ status: "failed", message });
    }
  }, [trimmedUrl]);

  const stopQuickConnect = useCallback(() => {
    pollCancelled.current = true;
    setQuickConnect({ status: "idle" });
    setShowTextFallback(false);
  }, []);

  useEffect(() => {
    return () => {
      pollCancelled.current = true;
    };
  }, []);

  useEffect(() => {
    if (quickConnect.status !== "waiting") {
      return;
    }
    const session = quickConnect.session;
    const validated = validateServerUrl(trimmedUrl);
    const pollUrl = validated.ok ? validated.url : trimmedUrl;
    let cancelled = false;
    let timer: number | undefined;

    const poll = async () => {
      if (cancelled || pollCancelled.current) {
        return;
      }
      try {
        const result = await pollDeviceLogin(pollUrl, session.device_code);
        if (cancelled || pollCancelled.current) {
          return;
        }
        if (result.status === "approved" && result.access_token && result.user) {
          completeAuth({
            serverUrl: pollUrl,
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
        if (err instanceof ApiError && err.status === 404) {
          setQuickConnect({
            status: "failed",
            message: "Quick Connect code expired. Generate a new one.",
          });
          return;
        }
        // Transient network errors: keep polling.
        const waitMs = Math.max(2, session.interval || 3) * 1000;
        timer = window.setTimeout(() => {
          void poll();
        }, waitMs);
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
      if (!trimmedUrl) throw new Error("No server selected");

      const validated = validateServerUrl(trimmedUrl);
      if (!validated.ok) throw new Error(validated.message);

      const setup = await fetchSetupStatus(validated.url);
      if (setup.needs_setup) {
        // Do not echo the server URL here — the connect field already shows it,
        // and repeating it in an action prompt aids phishing of mistyped hosts.
        throw new Error(
          "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.",
        );
      }
      const auth = await login(validated.url, { username: username.trim(), password });
      completeAuth({
        serverUrl: validated.url,
        accessToken: auth.access_token,
        refreshToken: auth.refresh_token,
        username: auth.user.username,
      });
    } catch (err) {
      // Prefer ApiError bodies for auth/setup HTTP failures; remap transport
      // errors ("Failed to fetch") so wrong http/https is actionable on TV.
      if (err instanceof ApiError && err.code !== "timeout") {
        setError(err.message || "Could not connect");
      } else {
        setError(networkFailureMessage(err));
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
              <FocusButton
                type="submit"
                className="connect-submit"
                icon={<LogIn />}
                disabled={busy}
              >
                {busy ? "Signing in…" : "Sign in"}
              </FocusButton>
              <FocusButton
                type="button"
                variant="ghost"
                icon={<ArrowLeft />}
                disabled={busy}
                onClick={onBack}
              >
                Back to servers
              </FocusButton>
            </div>
          </form>
        </div>

        <aside className="quick-connect-panel" aria-live="polite">
          <p className="eyebrow">Quick Connect</p>
          <h2 className="quick-connect-title">Use your phone instead</h2>
          <p className="quick-connect-copy">
            Scan a code, sign in there, and approve this TV — or enter the text code in Settings →
            Quick Connect.
          </p>

          {quickConnect.status === "idle" ? (
            <div className="quick-connect-codes">
              <FocusButton type="button" onClick={() => void startQuickConnect()}>
                Show QR code
              </FocusButton>
            </div>
          ) : null}

          {quickConnect.status === "starting" ? (
            <p className="quick-connect-status">Generating code…</p>
          ) : null}

          {quickConnect.status === "waiting" ? (
            <div className="quick-connect-codes">
              <QrCode value={quickConnect.session.verification_uri_complete} size={188} />
              <div>
                <div className="quick-connect-label">Match</div>
                <div className="quick-connect-match">{quickConnect.session.match_code}</div>
              </div>
              {showTextFallback ? (
                <div>
                  <div className="quick-connect-label">Code</div>
                  <div className="quick-connect-code">{quickConnect.session.user_code}</div>
                  <p className="quick-connect-status">{quickConnect.session.verification_uri}</p>
                </div>
              ) : (
                <FocusButton
                  type="button"
                  variant="ghost"
                  onClick={() => setShowTextFallback(true)}
                >
                  Can&apos;t scan the QR code?
                </FocusButton>
              )}
              <p className="quick-connect-status">Waiting for approval…</p>
              <FocusButton type="button" variant="ghost" onClick={stopQuickConnect}>
                Start over
              </FocusButton>
            </div>
          ) : null}

          {quickConnect.status === "failed" ? (
            <div className="quick-connect-codes">
              <p className="form-error" role="alert">
                {quickConnect.message}
              </p>
              <FocusButton
                type="button"
                icon={<RefreshCw />}
                onClick={() => void startQuickConnect()}
              >
                Try Quick Connect again
              </FocusButton>
            </div>
          ) : null}
        </aside>
      </div>
    </section>
  );
}
