import type { ButtonHTMLAttributes, ReactNode } from "react";

interface FocusButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  icon?: ReactNode;
  variant?: "primary" | "ghost" | "danger";
}

export function FocusButton({
  children,
  icon,
  variant = "primary",
  className = "",
  type = "button",
  ...rest
}: FocusButtonProps) {
  return (
    <button type={type} className={`focus-btn focus-btn--${variant} ${className}`.trim()} {...rest}>
      {icon ? (
        <span className="focus-btn__icon" aria-hidden="true">
          {icon}
        </span>
      ) : null}
      {children}
    </button>
  );
}
