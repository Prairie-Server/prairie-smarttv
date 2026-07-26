import { useCallback, useEffect, useState, type ReactNode } from "react";
import type { CollectionCard } from "./api/collections";
import { fetchLiveTvChannels, type LiveTvChannel } from "./api/livetv";
import type { Library } from "./api/libraries";
import { setSessionUnauthorizedHandler } from "./api/sessionClient";
import { ShellNav, type ShellTab } from "./components/ShellNav";
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
import { PlaybackSettingsScreen } from "./settings/PlaybackSettingsScreen";
import { loadLastServerUrl } from "./storage/persist";
import {
  clearSession,
  loadSession,
  type AuthTokens,
  type PrairieSession,
} from "./storage/session";

type Route =
  | { name: "connect" }
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

export function App() {
  const [session, setSession] = useState<PrairieSession | null>(() => loadSession());
  const [route, setRoute] = useState<Route>(() =>
    loadSession() ? { name: "home" } : { name: "connect" },
  );
  const [liveTvAvailable, setLiveTvAvailable] = useState(false);

  const disconnect = useCallback(() => {
    clearSession();
    setSession(null);
    setLiveTvAvailable(false);
    setRoute({ name: "connect" });
  }, []);

  useEffect(() => {
    setSessionUnauthorizedHandler(disconnect);
    return () => setSessionUnauthorizedHandler(undefined);
  }, [disconnect]);

  useEffect(() => {
    if (!session) {
      setLiveTvAvailable(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const channels = await fetchLiveTvChannels(session);
        if (!cancelled) setLiveTvAvailable(channels.length > 0);
      } catch {
        if (!cancelled) setLiveTvAvailable(false);
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

  if (route.name === "connect" || (!session && route.name !== "profiles")) {
    return (
      <ConnectScreen
        initialServerUrl={
          session?.serverUrl ||
          loadLastServerUrl() ||
          import.meta.env.VITE_DEFAULT_SERVER_URL ||
          ""
        }
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
          setRoute({ name: "connect" });
        }}
      />
    );
  }

  if (!session) {
    return (
      <ConnectScreen
        initialServerUrl={
          loadLastServerUrl() || import.meta.env.VITE_DEFAULT_SERVER_URL || ""
        }
        onAuthenticated={(auth) => setRoute({ name: "profiles", auth })}
      />
    );
  }

  if (route.name === "settings") {
    return <PlaybackSettingsScreen onBack={() => setRoute(route.back)} />;
  }

  if (route.name === "player") {
    return (
      <PlayerScreen
        session={session}
        launch={route.launch}
        onExit={() => setRoute(route.back)}
      />
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
  const openItem = (contentId: string) =>
    setRoute({ name: "detail", contentId, back: route });

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
        onTune={(channel) =>
          setRoute({ name: "livetv-player", channel, back: { name: "livetv" } })
        }
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
