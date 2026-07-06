// TypeScript port of the text chunking in
// BookDigest/Services/SpeechController.swift (chunk / splitLongParagraph).
// Uniform max size — the 900-char first chunk in the app was an on-device
// fast-start optimization that doesn't apply server-side.

export function chunkText(text: string, maxCharacters = 3000): string[] {
  const paragraphs = text
    .split("\n")
    .map((p) => p.trim())
    .filter((p) => p.length > 0);

  const chunks: string[] = [];
  let current = "";

  for (const paragraph of paragraphs) {
    if (paragraph.length > maxCharacters) {
      if (current.length > 0) {
        chunks.push(current);
        current = "";
      }
      chunks.push(...splitLongParagraph(paragraph, maxCharacters));
      continue;
    }

    if (current.length === 0) {
      current = paragraph;
    } else if (current.length + paragraph.length + 2 <= maxCharacters) {
      current += `\n\n${paragraph}`;
    } else {
      chunks.push(current);
      current = paragraph;
    }
  }

  if (current.length > 0) {
    chunks.push(current);
  }

  return chunks;
}

function splitLongParagraph(paragraph: string, maxCharacters: number): string[] {
  const sentences = paragraph
    .split(". ")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  const chunks: string[] = [];
  let current = "";

  for (const sentence of sentences) {
    const sentenceText = sentence.endsWith(".") ? sentence : `${sentence}.`;
    if (current.length === 0) {
      current = sentenceText;
    } else if (current.length + sentenceText.length + 1 <= maxCharacters) {
      current += ` ${sentenceText}`;
    } else {
      chunks.push(current);
      current = sentenceText;
    }
  }

  if (current.length > 0) {
    chunks.push(current);
  }

  return chunks;
}
