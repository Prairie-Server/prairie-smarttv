import { lazy, Suspense, useCallback, useEffect, useState, type ReactNode } from "react";
import type { CollectionCard } from "./api/collections";
import { checkServer } from "./api/checkServer";
import { fetchLiveTvChannels, type LiveTvChannel } from "./api/livetv";
import type { Library } from "./api/libraries";
import {
  setSessionTokensRefreshedHandler,
  setSessionUnauthorizedHandler,
} from "./api/sessionClient";
import { ScreenErrorBoundary } from "./components/ScreenErrorBoundary";
import { ShellNav, type ShellTab } from "./components/ShellNav";
import type { DiscoveryHit } from "./discovery/discover";
import { handleSpatialArrowKey } from "./focus/spatialFocus";
import { ServerUrlContext } from "./serverUrlContext";
import { HomeBrowseScreen } from "./screens/HomeBrowseScreen";
import type { PlayerLaunch } from "./screens/PlayerScreen";
import { saveLastServerUrl } from "./storage/persist";
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
import { loadCachedLiveTvAvailable, saveCachedLiveTvAvailable } from "./lib/liveTvProbeCache";
import {
  clearSession,
  loadSession,
  saveSession,
  type AuthTokens,
  type PrairieSession,
} from "./storage/session";

/**
 * Screens are code-split so launch only parses what the first paint needs.
 *
 * A TV reads these chunks from local flash, so the load is negligible, while
 * the JavaScript the app must parse before it can show anything drops by
 * roughly a third. Home stays static: it is the screen we boot into.
 */
const CollectionBrowseScreen = lazy(() =>
  import("./screens/CollectionBrowseScreen").then((m) => ({ default: m.CollectionBrowseScreen })),
);
const CollectionsScreen = lazy(() =>
  import("./screens/CollectionsScreen").then((m) => ({ default: m.CollectionsScreen })),
);
const ConnectScreen = lazy(() =>
  import("./screens/ConnectScreen").then((m) => ({ default: m.ConnectScreen })),
);
const ItemDetailScreen = lazy(() =>
  import("./screens/ItemDetailScreen").then((m) => ({ default: m.ItemDetailScreen })),
);
const LibrariesScreen = lazy(() =>
  import("./screens/LibrariesScreen").then((m) => ({ default: m.LibrariesScreen })),
);
const LibraryBrowseScreen = lazy(() =>
  import("./screens/LibraryBrowseScreen").then((m) => ({ default: m.LibraryBrowseScreen })),
);
const LiveTvPlayerScreen = lazy(() =>
  import("./screens/LiveTvPlayerScreen").then((m) => ({ default: m.LiveTvPlayerScreen })),
);
const LiveTvScreen = lazy(() =>
  import("./screens/LiveTvScreen").then((m) => ({ default: m.LiveTvScreen })),
);
const ManualServerScreen = lazy(() =>
  import("./screens/ManualServerScreen").then((m) => ({ default: m.ManualServerScreen })),
);
const ProfileSelectScreen = lazy(() =>
  import("./screens/ProfileSelectScreen").then((m) => ({ default: m.ProfileSelectScreen })),
);
const SearchScreen = lazy(() =>
  import("./screens/SearchScreen").then((m) => ({ default: m.SearchScreen })),
);
const ServerListScreen = lazy(() =>
  import("./screens/ServerListScreen").then((m) => ({ default: m.ServerListScreen })),
);
const PlaybackSettingsScreen = lazy(() =>
  import("./settings/PlaybackSettingsScreen").then((m) => ({ default: m.PlaybackSettingsScreen })),
);
const PlayerScreen = lazy(() =>
  import("./screens/PlayerScreen").then((m) => ({ default: m.PlayerScreen })),
);

type Route =
  | { name: "servers"; back?: "home"; autoScan?: boolean }
  | { name: "manual"; initialUrl?: string }
  | {
      name: "connect";
      serverUrl: string;
      serverName?: string;
      initialUsername?: string;
    }
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

/** Let the first screen's own requests finish before probing Live TV. */
const LIVE_TV_PROBE_DELAY_MS = 400;

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
  return { name: "servers", autoScan: true };
}

