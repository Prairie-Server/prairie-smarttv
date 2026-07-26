import { useCallback, useEffect, useState, type ReactNode } from "react";
import type { CollectionCard } from "./api/collections";
import { fetchLiveTvChannels, type LiveTvChannel } from "./api/livetv";
import type { Library } from "./api/libraries";
import { setSessionUnauthorizedHandler } from "./api/sessionClient";
import { ShellNav, type ShellTab } from "./components/ShellNav";
import type { DiscoveryHit } from "./discovery/discover";
import { handleSpatialArrowKey } from "./focus/spatialFocus";
import { CollectionBrowseScreen } from "./screens/CollectionBrowseScreen";
import { CollectionsScreen } from "./screens/CollectionsScreen";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeBrowseScreen } from "./screens/HomeBrowseScreen";
import { ItemDetailScreen } from "./screens/ItemDetailScreen";
import { LibrariesScreen } from "./screens/LibrariesScreen";
import { LibraryBrowseScreen } from "./screens/LibraryBrowseScreen";
import { LiveTvPlayerScreen } from "./screens/LiveTvPlayerScreen";
import { LiveTvScreen } from "./screens/LiveTvScreen";
import { PlayerScreen, type PlayerLaunch } from "./screens/PlayerScreen";
import { ProfileSelectScreen } from "./screens/ProfileSelectScreen";
import { SearchScreen } from "./screens/SearchScreen";
import { ServerListScreen } from "./screens/ServerListScreen";
import { PlaybackSettingsScreen } from "./settings/PlaybackSettingsScreen";
import { loadLastServerUrl, saveLastServerUrl } from "./storage/persist";
import {
  addOrUpdate,
  clearTokens,
  findIndex,
  loadRegistry,
  migrateFromLegacy,
  saveRegistry,
  sessionFromEntry,
  switchTo,
  type ServerEntry,
} from "./storage/serverRegistry";
import {
  clearSession,
  loadSession,
  saveSession,
  type AuthTokens,
  type PrairieSession,
} from "./storage/session";

type Route =
  | { name: "connect"; prefillUrl?: string }
  | { name: "servers"; back: "connect" | "home"; autoScan?: boolean }
  | { name: "profiles"; auth: AuthTokens }
  | { name: "home" }
  | { name: "libraries" }
  | { name: "library"; library: Library }
  | { name: "collections" }
  | { name: "collection"; collection: CollectionCard }
  | { name: "search" }
  | { name: "livetv" }
  | { name: "livetv-player"; channel: LiveTvChannel; back: Route }
  | { name: "detail"; contentId: string; back: Route }
  | { name: "settings"; back: Route }
  | { name: "player"; launch: PlayerLaunch; back: Route };

function shellTabFor(route: Route): ShellTab | null {
  switch (route.name) {
    case "home":
      return "home";
    case "libraries":
    case "library":
      return "libraries";
    case "collections":
    case "collection":
      return "collections";
    case "search":
      return "search";
    case "livetv":
      return "livetv";
    default:
      return null;
  }
}

function sessionFromActiveRegistry(): PrairieSession | null {
  const registry = loadRegistry();
  if (!registry.activeServerId) return null;
  const idx = findIndex(registry, registry.activeServerId);
  if (idx < 0) return null;
  const session = sessionFromEntry(registry.entries[idx]);
  return session ? saveSession(session) : null;
}

function initialRoute(): Route {
  migrateFromLegacy();
  if (loadSession() || sessionFromActiveRegistry()) return { name: "home" };
  if (loadRegistry().entries.length > 0) return { name: "servers", back: "connect" };
  return { name: "connect" };
}

