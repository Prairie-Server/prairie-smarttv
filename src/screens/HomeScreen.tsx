import { useState, type FormEvent } from "react";
import { FocusButton } from "../components/FocusButton";
import type { PrairieSession } from "../storage/session";

interface HomeScreenProps {
  session: PrairieSession;
  onPlay: (fileId: number) => void;
  onOpenSettings: () => void;
  onDisconnect: () => void;
}

export function HomeScreen({
  session,
  onPlay,
  onOpenSettings,
  onDisconnect,
}: HomeScreenProps) {
  const [fileId, setFileId] = useState("");
  const [error, setError] = useState<string | null>(null);

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    const parsed = Number.parseInt(fileId.trim(), 10);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      setError("Enter a valid media file ID");
      return;
    }
    setError(null);
    onPlay(parsed);
  }

  return (
    <section className="screen home-screen">
      <header className="home-header">
        <div>
          <p className="eyebrow">Signed in</p>
          <h1 className="home-title">Prairie</h1>
          <p className="muted">
            {session.username}
            {session.profileName ? ` · ${session.profileName}` : ""}
          </p>
        </div>
        <div className="home-actions">
          <FocusButton variant="ghost" onClick={onOpenSettings}>
            Playback settings
          </FocusButton>
          <FocusButton variant="ghost" onClick={onDisconnect}>
            Disconnect
          </FocusButton>
        </div>
      </header>

      <div className="home-launcher">
        <h2>Debug launcher</h2>
        <p className="lede">
          Foundation slice — enter a media <code>file_id</code> from your Prairie library to start
          playback. Full browse comes later.
        </p>
        <form className="launcher-form" onSubmit={handleSubmit}>
          <label className="field">
            <span>Media file ID</span>
            <input
              className="focusable"
              type="number"
              min={1}
              inputMode="numeric"
              placeholder="e.g. 42"
              value={fileId}
              onChange={(e) => setFileId(e.target.value)}
              autoFocus
            />
          </label>
          {error ? <p className="form-error" role="alert">{error}</p> : null}
          <FocusButton type="submit">Play</FocusButton>
        </form>
        <p className="hint muted">Server: {session.serverUrl}</p>
      </div>
    </section>
  );
}
