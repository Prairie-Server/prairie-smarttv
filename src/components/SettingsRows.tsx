import type { KeyboardEvent, ReactNode } from "react";

interface SettingsRowProps {
  label: string;
  hint?: string;
  value: string;
  onCycle: (direction: 1 | -1) => void;
  autoFocus?: boolean;
}

/** Full-width TV settings row: Enter / Left / Right cycle the value. */
export function SettingsCycleRow({ label, hint, value, onCycle, autoFocus }: SettingsRowProps) {
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      event.stopPropagation();
      onCycle(-1);
      return;
    }
    if (event.key === "ArrowRight" || event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.stopPropagation();
      onCycle(1);
    }
  }

  return (
    <button
      type="button"
      className="settings-row"
      autoFocus={autoFocus}
      onClick={() => onCycle(1)}
      onKeyDown={onKeyDown}
    >
      <span className="settings-row__copy">
        <span className="settings-row__label">{label}</span>
        {hint ? <span className="settings-row__hint">{hint}</span> : null}
      </span>
      <span className="settings-row__value" aria-hidden="true">
        {value}
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

export function SettingsChoiceRow<T extends string>({
  label,
  hint,
  value,
  options,
  onChange,
}: SettingsChoiceRowProps<T>) {
  const index = Math.max(
    0,
    options.findIndex((opt) => opt.value === value),
  );
  const current = options[index] ?? options[0];

  function cycle(direction: 1 | -1) {
    if (!options.length) return;
    const nextIndex = (index + direction + options.length) % options.length;
    onChange(options[nextIndex]!.value);
  }

  return (
    <SettingsCycleRow
      label={label}
      hint={hint}
      value={current?.label ?? String(value)}
      onCycle={cycle}
    />
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
