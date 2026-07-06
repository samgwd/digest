// TypeScript port of DigestTextSanitizer (originally in
// BookDigest/Services/OpenAIClient.swift, now DigestTextSanitizer.swift).
// Strips markdown so the stored digest is safe for direct TTS playback.

export function sanitize(text: string): string {
  let sanitized = text.replaceAll("\r\n", "\n");
  sanitized = replaceMarkdownLinks(sanitized);

  const lines = sanitized.split("\n").map((line) => {
    let cleaned = line.trim();

    cleaned = cleaned.replace(/^#{1,6}\s*/, "");
    cleaned = cleaned.replace(/^[-*+]\s+/, "");
    cleaned = cleaned.replace(/^\d+[.)]\s+/, "");
    cleaned = cleaned.replace(/^>\s*/, "");

    cleaned = cleaned.replace(/[*_`~]+/g, "");

    return cleaned.trim();
  });

  sanitized = lines.join("\n");
  sanitized = sanitized.replace(/\n{3,}/g, "\n\n");

  return sanitized.trim();
}

function replaceMarkdownLinks(text: string): string {
  return text.replace(/!?\[([^\]]+)\]\([^)]+\)/g, "$1");
}
