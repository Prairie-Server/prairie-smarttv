/** Map player-local HLS time onto media (content) time. */
export function toMediaTime(playerTimeSeconds: number, streamOriginSeconds = 0): number {
  return Math.max(0, playerTimeSeconds + streamOriginSeconds);
}

/**
 * Map media time onto the current HLS window. Negative means the target is
 * before the window and needs a server re-plan (new manifest).
 */
export function toPlayerTime(mediaTimeSeconds: number, streamOriginSeconds = 0): number {
  return mediaTimeSeconds - streamOriginSeconds;
}
