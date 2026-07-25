/** HTML overlay that renders AVPlay `onsubtitlechange` cues with our CSS vars. */

export function createSubtitleOverlay(container: HTMLElement): HTMLDivElement {
  const root = document.createElement("div");
  root.className = "prairie-avplay-subtitle";
  root.setAttribute("aria-live", "polite");
  root.setAttribute("data-focus-trap", "off");

  const cue = document.createElement("span");
  cue.className = "prairie-avplay-subtitle__cue";
  root.appendChild(cue);
  container.appendChild(root);
  return root;
}

/** Normalize AVPlay subtitle payload (string or line array) into display HTML. */
export function formatAvPlaySubtitleText(text: unknown): string {
  if (text == null) return "";
  if (Array.isArray(text)) {
    return text
      .map((line) => String(line ?? "").trim())
      .filter(Boolean)
      .join("\n");
  }
  return String(text);
}

export function setSubtitleOverlayText(root: HTMLElement | null, text: unknown): void {
  if (!root) return;
  const cue = root.querySelector(".prairie-avplay-subtitle__cue");
  if (!(cue instanceof HTMLElement)) return;
  const value = formatAvPlaySubtitleText(text);
  cue.textContent = value;
  root.hidden = !value;
  root.classList.toggle("is-empty", !value);
}

export function clearSubtitleOverlay(root: HTMLElement | null): void {
  setSubtitleOverlayText(root, "");
}

export function destroySubtitleOverlay(root: HTMLElement | null): void {
  root?.remove();
}
