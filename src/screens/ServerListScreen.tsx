import { useEffect, useRef, useState } from "react";
import { FocusButton } from "../components/FocusButton";
import type { DiscoveryHit } from "../discovery/discover";
import { runLanDiscovery } from "../discovery/scan";
import {
  displayName,
  loadRegistry,
  removeServer,
  saveRegistry,
  sortedEntries,
  type ServerEntry,
} from "../storage/serverRegistry";
import { loadLastServerUrl } from "../storage/persist";

export interface ServerListScreenProps {
  onSelectSaved: (entry: ServerEntry) => void;
  onSelectDiscovery: (hit: DiscoveryHit) => void;
  onAddManual: () => void;
  onBack?: () => void;
  /** Start a LAN scan when the screen mounts (default true — launch behavior). */
  autoScan?: boolean;
}

function mergeHitLists(base: DiscoveryHit[], extra: DiscoveryHit[]): DiscoveryHit[] {
  const map = new Map(base.map((h) => [h.url, h]));
  for (const hit of extra) map.set(hit.url, hit);
  return [...map.values()];
}

const DEFAULT_DISCOVERY_BASE_HOSTS = ["prairie.local", "prairie"] as const;

function hostnamesFromServerUrls(urls: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of urls) {
    const url = raw.trim();
    if (!url) continue;
    try {
      const host = new URL(url).hostname;
      const key = host.toLowerCase();
      if (!host || seen.has(key)) continue;
      seen.add(key);
      out.push(host);
    } catch {
      /* ignore invalid URL shapes */
    }
  }
  return out;
}

function computeDiscoveryBaseHosts(registry: ReturnType<typeof loadRegistry>): string[] {
  const savedHosts = hostnamesFromServerUrls(registry.entries.map((e) => e.url));
  const last = loadLastServerUrl();
  const lastHost = last ? hostnamesFromServerUrls([last]) : [];
  const custom = [...savedHosts, ...lastHost];
  const merged = [...custom, ...DEFAULT_DISCOVERY_BASE_HOSTS];

  // De-dupe while preserving ordering (first configured, then defaults).
  const out: string[] = [];
  const seen = new Set<string>();
  for (const host of merged) {
    const key = host.toLowerCase();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(host);
  }
  return out;
}

