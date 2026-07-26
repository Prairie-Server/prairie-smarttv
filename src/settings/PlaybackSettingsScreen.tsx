import { useState } from "react";
import { FocusButton } from "../components/FocusButton";
import { detectPlatform } from "../platform/detect";
import type { PlayerBackendPreference } from "../platform/types";
import {
  loadPlaybackSettings,
  savePlaybackSettings,
  type PlaybackSettings,
} from "./playbackSettings";
import {
  SUBTITLE_BG_COLOR_CHOICES,
  SUBTITLE_COLOR_CHOICES,
  subtitleAppearanceCssVars,
  type SubtitleAppearance,
  type SubtitleBackgroundStyle,
  type SubtitleFontSize,
  type SubtitlePosition,
} from "./subtitleAppearance";

interface PlaybackSettingsScreenProps {
  onBack: () => void;
  onSwitchServer?: () => void;
}

const BACKEND_OPTIONS: { value: PlayerBackendPreference; label: string; hint: string }[] = [
  { value: "auto", label: "Auto", hint: "Native on Tizen/webOS, HTML5 elsewhere" },
  { value: "html5", label: "HTML5", hint: "Browser video element (dev + fallback)" },
  { value: "native", label: "Native", hint: "AVPlay on Tizen, Starfish-style on webOS" },
];

const SIZE_OPTIONS: SubtitleFontSize[] = ["small", "medium", "large", "xlarge", "xxlarge"];
const STYLE_OPTIONS: SubtitleBackgroundStyle[] = ["none", "outline", "shadow", "box"];
const POSITION_OPTIONS: SubtitlePosition[] = ["bottom", "lower-third", "top"];
const OPACITY_STEPS = [0, 25, 50, 75, 100];

