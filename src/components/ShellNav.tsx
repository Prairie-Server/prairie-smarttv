import { FolderOpen, Home, Library, Search, Settings, Tv, Unplug, Users } from "lucide-react";
import type { ReactNode } from "react";
import { FocusButton } from "./FocusButton";

export type ShellTab = "home" | "libraries" | "collections" | "search" | "livetv";

interface ShellNavProps {
  active: ShellTab;
  profileName?: string;
  showLiveTv?: boolean;
  onNavigate: (tab: ShellTab) => void;
  onProfiles: () => void;
  onSettings: () => void;
  onDisconnect: () => void;
}

const BASE_TABS: Array<{ id: ShellTab; label: string; icon: ReactNode }> = [
  { id: "home", label: "Home", icon: <Home /> },
  { id: "libraries", label: "Libraries", icon: <Library /> },
  { id: "collections", label: "Collections", icon: <FolderOpen /> },
  { id: "search", label: "Search", icon: <Search /> },
];

export function ShellNav({
  active,
  profileName,
  showLiveTv = false,
  onNavigate,
  onProfiles,
  onSettings,
  onDisconnect,
}: ShellNavProps) {
  const tabs = showLiveTv
    ? [
        ...BASE_TABS.slice(0, 3),
        { id: "livetv" as const, label: "Live TV", icon: <Tv /> },
        BASE_TABS[3]!,
      ]
    : BASE_TABS;

  return (
    <header className="shell-nav">
      <div className="shell-nav__brand">
        <img className="shell-nav__mark" src="/prairie-mark.png" alt="" width={40} height={40} />
        <div className="shell-nav__brand-text">
          <p className="eyebrow">Prairie</p>
          <p className="shell-nav__profile muted">{profileName ?? "Profile"}</p>
        </div>
      </div>
      <nav className="shell-nav__tabs" aria-label="Main">
        {tabs.map((tab) => (
          <FocusButton
            key={tab.id}
            icon={tab.icon}
            variant={active === tab.id ? "primary" : "ghost"}
            className={active === tab.id ? "shell-nav__tab is-active" : "shell-nav__tab"}
            onClick={() => onNavigate(tab.id)}
          >
            {tab.label}
          </FocusButton>
        ))}
      </nav>
      <div className="shell-nav__actions">
        <FocusButton variant="ghost" icon={<Users />} onClick={onProfiles}>
          Switch profile
        </FocusButton>
        <FocusButton variant="ghost" icon={<Settings />} onClick={onSettings}>
          Settings
        </FocusButton>
        <FocusButton variant="ghost" icon={<Unplug />} onClick={onDisconnect}>
          Disconnect
        </FocusButton>
      </div>
    </header>
  );
}
