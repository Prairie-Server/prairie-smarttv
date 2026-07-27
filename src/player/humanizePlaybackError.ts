/** Map raw AVPlay / media error codes to short human-readable copy. */
export function humanizePlaybackError(raw: string): string {
  const text = (raw ?? "").trim();
  if (!text) return "Playback failed";

  const upper = text.toUpperCase();
  if (upper.includes("TRANSCODE TIMED OUT") || upper.includes("TRANSCODE_TIMED_OUT")) {
    return "Transcode timed out";
  }
  if (upper.includes("PLAYER_ERR_CONNECTION_FAILED") || upper.includes("CONNECTION")) {
    return "Could not connect to the stream. Check your network and try again.";
  }
  if (upper.includes("PLAYER_ERR_NETWORK") || upper.includes("NETWORK")) {
    return "Network error while streaming. Try again in a moment.";
  }
  if (upper.includes("PLAYER_ERR_NO_SUCH_FILE") || upper.includes("NOT_FOUND")) {
    return "Stream not found. The file may have been removed.";
  }
  if (upper.includes("PLAYER_ERR_INVALID_URI") || upper.includes("INVALID_URI")) {
    return "Invalid stream address.";
  }
  if (upper.includes("PLAYER_ERR_SEEK") || upper.includes("SEEK")) {
    return "Could not seek in this stream.";
  }
  if (upper.includes("PLAYER_ERR_NONE_SUPPORTED_CODEC") || upper.includes("CODEC")) {
    return "This format is not supported on this TV. Try forcing Transcode in Settings.";
  }
  if (upper.includes("PLAYER_ERR") || upper.includes("AVPLAY")) {
    return "The TV player could not play this stream. Try again or force Transcode.";
  }
  if (/^media error\s*\d+/i.test(text)) {
    return "The TV could not decode this stream. Try again or force Transcode.";
  }
  return text;
}
