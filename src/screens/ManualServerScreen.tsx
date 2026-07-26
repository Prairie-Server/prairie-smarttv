import { useState, type FormEvent } from "react";
import { FocusButton } from "../components/FocusButton";
import { normalizeServerUrl } from "../storage/persist";

export interface ManualServerScreenProps {
  initialUrl?: string;
  onContinue: (serverUrl: string) => void;
  onBack: () => void;
}

export function ManualServerScreen({
  initialUrl = "",
  onContinue,
  onBack,
}: ManualServerScreenProps) {
  const [serverUrl, setServerUrl] = useState(initialUrl);
  const [error, setError] = useState<string | null>(null);

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    const normalized = normalizeServerUrl(serverUrl);
    if (!normalized) {
      setError("Enter a valid http(s) Prairie server URL");
      return;
    }
    try {
      const parsed = new URL(normalized);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
        setError("Server URL must use http or https");
        return;
      }
      if (parsed.username || parsed.password) {
        setError("Server URL must not include credentials");
        return;
      }
    } catch {
      setError("Enter a valid http(s) Prairie server URL");
      return;
    }
    onContinue(normalized);
  }

  return (
    <section className="screen connect-screen">
      <div className="connect-atmosphere" aria-hidden="true" />
      <div className="connect-panel">
        <img className="connect-mark" src="/prairie-mark.png" alt="" width={72} height={72} />
        <p className="eyebrow">Add server</p>
        <h1 className="brand-hero brand-hero--compact">Prairie</h1>
        <p className="lede">Enter your Prairie server address, then sign in on the next screen.</p>

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

          {error ? (
            <p className="form-error" role="alert">
              {error}
            </p>
          ) : null}

          <div className="connect-actions">
            <FocusButton type="submit">Continue</FocusButton>
            <FocusButton type="button" variant="ghost" onClick={onBack}>
              Back
            </FocusButton>
          </div>
        </form>
      </div>
    </section>
  );
}
