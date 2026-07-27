import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";

interface FocusButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children?: ReactNode;
  icon?: ReactNode;
  variant?: "primary" | "secondary" | "ghost" | "danger" | "circle";
  active?: boolean;
}

export const FocusButton = forwardRef<HTMLButtonElement, FocusButtonProps>(function FocusButton(
  { children, icon, variant = "primary", active = false, className = "", type = "button", ...rest },
  ref,
) {
  const classes = ["focus-btn", `focus-btn--${variant}`, active ? "is-active" : "", className]
    .filter(Boolean)
    .join(" ");

  return (
    <button ref={ref} type={type} className={classes} {...rest}>
      {icon ? (
        <span className="focus-btn__icon" aria-hidden="true">
          {icon}
        </span>
      ) : null}
      {children != null && children !== false ? children : null}
    </button>
  );
});
