import { FolderOpen, Home, Library, Search, Settings, Tv, Unplug, Users } from "lucide-react";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { FocusButton } from "./FocusButton";
import { ProfileAvatar } from "./ProfileAvatar";

export type ShellTab = "home" | "libraries" | "collections" | "search" | "livetv";

interface ShellNavProps {
  active: ShellTab;
  profileName?: string;
  profileAvatarUrl?: string | null;
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
  profileAvatarUrl,
  showLiveTv = false,
  onNavigate,
  onProfiles,
  onSettings,
  onDisconnect,
}: ShellNavProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const firstItemRef = useRef<HTMLButtonElement>(null);

  const tabs = showLiveTv
    ? [
        ...BASE_TABS.slice(0, 3),
        { id: "livetv" as const, label: "Live TV", icon: <Tv /> },
        BASE_TABS[3]!,
      ]
    : BASE_TABS;

  useEffect(() => {
    if (!menuOpen) return;
    firstItemRef.current?.focus();
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" || event.key === "Backspace") {
        event.preventDefault();
        setMenuOpen(false);
      }
    }
    function onPointerDown(event: MouseEvent) {
      if (!menuRef.current?.contains(event.target as Node)) {
        setMenuOpen(false);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("mousedown", onPointerDown);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("mousedown", onPointerDown);
    };
  }, [menuOpen]);

  function runAndClose(action: () => void) {
    setMenuOpen(false);
    action();
  }

  return (
    <header className="shell-nav">
      <div className="shell-nav__brand">
        <img className="shell-nav__mark" src="/prairie-mark.png" alt="" width={40} height={40} />
        <div className="shell-nav__brand-text">
          <p className="eyebrow">Prairie</p>
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
      <div className="shell-nav__actions" ref={menuRef}>
        <button
          type="button"
          className="shell-nav__avatar-btn focusable"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          aria-label={profileName ? `Profile menu for ${profileName}` : "Profile menu"}
          onClick={() => setMenuOpen((open) => !open)}
        >
          <ProfileAvatar name={profileName} avatarUrl={profileAvatarUrl} size="md" />
        </button>
        {menuOpen ? (
          <div className="shell-nav__menu" role="menu">
            <p className="shell-nav__menu-label">{profileName ?? "Profile"}</p>
            <button
              ref={firstItemRef}
              type="button"
              role="menuitem"
              className="shell-nav__menu-item focusable"
              onClick={() => runAndClose(onProfiles)}
            >
              <Users size={18} aria-hidden />
              Switch profile
            </button>
            <button
              type="button"
              role="menuitem"
              className="shell-nav__menu-item focusable"
              onClick={() => runAndClose(onSettings)}
            >
              <Settings size={18} aria-hidden />
              Settings
            </button>
            <button
              type="button"
              role="menuitem"
              className="shell-nav__menu-item focusable"
              onClick={() => runAndClose(onDisconnect)}
            >
              <Unplug size={18} aria-hidden />
              Disconnect
            </button>
          </div>
        ) : null}
      </div>
    </header>
  );
}