export function App() {
  const [session, setSession] = useState<PrairieSession | null>(() => {
    migrateFromLegacy();
    return loadSession() ?? sessionFromActiveRegistry();
  });
  const [route, setRoute] = useState<Route>(() => initialRoute());
  const [liveTvProbe, setLiveTvProbe] = useState(false);
  const liveTvAvailable = session != null && liveTvProbe;

  const goConnectOrServers = useCallback((prefillUrl?: string) => {
    if (loadRegistry().entries.length > 0) {
      setRoute({ name: "servers", back: "connect" });
      return;
    }
    setRoute({ name: "connect", prefillUrl });
  }, []);

  const disconnect = useCallback(() => {
    const registry = loadRegistry();
    if (registry.activeServerId) {
      saveRegistry(clearTokens(registry, registry.activeServerId));
    }
    clearSession();
    setSession(null);
    setLiveTvProbe(false);
    goConnectOrServers();
  }, [goConnectOrServers]);

  useEffect(() => {
    setSessionUnauthorizedHandler(disconnect);
    return () => setSessionUnauthorizedHandler(undefined);
  }, [disconnect]);

  useEffect(() => {
    if (!session) {
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const channels = await fetchLiveTvChannels(session);
        if (!cancelled) setLiveTvProbe(channels.length > 0);
      } catch {
        if (!cancelled) setLiveTvProbe(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      handleSpatialArrowKey(event);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [route.name]);

  function handleSelectSaved(entry: ServerEntry) {
    let registry = loadRegistry();
    const idx = findIndex(registry, entry.id);
    if (idx < 0) return;
    const full = registry.entries[idx]!;
    registry = switchTo(registry, full.id);
    saveRegistry(registry);
    const restored = sessionFromEntry(full);
    if (restored) {
      setSession(saveSession(restored));
      saveLastServerUrl(restored.serverUrl);
      setRoute({ name: "home" });
      return;
    }
    setRoute({ name: "connect", prefillUrl: full.url });
  }

  function handleSelectDiscovery(hit: DiscoveryHit) {
    if (hit.serverName.trim()) {
      const registry = addOrUpdate(loadRegistry(), {
        url: hit.url,
        fetchedName: hit.serverName,
      });
      saveRegistry(registry);
    }
    setRoute({ name: "connect", prefillUrl: hit.url });
  }

  if (route.name === "servers") {
    return (
      <ServerListScreen
        autoScan={route.autoScan}
        onSelectSaved={handleSelectSaved}
        onSelectDiscovery={handleSelectDiscovery}
        onAddManual={() => setRoute({ name: "connect" })}
        onBack={() => {
          if (route.back === "home" && session) {
            setRoute({ name: "home" });
          } else {
            setRoute({ name: "connect" });
          }
        }}
      />
    );
  }

  if (route.name === "connect" || (!session && route.name !== "profiles")) {
    return (
      <ConnectScreen
        initialServerUrl={
          route.name === "connect" && route.prefillUrl
            ? route.prefillUrl
            : session?.serverUrl ||
              loadLastServerUrl() ||
              import.meta.env.VITE_DEFAULT_SERVER_URL ||
              ""
        }
        onOpenServers={() => setRoute({ name: "servers", back: "connect" })}
        onScanLan={() => setRoute({ name: "servers", back: "connect", autoScan: true })}
        onAuthenticated={(auth) => {
          setSession(null);
          setRoute({ name: "profiles", auth });
        }}
      />
    );
  }

  if (route.name === "profiles") {
    return (
      <ProfileSelectScreen
        auth={route.auth}
        onSelected={(next) => {
          setSession(next);
          setRoute({ name: "home" });
        }}
        onCancel={() => {
          clearSession();
          setSession(null);
          goConnectOrServers();
        }}
      />
    );
  }

  if (!session) {
    return (
      <ConnectScreen
        initialServerUrl={loadLastServerUrl() || import.meta.env.VITE_DEFAULT_SERVER_URL || ""}
        onOpenServers={() => setRoute({ name: "servers", back: "connect" })}
        onScanLan={() => setRoute({ name: "servers", back: "connect", autoScan: true })}
        onAuthenticated={(auth) => setRoute({ name: "profiles", auth })}
      />
    );
  }

  if (route.name === "settings") {
    return (
      <PlaybackSettingsScreen
        onBack={() => setRoute(route.back)}
        onSwitchServer={() => setRoute({ name: "servers", back: "home" })}
      />
    );
  }

  if (route.name === "player") {
    return (
      <PlayerScreen session={session} launch={route.launch} onExit={() => setRoute(route.back)} />
    );
  }

  if (route.name === "livetv-player") {
    return (
      <LiveTvPlayerScreen
        session={session}
        channel={route.channel}
        onExit={() => setRoute(route.back)}
      />
    );
  }

  if (route.name === "detail") {
    return (
      <ItemDetailScreen
        session={session}
        contentId={route.contentId}
        onBack={() => setRoute(route.back)}
        onPlay={(launch) => setRoute({ name: "player", launch, back: route })}
      />
    );
  }

  const tab = shellTabFor(route) ?? "home";
  const openItem = (contentId: string) => setRoute({ name: "detail", contentId, back: route });

  let body: ReactNode = null;
  if (route.name === "home") {
    body = <HomeBrowseScreen session={session} onOpenItem={openItem} />;
  } else if (route.name === "libraries") {
    body = (
      <LibrariesScreen
        session={session}
        onOpenLibrary={(library) => setRoute({ name: "library", library })}
      />
    );
  } else if (route.name === "library") {
    body = (
      <LibraryBrowseScreen
        session={session}
        libraryId={route.library.id}
        libraryName={route.library.name}
        onBack={() => setRoute({ name: "libraries" })}
        onOpenItem={openItem}
      />
    );
  } else if (route.name === "collections") {
    body = (
      <CollectionsScreen
        session={session}
        onOpenCollection={(collection) => setRoute({ name: "collection", collection })}
      />
    );
  } else if (route.name === "collection") {
    body = (
      <CollectionBrowseScreen
        session={session}
        title={route.collection.title ?? route.collection.name ?? "Collection"}
        collectionId={route.collection.id}
        libraryId={route.collection.library_id}
        onBack={() => setRoute({ name: "collections" })}
        onOpenItem={openItem}
      />
    );
  } else if (route.name === "search") {
    body = <SearchScreen session={session} onOpenItem={openItem} />;
  } else if (route.name === "livetv") {
    body = (
      <LiveTvScreen
        session={session}
        onTune={(channel) => setRoute({ name: "livetv-player", channel, back: { name: "livetv" } })}
      />
    );
  }

  return (
    <div className="shell">
      <ShellNav
        active={tab}
        profileName={session.profileName}
        showLiveTv={liveTvAvailable}
        onNavigate={(next) => {
          switch (next) {
            case "home":
              setRoute({ name: "home" });
              break;
            case "libraries":
              setRoute({ name: "libraries" });
              break;
            case "collections":
              setRoute({ name: "collections" });
              break;
            case "search":
              setRoute({ name: "search" });
              break;
            case "livetv":
              setRoute({ name: "livetv" });
              break;
          }
        }}
        onProfiles={() =>
          setRoute({
            name: "profiles",
            auth: {
              serverUrl: session.serverUrl,
              accessToken: session.accessToken,
              username: session.username,
            },
          })
        }
        onSettings={() => setRoute({ name: "settings", back: route })}
        onDisconnect={disconnect}
      />
      <main className="shell__main">{body}</main>
    </div>
  );
}
