import { ArrowLeft, FileText, Radar } from "lucide-react";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { FocusButton } from "../components/FocusButton";
import { SettingsChoiceRow, SettingsToggleRow } from "../components/SettingsRows";
import { isBackKey } from "../focus/spatialFocus";
import { detectPlatform } from "../platform/detect";
import type { PlayerBackendPreference } from "../platform/types";
import {
  changelogUrlOrNull,
  latestVersionLabel,
  statusLabel,
  type AppUpdateStatus,
} from "../update/appUpdateStatus";
import { checkAppUpdate } from "../update/checkAppUpdate";
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

type StreamMethodChoice = "auto" | "direct" | "transcode";
type SettingsSectionId = "servers" | "playback" | "subtitles" | "about";

const BACKEND_OPTIONS: { value: PlayerBackendPreference; label: string }[] = [
  { value: "auto", label: "Auto" },
  { value: "html5", label: "HTML5" },
  { value: "native", label: "Native" },
];

const SIZE_OPTIONS: Array<{ value: SubtitleFontSize; label: string }> = [
  { value: "small", label: "Small" },
  { value: "medium", label: "Medium" },
  { value: "large", label: "Large" },
  { value: "xlarge", label: "XL" },
  { value: "xxlarge", label: "XXL" },
];

const STYLE_OPTIONS: Array<{ value: SubtitleBackgroundStyle; label: string }> = [
  { value: "none", label: "None" },
  { value: "outline", label: "Outline" },
  { value: "shadow", label: "Shadow" },
  { value: "box", label: "Box" },
];

const POSITION_OPTIONS: Array<{ value: SubtitlePosition; label: string }> = [
  { value: "bottom", label: "Bottom" },
  { value: "lower-third", label: "Lower third" },
  { value: "top", label: "Top" },
];

const OPACITY_OPTIONS = [
  { value: "0", label: "0%" },
  { value: "25", label: "25%" },
  { value: "50", label: "50%" },
  { value: "75", label: "75%" },
  { value: "100", label: "100%" },
];

const STREAM_OPTIONS: Array<{ value: StreamMethodChoice; label: string }> = [
  { value: "auto", label: "Auto" },
  { value: "direct", label: "Direct play" },
  { value: "transcode", label: "Transcode" },
];

function streamMethodFromSettings(settings: PlaybackSettings): StreamMethodChoice {
  if (settings.forceDirectPlay) return "direct";
  if (settings.forceTranscode) return "transcode";
  return "auto";
}

