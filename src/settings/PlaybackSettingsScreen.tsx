import { useState } from "react";
import { FocusButton } from "../components/FocusButton";
import { detectPlatform } from "../platform/detect";
import type { PlayerBackendPreference } from "../platform/types";
import {
  loadPlaybackSettings,
  savePlaybackSettings,
  type PlaybackSettings,
} from "./playbackSettings";

interface PlaybackSettingsScreenProps {
  onBack: () => void;
}

const BACKEND_OPTIONS: { value: PlayerBackendPreference; label: string; hint: string }[] = [
  { value: "auto", label: "Auto", hint: "Native on Tizen/webOS, HTML5 elsewhere" },
  { value: "html5", label: "HTML5", hint: "Browser video element (dev + fallback)" },
  { value: "native", label: "Native", hint: "AVPlay on Tizen, Starfish-style on webOS" },
];

export function PlaybackSettingsScreen({ onBack }: PlaybackSettingsScreenProps) {
  const [settings, setSettings] = useState<PlaybackSettings>(() => loadPlaybackSettings());
  const platform = detectPlatform();

  function update(partial: Partial<PlaybackSettings>) {
    setSettings((prev) => {
      const next = { ...prev, ...partial };
      if (partial.forceDirectPlay) next.forceTranscode = false;
      if (partial.forceTranscode) next.forceDirectPlay = false;
      return savePlaybackSettings(next);
    });
  }

  return (
    <section className="screen settings-screen">
      <header className="settings-header">
        <div>
          <p className="eyebrow">Troubleshooting</p>
          <h1>Playback settings</h1>
          <p className="lede">
            Persisted in localStorage (more reliable than cookies on TV webviews). Platform:{" "}
            <strong>{platform}</strong>
          </p>
        </div>
        <FocusButton variant="ghost" onClick={onBack} autoFocus>
          Back
        </FocusButton>
      </header>

      <div className="settings-block">
        <h2>Player backend</h2>
        <div className="option-row" role="radiogroup" aria-label="Player backend">
          {BACKEND_OPTIONS.map((opt) => (
            <button
              key={opt.value}
              type="button"
              role="radio"
              aria-checked={settings.playerBackend === opt.value}
              className={`option-chip focusable ${
                settings.playerBackend === opt.value ? "is-active" : ""
              }`}
              onClick={() => update({ playerBackend: opt.value })}
            >
              <span className="option-chip__label">{opt.label}</span>
              <span className="option-chip__hint">{opt.hint}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="settings-block">
        <h2>Stream method</h2>
        <p className="muted settings-note">
          When neither force is on, Prairie chooses automatically (prefer remux). Toggles send{" "}
          <code>play_method</code> on <code>POST /api/v1/playback/start</code>.
        </p>
        <label className="toggle-row focusable">
          <input
            type="checkbox"
            checked={settings.forceDirectPlay}
            onChange={(e) => update({ forceDirectPlay: e.target.checked })}
          />
          <span>
            <strong>Force Direct Play</strong>
            <span className="toggle-hint">play_method: &quot;direct&quot;</span>
          </span>
        </label>
        <label className="toggle-row focusable">
          <input
            type="checkbox"
            checked={settings.forceTranscode}
            onChange={(e) => update({ forceTranscode: e.target.checked })}
          />
          <span>
            <strong>Force Transcode</strong>
            <span className="toggle-hint">play_method: &quot;transcode&quot;</span>
          </span>
        </label>
      </div>
    </section>
  );
}
