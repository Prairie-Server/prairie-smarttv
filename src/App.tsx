import { useCallback, useEffect, useState } from "react";
import { ConnectScreen } from "./screens/ConnectScreen";
import { HomeScreen } from "./screens/HomeScreen";
import { PlayerScreen } from "./screens/PlayerScreen";
import { PlaybackSettingsScreen } from "./settings/PlaybackSettingsScreen";
import { clearSession, loadSession, type PrairieSession } from "./storage/session";

type Route =
  | { name: "connect" }
  | { name: "home" }
  | { name: "settings" }
  | { name: "player"; fileId: number };

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
    // Simple spatial-ish focus: keep Tab/arrow movement on focusable controls.
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

  if (!session || route.name === "connect") {
    return (
      <ConnectScreen
        initialServerUrl={session?.serverUrl ?? import.meta.env.VITE_DEFAULT_SERVER_URL ?? ""}
        onConnected={(next) => {
          setSession(next);
          setRoute({ name: "home" });
        }}
      />
    );
  }

  if (route.name === "settings") {
    return <PlaybackSettingsScreen onBack={() => setRoute({ name: "home" })} />;
  }

  if (route.name === "player") {
    return (
      <PlayerScreen
        session={session}
        fileId={route.fileId}
        onExit={() => setRoute({ name: "home" })}
      />
    );
  }

  return (
    <HomeScreen
      session={session}
      onPlay={(fileId) => setRoute({ name: "player", fileId })}
      onOpenSettings={() => setRoute({ name: "settings" })}
      onDisconnect={disconnect}
    />
  );
}
