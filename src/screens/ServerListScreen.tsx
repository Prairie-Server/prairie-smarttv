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

export interface ServerListScreenProps {
  onSelectSaved: (entry: ServerEntry) => void;
  onSelectDiscovery: (hit: DiscoveryHit) => void;
  onAddManual: () => void;
  onBack: () => void;
  /** Start a LAN scan when the screen mounts (e.g. from Connect → Scan LAN). */
  autoScan?: boolean;
}

function mergeHitLists(base: DiscoveryHit[], extra: DiscoveryHit[]): DiscoveryHit[] {
  const map = new Map(base.map((h) => [h.url, h]));
  for (const hit of extra) map.set(hit.url, hit);
  return [...map.values()];
}

export function ServerListScreen({
  onSelectSaved,
  onSelectDiscovery,
  onAddManual,
  onBack,
  autoScan = false,
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
    setStatusText("Scanning for Prairie servers…");

    try {
      const current = loadRegistry();
      setRegistry(current);

      let hits = await runLanDiscovery({
        extraCidrs: current.scanCidrs,
        deepScan: false,
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
          ? "No Prairie servers found on the LAN"
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
      <header className="server-list-header">
        <div>
          <p className="eyebrow">Servers</p>
          <h1 className="home-title">Prairie servers</h1>
          <p className="lede">
            Saved servers and LAN discoveries via <code>GET /api/v1/health</code>.
          </p>
        </div>
        <FocusButton variant="ghost" onClick={onBack}>
          Back
        </FocusButton>
      </header>

      {statusText ? <p className="server-list-status">{statusText}</p> : null}
      {errorText ? (
        <p className="form-error" role="alert">
          {errorText}
        </p>
      ) : null}

      <div className="server-list-actions">
        <FocusButton onClick={() => void startScan(true)} disabled={busy} autoFocus>
          {busy ? "Scanning…" : "Scan LAN"}
        </FocusButton>
        <FocusButton variant="ghost" onClick={onAddManual} disabled={busy}>
          Add manually
        </FocusButton>
        <FocusButton variant="ghost" onClick={handleRemove} disabled={busy || !focusedId}>
          Remove
        </FocusButton>
      </div>

      <div className="server-list-grid" role="list">
        {saved.map((entry) => (
          <button
            key={entry.id}
            type="button"
            role="listitem"
            className={`server-card focusable ${focusedId === entry.id ? "is-focused" : ""} ${
              entry.id === registry.activeServerId ? "is-active" : ""
            }`}
            onFocus={() => setFocusedId(entry.id)}
            onClick={() => onSelectSaved(entry)}
            disabled={busy}
          >
            <span className="server-card__name">{displayName(entry)}</span>
            <span className="server-card__meta">
              {entry.id === registry.activeServerId ? "Active · " : "Saved · "}
              {entry.url}
            </span>
          </button>
        ))}

        {discovered.map((hit) => (
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

        {!busy && saved.length === 0 && discovered.length === 0 ? (
          <p className="muted">No servers yet — scan the LAN or add a URL manually.</p>
        ) : null}
      </div>
    </section>
  );
}