export function PlaybackSettingsScreen({ onBack, onSwitchServer }: PlaybackSettingsScreenProps) {
  const sections = useMemo(() => {
    const items: Array<{ id: SettingsSectionId; label: string }> = [];
    if (onSwitchServer) items.push({ id: "servers", label: "Servers" });
    items.push(
      { id: "playback", label: "Playback" },
      { id: "subtitles", label: "Subtitles" },
      { id: "about", label: "About" },
    );
    return items;
  }, [onSwitchServer]);

  const [section, setSection] = useState<SettingsSectionId>(() => sections[0]?.id ?? "playback");
  const [settings, setSettings] = useState<PlaybackSettings>(() => loadPlaybackSettings());
  const [updateStatus, setUpdateStatus] = useState<AppUpdateStatus>({ kind: "checking" });
  const [changelogFallbackUrl, setChangelogFallbackUrl] = useState<string | null>(null);
  const platform = detectPlatform();
  const appearance = settings.subtitleAppearance;
  const previewVars = subtitleAppearanceCssVars(appearance);
  const latestLabel = latestVersionLabel(updateStatus);
  const changelogUrl = changelogUrlOrNull(updateStatus);
  const activeSection = sections.find((item) => item.id === section) ?? sections[0];

  useEffect(() => {
    if (!sections.some((item) => item.id === section)) {
      setSection(sections[0]?.id ?? "playback");
    }
  }, [section, sections]);

  useEffect(() => {
    let cancelled = false;
    void checkAppUpdate({ currentVersionName: __APP_VERSION__ }).then((status) => {
      if (!cancelled) setUpdateStatus(status);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (!isBackKey(event.key)) return;
      if (event.defaultPrevented) return;
      event.preventDefault();
      onBack();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onBack]);

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

  function setStreamMethod(choice: StreamMethodChoice) {
    update({
      forceDirectPlay: choice === "direct",
      forceTranscode: choice === "transcode",
    });
  }

  function openChangelog(url: string) {
    const opened = window.open(url, "_blank", "noopener,noreferrer");
    if (!opened) {
      setChangelogFallbackUrl(url);
    }
  }

  let pane: ReactNode = null;
  if (section === "servers" && onSwitchServer) {
    pane = (
      <>
        <p className="muted settings-note">Switch servers or scan the LAN for new ones.</p>
        <FocusButton
          variant="ghost"
          className="settings-action"
          icon={<Radar />}
          onClick={onSwitchServer}
        >
          Servers / Scan LAN
        </FocusButton>
      </>
    );
  } else if (section === "playback") {
    pane = (
      <div className="settings-block__rows">
        <SettingsChoiceRow
          label="Player backend"
          hint="Auto uses native on Tizen/webOS"
          value={settings.playerBackend}
          options={BACKEND_OPTIONS}
          onChange={(playerBackend) => update({ playerBackend })}
        />
        <SettingsChoiceRow
          label="Stream method"
          hint="Auto prefers remux when possible"
          value={streamMethodFromSettings(settings)}
          options={STREAM_OPTIONS}
          onChange={setStreamMethod}
        />
      </div>
    );
  } else if (section === "subtitles") {
    pane = (
      <>
        <p className="muted settings-note">Applied on HTML5, webOS, and Tizen overlay.</p>
        <div className="settings-block__rows">
          <SettingsChoiceRow
            label="Size"
            value={appearance.fontSize}
            options={SIZE_OPTIONS}
            onChange={(fontSize) => updateAppearance({ fontSize })}
          />
          <SettingsChoiceRow
            label="Text color"
            value={appearance.fontColor}
            options={SUBTITLE_COLOR_CHOICES.map((color) => ({
              value: color.hex,
              label: color.label,
            }))}
            onChange={(fontColor) => updateAppearance({ fontColor })}
          />
          <SettingsChoiceRow
            label="Background style"
            value={appearance.backgroundStyle}
            options={STYLE_OPTIONS}
            onChange={(backgroundStyle) => updateAppearance({ backgroundStyle })}
          />
          <SettingsChoiceRow
            label="Background color"
            value={appearance.backgroundColor}
            options={SUBTITLE_BG_COLOR_CHOICES.map((color) => ({
              value: color.hex,
              label: color.label,
            }))}
            onChange={(backgroundColor) => updateAppearance({ backgroundColor })}
          />
          <SettingsChoiceRow
            label="Background opacity"
            value={String(appearance.backgroundOpacity)}
            options={OPACITY_OPTIONS}
            onChange={(step) => updateAppearance({ backgroundOpacity: Number(step) })}
          />
          <SettingsChoiceRow
            label="Position"
            value={appearance.position}
            options={POSITION_OPTIONS}
            onChange={(position) => updateAppearance({ position })}
          />
          <SettingsToggleRow
            label="Text outline"
            hint="Improves contrast on bright scenes"
            checked={appearance.textOutline}
            onChange={(textOutline) => updateAppearance({ textOutline })}
          />
        </div>
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
      </>
    );
  } else {
    pane = (
      <div className="settings-about">
        <p>
          Platform <strong>{platform}</strong>
        </p>
        <p>
          Version <strong>{__APP_VERSION__}</strong>
        </p>
        <p>
          Update status <strong>{statusLabel(updateStatus)}</strong>
        </p>
        {latestLabel ? (
          <p>
            Latest <strong>{latestLabel}</strong>
          </p>
        ) : null}
        {changelogUrl ? (
          <>
            <FocusButton
              variant="ghost"
              className="settings-action"
              icon={<FileText />}
              onClick={() => openChangelog(changelogUrl)}
            >
              Changelog
            </FocusButton>
            {changelogFallbackUrl ? (
              <p className="muted settings-note">{changelogFallbackUrl}</p>
            ) : null}
          </>
        ) : null}
      </div>
    );
  }

  return (
    <section className="screen settings-screen">
      <header className="settings-header">
        <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={onBack} autoFocus>
          Back
        </FocusButton>
        <div className="settings-header__titles">
          <p className="eyebrow">Preferences</p>
          <h1>Settings</h1>
        </div>
      </header>

      <div className="settings-shell">
        <nav className="settings-sidebar" aria-label="Settings sections">
          {sections.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`settings-nav-item${item.id === section ? " is-active" : ""}`}
              aria-current={item.id === section ? "page" : undefined}
              onClick={() => setSection(item.id)}
            >
              {item.label}
            </button>
          ))}
        </nav>

        <div className="settings-pane" key={section}>
          <h2 className="settings-pane__title">{activeSection?.label ?? "Settings"}</h2>
          {pane}
        </div>
      </div>
    </section>
  );
}
