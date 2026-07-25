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

const BASE_TABS: Array<{ id: ShellTab; label: string }> = [
  { id: "home", label: "Home" },
  { id: "libraries", label: "Libraries" },
  { id: "collections", label: "Collections" },
  { id: "search", label: "Search" },
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
    ? [...BASE_TABS.slice(0, 3), { id: "livetv" as const, label: "Live TV" }, BASE_TABS[3]!]
    : BASE_TABS;

  return (
    <header className="shell-nav">
      <div className="shell-nav__brand">
        <p className="eyebrow">Prairie</p>
        <p className="shell-nav__profile muted">{profileName ?? "Profile"}</p>
      </div>
      <nav className="shell-nav__tabs" aria-label="Main">
        {tabs.map((tab) => (
          <FocusButton
            key={tab.id}
            variant={active === tab.id ? "primary" : "ghost"}
            className={active === tab.id ? "shell-nav__tab is-active" : "shell-nav__tab"}
            onClick={() => onNavigate(tab.id)}
          >
            {tab.label}
          </FocusButton>
        ))}
      </nav>
      <div className="shell-nav__actions">
        <FocusButton variant="ghost" onClick={onProfiles}>
          Switch profile
        </FocusButton>
        <FocusButton variant="ghost" onClick={onSettings}>
          Settings
        </FocusButton>
        <FocusButton variant="ghost" onClick={onDisconnect}>
          Disconnect
        </FocusButton>
      </div>
    </header>
  );
}
