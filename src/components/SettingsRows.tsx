import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { isBackKey } from "../focus/spatialFocus";

interface SettingsRowProps {
  label: string;
  hint?: string;
  value: string;
  onActivate: () => void;
  autoFocus?: boolean;
}

/** Full-width TV settings row that opens a compact value menu on Enter / click. */
export function SettingsCycleRow({ label, hint, value, onActivate, autoFocus }: SettingsRowProps) {
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.stopPropagation();
      onActivate();
    }
  }

  return (
    <button
      type="button"
      className="settings-row"
      autoFocus={autoFocus}
      onClick={onActivate}
      onKeyDown={onKeyDown}
    >
      <span className="settings-row__copy">
        <span className="settings-row__label">{label}</span>
        {hint ? <span className="settings-row__hint">{hint}</span> : null}
      </span>
      <span className="settings-row__value" aria-hidden="true">
        {value}
        <span className="settings-row__chevron">▾</span>
      </span>
    </button>
  );
}

interface SettingsToggleRowProps {
  label: string;
  hint?: string;
  checked: boolean;
  onChange: (next: boolean) => void;
}

export function SettingsToggleRow({ label, hint, checked, onChange }: SettingsToggleRowProps) {
  return (
    <button
      type="button"
      className={`settings-row${checked ? " is-on" : ""}`}
      aria-pressed={checked}
      onClick={() => onChange(!checked)}
    >
      <span className="settings-row__copy">
        <span className="settings-row__label">{label}</span>
        {hint ? <span className="settings-row__hint">{hint}</span> : null}
      </span>
      <span className="settings-row__value">{checked ? "On" : "Off"}</span>
    </button>
  );
}

interface SettingsChoiceRowProps<T extends string> {
  label: string;
  hint?: string;
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (next: T) => void;
}

/**
 * Litefin-style compact dropdown: the settings row stays put; options open in a
 * small menu anchored to the value (no full-width layout swap / CLS).
 */
export function SettingsChoiceRow<T extends string>({
  label,
  hint,
  value,
  options,
  onChange,
}: SettingsChoiceRowProps<T>) {
  const [open, setOpen] = useState(false);
  const listId = useId();
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const index = Math.max(
    0,
    options.findIndex((opt) => opt.value === value),
  );
  const current = options[index] ?? options[0];

  useEffect(() => {
    if (!open) return;
    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (!isBackKey(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      setOpen(false);
    }
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [open]);

  return (
    <div className={`settings-row-wrap${open ? " is-open" : ""}`} ref={wrapRef}>
      <SettingsCycleRow
        label={label}
        hint={hint}
        value={current?.label ?? String(value)}
        onActivate={() => setOpen((prev) => !prev)}
      />
      {open ? (
        <div className="settings-menu" role="listbox" aria-label={label} id={listId}>
          {options.map((opt, optIndex) => {
            const selected = opt.value === value;
            return (
              <button
                key={opt.value}
                type="button"
                role="option"
                aria-selected={selected}
                className={`settings-menu__option${selected ? " is-selected" : ""}`}
                autoFocus={selected || (optIndex === 0 && !current)}
                onClick={() => {
                  onChange(opt.value);
                  setOpen(false);
                }}
              >
                {opt.label}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}

interface SettingsBlockProps {
  title: string;
  children: ReactNode;
  note?: string;
}

export function SettingsBlock({ title, children, note }: SettingsBlockProps) {
  return (
    <section className="settings-block">
      <h2>{title}</h2>
      {note ? <p className="muted settings-note">{note}</p> : null}
      <div className="settings-block__rows">{children}</div>
    </section>
  );
}