export function ServerListScreen({
  onSelectSaved,
  onSelectDiscovery,
  onAddManual,
  onBack,
  autoScan = true,
}: ServerListScreenProps) {
  const [registry, setRegistry] = useState(() => loadRegistry());
  const [discovered, setDiscovered] = useState<DiscoveryHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [statusText, setStatusText] = useState("");
  const [errorText, setErrorText] = useState("");
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const didAutoScan = useRef(false);

  const saved = sortedEntries(registry);
  const savedUrls = new Set(saved.map((e) => e.url));
  const freshHits = discovered.filter((hit) => !savedUrls.has(hit.url));

  useEffect(() => {
    return () => {
      abortRef.current?.abort();
    };
  }, []);

  useEffect(() => {
    if (!autoScan || didAutoScan.current) return;
    didAutoScan.current = true;
    void startScan(true);
  }, [autoScan]);

  async function startScan(includeDeep: boolean) {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setBusy(true);
    setErrorText("");
    setDiscovered([]);
    setStatusText("Looking for Prairie servers on your network…");

    try {
      const current = loadRegistry();
      setRegistry(current);
      const baseHosts = computeDiscoveryBaseHosts(current);

      let hits = await runLanDiscovery({
        extraCidrs: current.scanCidrs,
        deepScan: false,
        baseHosts,
        signal: controller.signal,
        onHit: (next) => setDiscovered(next),
        onProgress: (done, total) => {
          setStatusText(`Quick scan ${done}/${total}…`);
        },
      });
      if (controller.signal.aborted) return;
      setDiscovered(hits);

      if (includeDeep) {
        setStatusText("Deep LAN scan…");
        const deepHits = await runLanDiscovery({
          extraCidrs: current.scanCidrs,
          deepScan: true,
          baseHosts,
          signal: controller.signal,
          onHit: (next) => setDiscovered(mergeHitLists(hits, next)),
          onProgress: (done, total) => {
            setStatusText(`Deep scan ${done}/${total}…`);
          },
        });
        if (controller.signal.aborted) return;
        hits = mergeHitLists(hits, deepHits);
        setDiscovered(hits);
      }

      setStatusText(
        hits.length === 0
          ? "No Prairie servers found — add one manually or scan again"
          : `Found ${hits.length} server(s)`,
      );
    } catch (err) {
      if (!controller.signal.aborted) {
        setErrorText(err instanceof Error ? err.message : "Scan failed");
        setStatusText("");
      }
    } finally {
      if (!controller.signal.aborted) setBusy(false);
    }
  }

  function handleRemove() {
    if (!focusedId) return;
    const next = removeServer(loadRegistry(), focusedId);
    saveRegistry(next);
    setRegistry(next);
    setFocusedId(null);
  }

  return (
    <section className="screen server-list-screen">
      <div className="server-list-atmosphere" aria-hidden="true" />

      <div className="server-list-stage">
        <header className="server-list-hero">
          <img
            className="server-list-mark"
            src="/prairie-mark.png"
            alt=""
            width={112}
            height={112}
          />
          <div className="server-list-hero__copy">
            <p className="eyebrow">Smart TV</p>
            <h1 className="brand-hero">Prairie</h1>
            <p className="lede">Choose a saved server, one found nearby, or add an address.</p>
          </div>
          {onBack ? (
            <FocusButton variant="ghost" onClick={onBack}>
              Back
            </FocusButton>
          ) : null}
        </header>

        {statusText ? <p className="server-list-status">{statusText}</p> : null}
        {errorText ? (
          <p className="form-error" role="alert">
            {errorText}
          </p>
        ) : null}

        <div className="server-list-actions">
          <FocusButton
            onClick={() => void startScan(true)}
            disabled={busy}
            autoFocus={!saved.length}
          >
            {busy ? "Scanning…" : "Scan again"}
          </FocusButton>
          <FocusButton variant="ghost" onClick={onAddManual} disabled={busy}>
            Add manually
          </FocusButton>
          <FocusButton variant="ghost" onClick={handleRemove} disabled={busy || !focusedId}>
            Remove
          </FocusButton>
        </div>

        {saved.length > 0 ? (
          <section className="server-list-section" aria-label="Saved servers">
            <h2 className="server-list-section__title">Saved</h2>
            <div className="server-list-grid" role="list">
              {saved.map((entry, index) => (
                <button
                  key={entry.id}
                  type="button"
                  role="listitem"
                  className={`server-card focusable ${focusedId === entry.id ? "is-focused" : ""} ${
                    entry.id === registry.activeServerId ? "is-active" : ""
                  }`}
                  autoFocus={index === 0}
                  onFocus={() => setFocusedId(entry.id)}
                  onClick={() => onSelectSaved(entry)}
                  disabled={busy}
                >
                  <span className="server-card__name">{displayName(entry)}</span>
                  <span className="server-card__meta">
                    {entry.id === registry.activeServerId ? "Active · " : "Saved · "}
                    {entry.username ? `${entry.username} · ` : ""}
                    {entry.url}
                  </span>
                </button>
              ))}
            </div>
          </section>
        ) : null}

        {freshHits.length > 0 || busy ? (
          <section className="server-list-section" aria-label="Discovered servers">
            <h2 className="server-list-section__title">Discovered</h2>
            <div className="server-list-grid" role="list">
              {freshHits.map((hit) => (
                <button
                  key={`disc-${hit.url}`}
                  type="button"
                  role="listitem"
                  className="server-card focusable"
                  onClick={() => onSelectDiscovery(hit)}
                  disabled={busy}
                >
                  <span className="server-card__name">{hit.serverName.trim() || hit.url}</span>
                  <span className="server-card__meta">Found · {hit.url}</span>
                </button>
              ))}
              {busy && freshHits.length === 0 ? (
                <p className="muted">Scanning your network for Prairie…</p>
              ) : null}
            </div>
          </section>
        ) : null}

        {!busy && saved.length === 0 && freshHits.length === 0 ? (
          <p className="muted server-list-empty">
            No servers yet — wait for the scan, or add a URL manually.
          </p>
        ) : null}
      </div>
    </section>
  );
}
