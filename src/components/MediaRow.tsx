import type { ReactNode } from "react";

interface MediaRowProps {
  title: string;
  children: ReactNode;
  /** Shimmer title bar for skeleton rows (avoids empty→title height jump). */
  skeleton?: boolean;
}

export function MediaRow({ title, children, skeleton = false }: MediaRowProps) {
  return (
    <section className={`media-row${skeleton ? " media-row--skeleton" : ""}`}>
      {skeleton ? (
        <div className="media-row__title media-row__title--skeleton" aria-hidden="true" />
      ) : (
        <h2 className="media-row__title">{title}</h2>
      )}
      <div className="media-row__scroller">{children}</div>
    </section>
  );
}
