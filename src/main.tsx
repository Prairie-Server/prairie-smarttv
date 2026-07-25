import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/sora/400.css";
import "@fontsource/sora/600.css";
import "@fontsource/fraunces/600.css";
import "@fontsource/fraunces/700.css";
import "./styles.css";
import { App } from "./App";

const root = document.getElementById("root");
if (!root) {
  throw new Error("Missing #root");
}

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
