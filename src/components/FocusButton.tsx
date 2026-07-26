import type { ButtonHTMLAttributes, ReactNode } from "react";

interface FocusButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  variant?: "primary" | "ghost" | "danger";
}

export function FocusButton({
  children,
  variant = "primary",
  className = "",
  type = "button",
  ...rest
}: FocusButtonProps) {
  return (
    <button type={type} className={`focus-btn focus-btn--${variant} ${className}`.trim()} {...rest}>
      {children}
    </button>
  );
}
