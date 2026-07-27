import { createContext, useContext } from "react";

/** Connected Prairie origin for resolving relative artwork / media paths. */
export const ServerUrlContext = createContext<string>("");

export function useServerUrl(): string {
  return useContext(ServerUrlContext);
}
