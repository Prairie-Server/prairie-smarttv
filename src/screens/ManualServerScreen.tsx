import { useState, type FormEvent } from "react";
import { buildManualUrlCandidates, checkServerCandidates } from "../api/checkServer";
import { FocusButton } from "../components/FocusButton";
<<<<<<< HEAD
=======
import { validateServerUrl } from "../storage/serverUrl";
>>>>>>> 5c77d98 (fix(security): keep session tokens out of localStorage and restrict public HTTP)

export interface ManualServerScreenProps {
  initialUrl?: string;
  onContinue: (serverUrl: string, options?: { serverName?: string }) => void;
  onBack: () => void;
}

export function ManualServerScreen({
  initialUrl = "",
  onContinue,
  onBack,
}: ManualServerScreenProps) {
  const [serverUrl, setServerUrl] = useState(initialUrl);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setError(null);
<<<<<<< HEAD

    const candidates = buildManualUrlCandidates(serverUrl);
    if (!candidates.length) {
      setError("Enter a valid Prairie server address");
      return;
    }

    // Validate any fully-qualified candidate before probing.
    for (const candidate of candidates) {
      try {
        const parsed = new URL(candidate);
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
          setError("Server URL must use http or https");
          return;
        }
        if (parsed.username || parsed.password) {
          setError("Server URL must not include credentials");
          return;
        }
      } catch {
        setError("Enter a valid Prairie server address");
        return;
      }
    }

    setBusy(true);
    try {
      const result = await checkServerCandidates(candidates);
      if (!result.ok) {
        setError(result.message);
        return;
      }
      if (result.needsSetup) {
        setError(
          "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.",
        );
        return;
      }
      onContinue(result.serverUrl, { serverName: result.serverName });
    } finally {
      setBusy(false);
    }
=======
    const validated = validateServerUrl(serverUrl);
    if (!validated.ok) {
      setError(validated.message);
      return;
    }
    onContinue(validated.url);
>>>>>>> 5c77d98 (fix(security): keep session tokens out of localStorage and restrict public HTTP)
  }

  return (
    <section className="screen connect-screen">
      <div className="connect-atmosphere" aria-hidden="true" />
      <div className="connect-panel">
        <img className="connect-mark" src="/prairie-mark.png" alt="" width={72} height={72} />
        <p className="eyebrow">Add server</p>
        <h1 className="brand-hero brand-hero--compact">Prairie</h1>
        <p className="lede">
          Enter your Prairie server address. We check it is reachable before signing in.
        </p>

        <form className="connect-form" onSubmit={(e) => void handleSubmit(e)}>
          <label className="field">
            <span>Server URL</span>
            <input
              autoFocus
              className="focusable"
              type="url"
              inputMode="url"
              placeholder="192.168.1.10:8080"
              value={serverUrl}
              onChange={(e) => setServerUrl(e.target.value)}
              required
              disabled={busy}
            />
          </label>

          {error ? (
            <p className="form-error" role="alert">
              {error}
            </p>
          ) : null}

          <div className="connect-actions">
            <FocusButton type="submit" disabled={busy}>
              {busy ? "Checking…" : "Continue"}
            </FocusButton>
            <FocusButton type="button" variant="ghost" disabled={busy} onClick={onBack}>
              Back
            </FocusButton>
          </div>
        </form>
      </div>
    </section>
  );
}
