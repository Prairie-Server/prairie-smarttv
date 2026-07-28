/** Shared profile avatar: server image when present, else first-letter fallback. */

import { useServerUrl } from "../serverUrlContext";

interface ProfileAvatarProps {
  name?: string | null;
  avatarUrl?: string | null;
  /** Override server origin used to absolutize relative `/profile-avatars/...` paths. */
  serverUrl?: string | null;
  className?: string;
  size?: "sm" | "md" | "lg";
}

export function profileInitial(name?: string | null): string {
  const trimmed = name?.trim() ?? "";
  if (!trimmed) return "?";
  return trimmed.slice(0, 1).toUpperCase();
}

export function resolveProfileAvatarUrl(
  avatarUrl: string | null | undefined,
  serverUrl: string | null | undefined,
): string {
  const url = avatarUrl?.trim() ?? "";
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://") || url.startsWith("data:")) {
    return url;
  }
  const base = serverUrl?.replace(/\/+$/, "") ?? "";
  if (!base) return url;
  return url.startsWith("/") ? `${base}${url}` : `${base}/${url}`;
}

export function ProfileAvatar({
  name,
  avatarUrl,
  serverUrl: serverUrlProp,
  className = "",
  size = "md",
}: ProfileAvatarProps) {
  const contextServerUrl = useServerUrl();
  const url = resolveProfileAvatarUrl(avatarUrl, serverUrlProp ?? contextServerUrl);
  const initial = profileInitial(name);
  const classes = ["profile-avatar", `profile-avatar--${size}`, className]
    .filter(Boolean)
    .join(" ");

  return (
    <span className={classes} aria-hidden="true">
      {url ? (
        // Not an artwork-ladder object (no width rungs), so it stays a plain
        // <img> — but it decodes off the paint path like every other image.
        <img className="profile-avatar__img" src={url} alt="" decoding="async" loading="lazy" />
      ) : (
        <span className="profile-avatar__initial">{initial}</span>
      )}
    </span>
  );
}
