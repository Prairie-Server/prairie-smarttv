import type { ButtonHTMLAttributes, ReactNode } from "react";

interface FocusButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children?: ReactNode;
  icon?: ReactNode;
  variant?: "primary" | "secondary" | "ghost" | "danger" | "circle";
  active?: boolean;
}

export function FocusButton({
  children,
  icon,
  variant = "primary",
  active = false,
  className = "",
  type = "button",
  ...rest
}: FocusButtonProps) {
  const classes = ["focus-btn", `focus-btn--${variant}`, active ? "is-active" : "", className]
    .filter(Boolean)
    .join(" ");

  return (
    <button type={type} className={classes} {...rest}>
      {icon ? (
        <span className="focus-btn__icon" aria-hidden="true">
          {icon}
        </span>
      ) : null}
      {children != null && children !== false ? children : null}
    </button>
  );
}
