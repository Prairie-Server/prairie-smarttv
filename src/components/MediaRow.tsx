import type { ReactNode } from "react";

interface MediaRowProps {
  title: string;
  children: ReactNode;
}

export function MediaRow({ title, children }: MediaRowProps) {
  return (
    <section className="media-row">
      <h2 className="media-row__title">{title}</h2>
      <div className="media-row__scroller">{children}</div>
    </section>
  );
}