export function App() {
  const [session, setSession] = useState<PrairieSession | null>(() => {
    migrateFromLegacy();
    return loadSession() ?? sessionFromActiveRegistry();
  });
  const [route, setRoute] = useState<Route>(() => initialRoute());
  // null = pending (unknown); boolean = probed / cached. Seed from cache so
  // Home can reserve On now on the first paint instead of inserting it late.
  const [liveTvProbe, setLiveTvProbe] = useState<boolean | null>(() => {
    const active = loadSession() ?? sessionFromActiveRegistry();
    return active ? loadCachedLiveTvAvailable(active.serverUrl) : false;
  });
  const liveTvAvailable = session != null && liveTvProbe === true;
  const reserveOnNow = session != null && liveTvProbe === null;

  // Keying the boundary on the route clears a stale error when the user
  // navigates away, so a crashed screen never sticks to the next one.
  const routeKey = route.name === "detail" ? `detail:${route.contentId}` : route.name;
  // Suspense must wrap each lazy screen *inside* the shell (and each fullscreen
  // route), not the whole App: a root-only boundary unmounted ShellNav on every
  // first visit to Libraries / Search / … and flashed a blank page.
  const lazyGate = (node: ReactNode) => (
    <Suspense fallback={<div className="screen" aria-busy="true" />}>{node}</Suspense>
  );
  const guard = (screen: string, node: ReactNode, onBack?: () => void) => (
    <ScreenErrorBoundary key={routeKey} screen={screen} onBack={onBack}>
      {lazyGate(node)}
    </ScreenErrorBoundary>
  );

  const goServers = useCallback((autoScan = true) => {
    setRoute({ name: "servers", autoScan });
  }, []);

  const openLogin = useCallback(
    (serverUrl: string, options?: { serverName?: string; initialUsername?: string }) => {
      setRoute({
        name: "connect",
        serverUrl,
        serverName: options?.serverName,
        initialUsername: options?.initialUsername,
      });
    },
    [],
  );

  const disconnect = useCallback(() => {
    const registry = loadRegistry();
    if (registry.activeServerId) {
      saveRegistry(clearTokens(registry, registry.activeServerId));
    }
    clearSession();
    setSession(null);
    setLiveTvProbe(false);
    goServers(true);
  }, [goServers]);

  useEffect(() => {
    setSessionUnauthorizedHandler(disconnect);
    setSessionTokensRefreshedHandler((tokens) => {
      setSession((prev) =>
        prev
          ? {
              ...prev,
              accessToken: tokens.accessToken,
              refreshToken: tokens.refreshToken ?? prev.refreshToken,
            }
          : prev,
      );
    });
    return () => {
      setSessionUnauthorizedHandler(undefined);
      setSessionTokensRefreshedHandler(undefined);
    };
  }, [disconnect]);

  useEffect(() => {
    if (!session) {
      setLiveTvProbe(false);
      return;
    }
    const cached = loadCachedLiveTvAvailable(session.serverUrl);
    if (cached != null) {
      setLiveTvProbe(cached);
    } else {
      setLiveTvProbe(null);
    }
    let cancelled = false;
    // Runs after the first screen has had a chance to paint: this probe only
    // decides whether a nav tab appears / On now stays reserved. Home already
    // holds the slot when the result is unknown, so a short delay is enough.
    const handle = window.setTimeout(() => {
      void (async () => {
        try {
          const channels = await fetchLiveTvChannels(session);
          if (cancelled) return;
          const available = channels.length > 0;
          saveCachedLiveTvAvailable(session.serverUrl, available);
          setLiveTvProbe(available);
        } catch {
          if (cancelled) return;
          saveCachedLiveTvAvailable(session.serverUrl, false);
          setLiveTvProbe(false);
        }
      })();
    }, LIVE_TV_PROBE_DELAY_MS);
    return () => {
      cancelled = true;
      window.clearTimeout(handle);
    };
  }, [session]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      handleSpatialArrowKey(event);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [route.name]);

  async function handleSelectSaved(entry: ServerEntry): Promise<void> {
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
    const setupError =
      "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.";
    const probe = await checkServer(full.url);
    if (!probe.ok) throw new Error(probe.message);
    if (probe.needsSetup) throw new Error(setupError);

    if (probe.serverName?.trim() && probe.serverName.trim() !== full.fetchedName.trim()) {
      registry = addOrUpdate(registry, {
        url: probe.serverUrl,
        fetchedName: probe.serverName.trim(),
      });
      saveRegistry(registry);
    }

    openLogin(probe.serverUrl, {
      serverName: probe.serverName?.trim() || full.fetchedName,
      initialUsername: full.username || undefined,
    });
  }

  async function handleSelectDiscovery(hit: DiscoveryHit): Promise<void> {
    if (hit.serverName.trim()) {
      const registry = addOrUpdate(loadRegistry(), {
        url: hit.url,
        fetchedName: hit.serverName,
      });
      saveRegistry(registry);
    }
    const setupError =
      "This server has not been set up yet. Open its web UI in a browser on another device to create the first account, then return here to sign in.";
    const probe = await checkServer(hit.url);
    if (!probe.ok) throw new Error(probe.message);
    if (probe.needsSetup) throw new Error(setupError);

    if (probe.serverName?.trim()) {
      const registry = addOrUpdate(loadRegistry(), {
        url: probe.serverUrl,
        fetchedName: probe.serverName.trim(),
      });
      saveRegistry(registry);
    }

    openLogin(probe.serverUrl, {
      serverName: probe.serverName?.trim() || hit.serverName.trim() || undefined,
    });
  }

  if (route.name === "servers") {
    return guard(
      "Servers",
      <ServerListScreen
        autoScan={route.autoScan !== false}
        onSelectSaved={handleSelectSaved}
        onSelectDiscovery={handleSelectDiscovery}
        onAddManual={() => setRoute({ name: "manual" })}
        onBack={route.back === "home" && session ? () => setRoute({ name: "home" }) : undefined}
      />,
    );
  }

  if (route.name === "manual") {
    return guard(
      "Add server",
      <ManualServerScreen
        initialUrl={route.initialUrl}
        onBack={() => goServers(false)}
        onContinue={(serverUrl, options) => openLogin(serverUrl, options)}
      />,
      () => goServers(false),
    );
  }

  if (route.name === "connect") {
    return guard(
      "Sign in",
      <ConnectScreen
        serverUrl={route.serverUrl}
        serverName={route.serverName}
        initialUsername={route.initialUsername}
        onBack={() => goServers(false)}
        onAuthenticated={(auth) => {
          setSession(null);
          setRoute({ name: "profiles", auth });
        }}
      />,
      () => goServers(false),
    );
  }

  if (route.name === "profiles") {
    // Reached two ways: straight after sign-in (no session yet), and from the
    // shell's profile switcher (session live). Backing out of the switcher must
    // return to the app — only the post-login flow has nowhere to go but out.
    const leaveProfiles = () => {
      if (session) {
        setRoute({ name: "home" });
        return;
      }
      clearSession();
      setSession(null);
      goServers(false);
    };
    return guard(
      "Profiles",
      <ProfileSelectScreen
        auth={route.auth}
        onSelected={(next) => {
          setSession(next);
          setRoute({ name: "home" });
        }}
        onCancel={leaveProfiles}
      />,
      leaveProfiles,
    );
  }

  if (!session) {
    return guard(
      "Servers",
      <ServerListScreen
        autoScan
        onSelectSaved={handleSelectSaved}
        onSelectDiscovery={handleSelectDiscovery}
        onAddManual={() => setRoute({ name: "manual" })}
      />,
    );
  }

  if (route.name === "settings") {
    return (
      <ServerUrlContext.Provider value={session.serverUrl}>
        {guard(
          "Settings",
          <PlaybackSettingsScreen
            onBack={() => setRoute(route.back)}
            onSwitchServer={() => setRoute({ name: "servers", back: "home", autoScan: true })}
          />,
          () => setRoute(route.back),
        )}
      </ServerUrlContext.Provider>
    );
  }

  if (route.name === "player") {
    const playerRoute = route;
    return (
      <ServerUrlContext.Provider value={session.serverUrl}>
        {guard(
          "Playback",
          <PlayerScreen
            session={session}
            launch={playerRoute.launch}
            onExit={() => setRoute(playerRoute.back)}
          />,
          () => setRoute(playerRoute.back),
        )}
      </ServerUrlContext.Provider>
    );
  }

  if (route.name === "livetv-player") {
    const liveRoute = route;
    return (
      <ServerUrlContext.Provider value={session.serverUrl}>
        {guard(
          "Live TV",
          <LiveTvPlayerScreen
            session={session}
            channel={liveRoute.channel}
            onExit={() => setRoute(liveRoute.back)}
          />,
          () => setRoute(liveRoute.back),
        )}
      </ServerUrlContext.Provider>
    );
  }

  if (route.name === "detail") {
    const detailRoute = route;
    return (
      <ServerUrlContext.Provider value={session.serverUrl}>
        {guard(
          "This title",
          <ItemDetailScreen
            session={session}
            contentId={detailRoute.contentId}
            onBack={() => setRoute(detailRoute.back)}
            onPlay={(launch) => setRoute({ name: "player", launch, back: detailRoute })}
            onOpenItem={(contentId) => setRoute({ name: "detail", contentId, back: detailRoute })}
          />,
          () => setRoute(detailRoute.back),
        )}
      </ServerUrlContext.Provider>
    );
  }

  const tab = shellTabFor(route) ?? "home";
  const openItem = (contentId: string) => setRoute({ name: "detail", contentId, back: route });

  let body: ReactNode = null;
  if (route.name === "home") {
    body = (
      <HomeBrowseScreen
        session={session}
        onOpenItem={openItem}
        showOnNow={liveTvAvailable}
        reserveOnNow={reserveOnNow}
        onOpenLiveChannel={(channel) => setRoute({ name: "livetv-player", channel, back: route })}
      />
    );
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
        libraryType={route.library.type}
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
    <ServerUrlContext.Provider value={session.serverUrl}>
      <div className="shell">
        <ShellNav
          active={tab}
          profileName={session.profileName}
          profileAvatarUrl={session.profileAvatarUrl}
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
                refreshToken: session.refreshToken,
                username: session.username,
              },
            })
          }
          onSettings={() => setRoute({ name: "settings", back: route })}
          onDisconnect={disconnect}
        />
        <main className="shell__main">
          {guard("This screen", body, () => setRoute({ name: "home" }))}
        </main>
      </div>
    </ServerUrlContext.Provider>
  );
}
