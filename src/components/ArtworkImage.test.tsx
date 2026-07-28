import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ArtworkImage } from "./ArtworkImage";
import { artworkRoleWidth } from "../lib/artworkRole";
import { BACKDROP_CARD_WIDTH } from "../lib/artworkUrl";
import { resetImageLoadQueueForTests } from "../lib/imageLoadQueue";
import { ServerUrlContext } from "../serverUrlContext";

const SERVER = "https://tv.example.com";

let container: HTMLDivElement;
let root: Root | null = null;

async function render(node: React.ReactNode) {
  await act(async () => {
    root = createRoot(container);
    root.render(<ServerUrlContext.Provider value={SERVER}>{node}</ServerUrlContext.Provider>);
  });
}

function images(): HTMLImageElement[] {
  return [...container.querySelectorAll("img")];
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  resetImageLoadQueueForTests();
});

afterEach(async () => {
  if (root) {
    await act(async () => root?.unmount());
    root = null;
  }
  container.remove();
  resetImageLoadQueueForTests();
});

describe("ArtworkImage", () => {
  it("decodes asynchronously by default so posters cannot block the remote", async () => {
    await render(<ArtworkImage src="/artwork/movie/original.webp" alt="" role="poster" />);
    expect(images()[0]?.getAttribute("decoding")).toBe("async");
  });

  it("lets a caller override the decoding hint", async () => {
    await render(
      <ArtworkImage src="/artwork/movie/original.webp" alt="" role="poster" decoding="sync" />,
    );
    expect(images()[0]?.getAttribute("decoding")).toBe("sync");
  });

  it("paints a small preview rung while the full-size hero loads", async () => {
    await render(<ArtworkImage src="/artwork/show/original.webp" alt="hero" role="backdropHero" />);

    const [full, preview] = images();
    // The real image stays first in the DOM so callers keep finding it.
    expect(full?.getAttribute("alt")).toBe("hero");
    expect(preview?.getAttribute("src")).toContain(`w${BACKDROP_CARD_WIDTH}`);
    expect(preview?.getAttribute("aria-hidden")).toBe("true");

    await act(async () => {
      full?.dispatchEvent(new Event("load"));
    });
    // Preview is dropped the moment the full image is ready.
    expect(images()).toHaveLength(1);
  });

  it("uses no preview rung for roles that decode fast enough already", async () => {
    await render(<ArtworkImage src="/artwork/show/original.webp" alt="" role="poster" />);
    expect(images()).toHaveLength(1);
  });

  it("requests a sized rung, never the original object", async () => {
    await render(<ArtworkImage src="/artwork/lib/original.webp" alt="" role="libraryTile" />);
    const src = images()[0]?.getAttribute("src") ?? "";
    // Assert against the ladder rather than a literal, so moving a role to a
    // different rung does not need this test edited.
    expect(src).toContain(`/w${artworkRoleWidth("libraryTile")}.`);
    expect(src).not.toContain("/original.");
  });

  it("falls back to the placeholder when the preview rung 404s", async () => {
    await render(
      <ArtworkImage
        src="/artwork/show/original.webp"
        alt=""
        placeholderLabel="Prairie"
        role="backdropHero"
      />,
    );
    await act(async () => {
      images()[1]?.dispatchEvent(new Event("error"));
    });
    expect(images()).toHaveLength(1);
    expect(container.querySelector(".artwork-image__placeholder")?.textContent).toBe("P");
  });
});