export function PlaybackSettingsScreen({ onBack, onSwitchServer }: PlaybackSettingsScreenProps) {
  const [settings, setSettings] = useState<PlaybackSettings>(() => loadPlaybackSettings());
  const platform = detectPlatform();
  const appearance = settings.subtitleAppearance;
  const previewVars = subtitleAppearanceCssVars(appearance);

  function update(partial: Partial<PlaybackSettings>) {
    setSettings((prev) => {
      const next = { ...prev, ...partial };
      if (partial.forceDirectPlay) next.forceTranscode = false;
      if (partial.forceTranscode) next.forceDirectPlay = false;
      return savePlaybackSettings(next);
    });
  }

  function updateAppearance(partial: Partial<SubtitleAppearance>) {
    update({
      subtitleAppearance: { ...appearance, ...partial },
    });
  }

  return (
    <section className="screen settings-screen">
      <header className="settings-header">
        <div>
          <p className="eyebrow">Preferences</p>
          <h1>Playback settings</h1>
          <p className="lede">
            Persisted in localStorage across app updates. Platform: <strong>{platform}</strong>
          </p>
        </div>
        <FocusButton variant="ghost" onClick={onBack} autoFocus>
          Back
        </FocusButton>
      </header>

      {onSwitchServer ? (
        <div className="settings-block">
          <h2>Servers</h2>
          <p className="muted settings-note">
            Switch between saved Prairie servers or scan the LAN for new ones.
          </p>
          <FocusButton variant="ghost" onClick={onSwitchServer}>
            Servers / Scan LAN
          </FocusButton>
        </div>
      ) : null}

      <div className="settings-block">
        <h2>Subtitles</h2>
        <p className="muted settings-note">
          Text color, size, and background. Applied to HTML5 / webOS <code>::cue</code> and to the
          Tizen AVPlay subtitle overlay (<code>onsubtitlechange</code>).
        </p>

        <p className="eyebrow">Size</p>
        <div className="option-row" role="radiogroup" aria-label="Subtitle size">
          {SIZE_OPTIONS.map((size) => (
            <button
              key={size}
              type="button"
              role="radio"
              aria-checked={appearance.fontSize === size}
              className={`option-chip focusable ${appearance.fontSize === size ? "is-active" : ""}`}
              onClick={() => updateAppearance({ fontSize: size })}
            >
              <span className="option-chip__label">{size}</span>
            </button>
          ))}
        </div>

        <p className="eyebrow">Text color</p>
        <div className="option-row" role="radiogroup" aria-label="Subtitle text color">
          {SUBTITLE_COLOR_CHOICES.map((color) => (
            <button
              key={color.hex}
              type="button"
              role="radio"
              aria-checked={appearance.fontColor === color.hex}
              className={`option-chip focusable ${appearance.fontColor === color.hex ? "is-active" : ""}`}
              onClick={() => updateAppearance({ fontColor: color.hex })}
            >
              <span className="option-chip__label" style={{ color: color.hex }}>
                {color.label}
              </span>
            </button>
          ))}
        </div>

        <p className="eyebrow">Background style</p>
        <div className="option-row" role="radiogroup" aria-label="Subtitle background style">
          {STYLE_OPTIONS.map((style) => (
            <button
              key={style}
              type="button"
              role="radio"
              aria-checked={appearance.backgroundStyle === style}
              className={`option-chip focusable ${appearance.backgroundStyle === style ? "is-active" : ""}`}
              onClick={() => updateAppearance({ backgroundStyle: style })}
            >
              <span className="option-chip__label">{style}</span>
            </button>
          ))}
        </div>

        <p className="eyebrow">Background color</p>
        <div className="option-row" role="radiogroup" aria-label="Subtitle background color">
          {SUBTITLE_BG_COLOR_CHOICES.map((color) => (
            <button
              key={color.hex}
              type="button"
              role="radio"
              aria-checked={appearance.backgroundColor === color.hex}
              className={`option-chip focusable ${appearance.backgroundColor === color.hex ? "is-active" : ""}`}
              onClick={() => updateAppearance({ backgroundColor: color.hex })}
            >
              <span className="option-chip__label">{color.label}</span>
            </button>
          ))}
        </div>

        <p className="eyebrow">Background opacity</p>
        <div className="option-row" role="radiogroup" aria-label="Subtitle background opacity">
          {OPACITY_STEPS.map((step) => (
            <button
              key={step}
              type="button"
              role="radio"
              aria-checked={appearance.backgroundOpacity === step}
              className={`option-chip focusable ${appearance.backgroundOpacity === step ? "is-active" : ""}`}
              onClick={() => updateAppearance({ backgroundOpacity: step })}
            >
              <span className="option-chip__label">{step}%</span>
            </button>
          ))}
        </div>

        <p className="eyebrow">Position</p>
        <div className="option-row" role="radiogroup" aria-label="Subtitle position">
          {POSITION_OPTIONS.map((position) => (
            <button
              key={position}
              type="button"
              role="radio"
              aria-checked={appearance.position === position}
              className={`option-chip focusable ${appearance.position === position ? "is-active" : ""}`}
              onClick={() => updateAppearance({ position })}
            >
              <span className="option-chip__label">{position}</span>
            </button>
          ))}
        </div>

        <label className="toggle-row focusable">
          <input
            type="checkbox"
            checked={appearance.textOutline}
            onChange={(e) => updateAppearance({ textOutline: e.target.checked })}
          />
          <span>
            <strong>Text outline</strong>
            <span className="toggle-hint">Improves contrast on bright scenes</span>
          </span>
        </label>

        <div className="subtitle-preview" aria-hidden="true">
          <span
            className="subtitle-preview__cue"
            style={{
              color: previewVars["--prairie-sub-color"],
              background: previewVars["--prairie-sub-bg"],
              fontSize: previewVars["--prairie-sub-size"],
              textShadow: previewVars["--prairie-sub-shadow"],
            }}
          >
            Sample subtitle text
          </span>
        </div>
      </div>

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
