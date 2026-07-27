export type ArrowKey = "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight";

export function isArrowKey(key: string): key is ArrowKey {
  return key === "ArrowUp" || key === "ArrowDown" || key === "ArrowLeft" || key === "ArrowRight";
}

/** Text-entry fields where arrows should move the caret, not spatial focus. */
export function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target instanceof HTMLTextAreaElement) return true;
  if (target instanceof HTMLSelectElement) return true;
  if (target.isContentEditable) return true;
  if (!(target instanceof HTMLInputElement)) return false;
  const type = (target.type || "text").toLowerCase();
  return (
    type === "text" ||
    type === "password" ||
    type === "search" ||
    type === "email" ||
    type === "url" ||
    type === "tel" ||
    type === "number" ||
    type === ""
  );
}

/**
 * Whether an arrow key should stay on the caret inside an editable field.
 * Up/Down always leave the field on TV remotes so users can reach Back / QR.
 * Left/Right keep caret motion until the selection is at the field edge.
 */
export function shouldDeferToEditableCaret(target: EventTarget | null, key: ArrowKey): boolean {
  if (!isEditableTarget(target)) return false;
  if (key === "ArrowUp" || key === "ArrowDown") return false;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)) {
    return true;
  }
  const start = target.selectionStart;
  const end = target.selectionEnd;
  if (start == null || end == null) return true;
  if (start !== end) return true;
  if (key === "ArrowLeft") return start > 0;
  if (key === "ArrowRight") return start < target.value.length;
  /* v8 ignore next -- ArrowUp/Down already returned above for editables */
  return true;
}

/** TV remote Back / Escape helpers. */
export function isBackKey(key: string): boolean {
  return key === "Escape" || key === "Backspace" || key === "XF86Back" || key === "GoBack";
}
