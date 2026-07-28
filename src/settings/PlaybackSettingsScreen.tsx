import { ArrowLeft, FileText, Radar } from "lucide-react";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { FocusButton } from "../components/FocusButton";
import { SettingsChoiceRow, SettingsToggleRow } from "../components/SettingsRows";
import { isBackKey } from "../focus/spatialFocus";
import { resetImageFormatTierCache } from "../lib/imageFormats";
import { detectPlatform } from "../platform/detect";
import {
  describeAv1Probe,
  resolveAdvertisedCapabilities,
} from "../platform/tizen/deviceCapabilities";
import type { PlayerBackendPreference } from "../platform/types";
import {
  changelogUrlOrNull,
  latestVersionLabel,
  statusLabel,
  type AppUpdateStatus,
} from "../update/appUpdateStatus";
import { checkAppUpdate } from "../update/checkAppUpdate";
import {
  describePlayMethodPreference,
  loadPlaybackSettings,
  savePlaybackSettings,
  type PlaybackSettings,
} from "./playbackSettings";
import {
  applyPerformanceTier,
  describePerformanceMode,
  loadPerformanceMode,
  resolvePerformanceTier,
  savePerformanceMode,
  type PerformanceMode,
} from "../perf/performanceTier";
import { scheduleDurablePersist } from "../storage/durableStorage";
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

type SettingsSectionId = "servers" | "playback" | "display" | "subtitles" | "about";

const BACKEND_OPTIONS: { value: PlayerBackendPreference; label: string }[] = [
  { value: "auto", label: "Auto" },
  { value: "html5", label: "HTML5" },
  { value: "native", label: "Native" },
];

const PERF_OPTIONS: { value: PerformanceMode; label: string }[] = [
  { value: "auto", label: "Auto" },
  { value: "high", label: "High quality" },
  { value: "balanced", label: "Balanced" },
  { value: "low", label: "Performance" },
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

function formatProbeTriState(value: boolean | null): string {
  if (value === true) return "yes";
  if (value === false) return "no";
  return "n/a";
}

export function PlaybackSettingsScreen({ onBack, onSwitchServer }: PlaybackSettingsScreenProps) {
  const sections = useMemo(() => {
    const items: Array<{ id: SettingsSectionId; label: string }> = [];
    if (onSwitchServer) items.push({ id: "servers", label: "Servers" });
    items.push(
      { id: "playback", label: "Playback" },
      { id: "display", label: "Display" },
      { id: "subtitles", label: "Subtitles" },
      { id: "about", label: "About" },
    );
    return items;
  }, [onSwitchServer]);

  const [section, setSection] = useState<SettingsSectionId>(() => sections[0]?.id ?? "playback");
  const [settings, setSettings] = useState<PlaybackSettings>(() => loadPlaybackSettings());
  const [performanceMode, setPerformanceMode] = useState<PerformanceMode>(() =>
    loadPerformanceMode(),
  );
  const [updateStatus, setUpdateStatus] = useState<AppUpdateStatus>({ kind: "checking" });
  const [changelogFallbackUrl, setChangelogFallbackUrl] = useState<string | null>(null);
  const platform = detectPlatform();
  const appearance = settings.subtitleAppearance;
  const previewVars = subtitleAppearanceCssVars(appearance);
  const latestLabel = latestVersionLabel(updateStatus);
  const changelogUrl = changelogUrlOrNull(updateStatus);
  const activeSection = sections.find((item) => item.id === section) ?? sections[0];
  const resolvedTier = resolvePerformanceTier(performanceMode);
  const av1Probe = useMemo(() => describeAv1Probe(), []);
  const advertisedCaps = useMemo(
    () =>
      resolveAdvertisedCapabilities({
        forceAv1: settings.forceAv1,
        disableAv1: settings.disableAv1,
      }),
    [settings.forceAv1, settings.disableAv1],
  );
  const playMethodLabel = describePlayMethodPreference(settings);

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
      // resolveForcedPlayMethod checks direct first — keep the pair exclusive.
      if (partial.forceDirectPlay) next.forceTranscode = false;
      if (partial.forceTranscode) next.forceDirectPlay = false;
      if (partial.forceAv1) next.disableAv1 = false;
      if (partial.disableAv1) next.forceAv1 = false;
      return savePlaybackSettings(next);
    });
  }

  function updateAppearance(partial: Partial<SubtitleAppearance>) {
    update({
      subtitleAppearance: { ...appearance, ...partial },
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
        <SettingsToggleRow
          label="Force direct play"
          hint="Ask Prairie for Direct Play only (clears Force transcode)"
          checked={settings.forceDirectPlay}
          onChange={(forceDirectPlay) => update({ forceDirectPlay })}
        />
        <SettingsToggleRow
          label="Force transcode"
          hint="Ask Prairie to transcode (clears Force direct play)"
          checked={settings.forceTranscode}
          onChange={(forceTranscode) => update({ forceTranscode })}
        />
        <SettingsToggleRow
          label="Advertise AV1 (override)"
          hint="Force-advertise av1 when the panel probe is wrong"
          checked={settings.forceAv1}
          onChange={(forceAv1) => update({ forceAv1 })}
        />
        <SettingsToggleRow
          label="Disable AV1"
          hint="Never advertise av1, even when the probe says yes"
          checked={settings.disableAv1}
          onChange={(disableAv1) => update({ disableAv1 })}
        />
        <div className="settings-diagnostics" aria-label="Playback diagnostics">
          <p className="eyebrow">Diagnostics</p>
          <p className="muted settings-note">
            Play method <strong>{playMethodLabel}</strong>
          </p>
          <p className="muted settings-note">
            Tizen <strong>{av1Probe.tizenVersion || "n/a"}</strong>
            {" · "}
            AV1 systeminfo <strong>{formatProbeTriState(av1Probe.systeminfo)}</strong>
            {" · "}
            canPlayType <strong>{av1Probe.canPlayType ? "yes" : "no"}</strong>
            {" · "}
            probe <strong>{av1Probe.supported ? "av1" : "no-av1"}</strong>
          </p>
          <p className="muted settings-note">
            Advertised video <strong>{advertisedCaps.codecs_video.join(", ") || "none"}</strong>
          </p>
          <p className="muted settings-note">
            Audio <strong>{advertisedCaps.codecs_audio.join(", ") || "none"}</strong>
            {" · "}
            Max <strong>{advertisedCaps.max_resolution}</strong>
            {" · "}
            HDR <strong>{advertisedCaps.hdr ? "yes" : "no"}</strong>
          </p>
        </div>
      </div>
    );
  } else if (section === "display") {
    pane = (
      <div className="settings-block__rows">
        <SettingsChoiceRow
          label="Performance"
          hint={`Resolved: ${describePerformanceMode(performanceMode, resolvedTier)}. Lower tiers reduce focus scale, shadows, and animations.`}
          value={performanceMode}
          options={PERF_OPTIONS}
          onChange={(mode) => {
            const next = savePerformanceMode(mode);
            setPerformanceMode(next);
            applyPerformanceTier(resolvePerformanceTier(next));
            resetImageFormatTierCache();
            scheduleDurablePersist();
          }}
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
