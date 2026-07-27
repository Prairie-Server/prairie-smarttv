import { Component, type ErrorInfo, type ReactNode } from "react";
import { FocusButton } from "./FocusButton";

interface ScreenErrorBoundaryProps {
  children: ReactNode;
  /** Screen name used in the fallback copy and console log. */
  screen: string;
  /** Remount the subtree; the boundary clears its own error first. */
  onRetry?: () => void;
  onBack?: () => void;
}

interface ScreenErrorBoundaryState {
  error: Error | null;
  componentStack: string;
}

/**
 * Packaged TV apps have no reachable dev console, and React unmounts the whole
 * tree on an uncaught render error — leaving a dead frame the remote cannot
 * escape. This boundary keeps the failure recoverable (Retry / Back stay
 * focusable) and prints the stack on screen so a TV can be diagnosed without
 * attaching the web inspector.
 */
export class ScreenErrorBoundary extends Component<
  ScreenErrorBoundaryProps,
  ScreenErrorBoundaryState
> {
  state: ScreenErrorBoundaryState = { error: null, componentStack: "" };

  static getDerivedStateFromError(error: unknown): Partial<ScreenErrorBoundaryState> {
    return { error: error instanceof Error ? error : new Error(String(error)) };
  }

  componentDidCatch(error: unknown, info: ErrorInfo): void {
    this.setState({ componentStack: info.componentStack ?? "" });
    console.error(`[prairie] ${this.props.screen} render failed`, error, info.componentStack);
  }

  private reset = (): void => {
    this.setState({ error: null, componentStack: "" });
    this.props.onRetry?.();
  };

  render(): ReactNode {
    const { error, componentStack } = this.state;
    if (!error) return this.props.children;

    const detail = [error.stack || error.message, componentStack].filter(Boolean).join("\n");

    return (
      <section className="screen error-screen" role="alert">
        <h1 className="browse-title">Something went wrong</h1>
        <p className="muted">
          {this.props.screen} could not be displayed. The rest of the app is still usable.
        </p>
        <p className="form-error">{error.message}</p>
        <div className="row-actions">
          <FocusButton autoFocus onClick={this.reset}>
            Try again
          </FocusButton>
          {this.props.onBack ? (
            <FocusButton variant="secondary" onClick={this.props.onBack}>
              Back
            </FocusButton>
          ) : null}
        </div>
        <pre className="error-screen__stack">{detail}</pre>
      </section>
    );
  }
}
