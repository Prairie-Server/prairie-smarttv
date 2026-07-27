import { useState, type FormEvent } from "react";
import { buildManualUrlCandidates, checkServerCandidates } from "../api/checkServer";
import { FocusButton } from "../components/FocusButton";
import { validateServerUrl } from "../storage/serverUrl";

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

    const candidates = buildManualUrlCandidates(serverUrl);
    if (!candidates.length) {
      setError("Enter a valid Prairie server address");
      return;
    }

    // Validate any fully-qualified candidate before probing (incl. cleartext policy).
    const allowed: string[] = [];
    for (const candidate of candidates) {
      const validated = validateServerUrl(candidate);
      if (!validated.ok) {
        // Keep the first actionable policy error for the user.
        if (allowed.length === 0) {
          setError(validated.message);
        }
        continue;
      }
      allowed.push(validated.url);
    }
    if (!allowed.length) {
      return;
    }

    setBusy(true);
    try {
      const result = await checkServerCandidates(allowed);
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
