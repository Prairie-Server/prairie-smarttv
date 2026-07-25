import { useCallback, useEffect, useState, type ReactNode } from "react";
import type { CollectionCard } from "./api/collections";
import type { Library } from "./api/libraries";
import { ShellNav, type ShellTab } from "./components/ShellNav";
import { CollectionBrowseScreen } from "./screens/CollectionBrowseScreen";
import { CollectionsScreen } from "./screens/CollectionsScreen";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeBrowseScreen } from "./screens/HomeBrowseScreen";
import { ItemDetailScreen } from "./screens/ItemDetailScreen";
import { LibrariesScreen } from "./screens/LibrariesScreen";
import { LibraryBrowseScreen } from "./screens/LibraryBrowseScreen";
import { PlayerScreen } from "./screens/PlayerScreen";
import { ProfileSelectScreen } from "./screens/ProfileSelectScreen";
import { SearchScreen } from "./screens/SearchScreen";
import { PlaybackSettingsScreen } from "./settings/PlaybackSettingsScreen";
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
  | { name: "detail"; contentId: string; back: Route }
  | { name: "settings"; back: Route }
  | { name: "player"; fileId: number; title?: string; back: Route };

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
    default:
      return null;
  }
}

export function App() {
  const [session, setSession] = useState<PrairieSession | null>(() => loadSession());
  const [route, setRoute] = useState<Route>(() =>
    loadSession() ? { name: "home" } : { name: "connect" },
  );

  const disconnect = useCallback(() => {
    clearSession();
    setSession(null);
    setRoute({ name: "connect" });
  }, []);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.key)) {
        return;
      }
      const focusables = Array.from(
        document.querySelectorAll<HTMLElement>(
          'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      ).filter((el) => el.offsetParent !== null);
      if (focusables.length < 2) return;
      const active = document.activeElement as HTMLElement | null;
      const index = active ? focusables.indexOf(active) : -1;
      if (index < 0) {
        focusables[0]?.focus();
        event.preventDefault();
        return;
      }
      const delta =
        event.key === "ArrowDown" || event.key === "ArrowRight" ? 1 : -1;
      const next = focusables[(index + delta + focusables.length) % focusables.length];
      next?.focus();
      event.preventDefault();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [route.name]);

  if (route.name === "connect" || (!session && route.name !== "profiles")) {
    return (
      <ConnectScreen
        initialServerUrl={session?.serverUrl ?? import.meta.env.VITE_DEFAULT_SERVER_URL ?? ""}
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
        initialServerUrl={import.meta.env.VITE_DEFAULT_SERVER_URL ?? ""}
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
        fileId={route.fileId}
        title={route.title}
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
        onPlay={(fileId, title) =>
          setRoute({ name: "player", fileId, title, back: route })
        }
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
  }

  return (
    <div className="shell">
      <ShellNav
        active={tab}
        profileName={session.profileName}
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
      <main className="shell__main">{body}</main>
    </div>
  );
}
