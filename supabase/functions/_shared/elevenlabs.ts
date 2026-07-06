// ElevenLabs TTS per chunk + MP3 concatenation, mirroring the request the app
// previously made on-device (BookDigest/Services/SpeechController.swift).
// Output format mp3_44100_128 is CBR, so stripping ID3v2 headers and
// concatenating raw frames yields a single valid, seekable MP3. Each chunk
// also starts with a Xing/Info metadata frame that encodes that chunk's frame
// count — kept, the combined file would report chunk 1's duration — so it is
// stripped from every chunk and players estimate duration from size/bitrate,
// which is exact for CBR.

const TIMEOUT_MS = 180_000;

export async function synthesizeChunk(
  text: string,
  apiKey: string,
  voiceId: string,
  modelId: string,
): Promise<Uint8Array> {
  const endpoint = `https://api.elevenlabs.io/v1/text-to-speech/${
    encodeURIComponent(voiceId)
  }?output_format=mp3_44100_128`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "xi-api-key": apiKey,
      "Content-Type": "application/json",
      "Accept": "audio/mpeg",
    },
    body: JSON.stringify({
      text,
      model_id: modelId,
      voice_settings: { stability: 0.7 },
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (!response.ok) {
    let message = `ElevenLabs returned status ${response.status}.`;
    try {
      const parsed = await response.json();
      const detail = parsed?.detail?.message ?? parsed?.detail;
      if (typeof detail === "string") {
        message = `ElevenLabs error (status ${response.status}): ${detail}`;
      }
    } catch {
      // keep the generic status message
    }
    throw new Error(message);
  }

  const bytes = new Uint8Array(await response.arrayBuffer());

  if (bytes.length === 0) {
    throw new Error("ElevenLabs returned empty audio.");
  }
  if (!looksLikeAudio(bytes)) {
    throw new Error("ElevenLabs returned non-audio data.");
  }

  return bytes;
}

export function concatMp3(chunks: Uint8Array[]): Uint8Array {
  const parts = chunks.map((chunk) => stripMetadataFrame(stripID3v2(chunk)));
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const combined = new Uint8Array(total);

  let offset = 0;
  for (const part of parts) {
    combined.set(part, offset);
    offset += part.length;
  }

  return combined;
}

function looksLikeAudio(bytes: Uint8Array): boolean {
  if (bytes.length < 3) return false;
  // MP3 frame sync word
  if (bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0) return true;
  // ID3 tag header
  if (bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) return true;
  return false;
}

function stripID3v2(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 10) return bytes;
  if (bytes[0] !== 0x49 || bytes[1] !== 0x44 || bytes[2] !== 0x33) return bytes;

  // ID3v2 size is a 4-byte synchsafe integer at offset 6, excluding the
  // 10-byte header itself.
  const size = ((bytes[6] & 0x7f) << 21) |
    ((bytes[7] & 0x7f) << 14) |
    ((bytes[8] & 0x7f) << 7) |
    (bytes[9] & 0x7f);

  const start = 10 + size;
  return start < bytes.length ? bytes.subarray(start) : bytes;
}

// Drops a leading Xing/Info/VBRI frame (a silent frame whose payload holds the
// frame/byte count of one chunk, which players trust for duration).
function stripMetadataFrame(bytes: Uint8Array): Uint8Array {
  const frameLength = mp3FrameLength(bytes);
  if (frameLength === null || bytes.length < frameLength) return bytes;

  // Xing/Info sits after the side info, whose size depends on MPEG version
  // and channel mode; VBRI is always at offset 32 past the 4-byte header.
  const mpeg1 = ((bytes[1] >> 3) & 0x03) === 3;
  const mono = ((bytes[3] >> 6) & 0x03) === 3;
  const xingOffset = 4 + (mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17));

  const hasTag = (offset: number, tag: string) =>
    offset + tag.length <= frameLength &&
    [...tag].every((char, i) => bytes[offset + i] === char.charCodeAt(0));

  if (
    hasTag(xingOffset, "Xing") || hasTag(xingOffset, "Info") || hasTag(36, "VBRI")
  ) {
    return bytes.subarray(frameLength);
  }
  return bytes;
}

// Frame length of the MPEG Layer III frame at offset 0, or null if the bytes
// don't start with a valid frame header.
function mp3FrameLength(bytes: Uint8Array): number | null {
  if (bytes.length < 4) return null;
  if (bytes[0] !== 0xff || (bytes[1] & 0xe0) !== 0xe0) return null;

  const versionBits = (bytes[1] >> 3) & 0x03; // 0=MPEG2.5, 2=MPEG2, 3=MPEG1
  const layerBits = (bytes[1] >> 1) & 0x03; // 1=Layer III
  if (versionBits === 1 || layerBits !== 1) return null;
  const mpeg1 = versionBits === 3;

  const bitrateIndex = (bytes[2] >> 4) & 0x0f;
  const kbps = (mpeg1
    ? [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
    : [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0])[bitrateIndex];
  if (kbps === 0) return null;

  const sampleRateIndex = (bytes[2] >> 2) & 0x03;
  if (sampleRateIndex === 3) return null;
  const mpeg1Rates = [44100, 48000, 32000];
  const sampleRate = mpeg1Rates[sampleRateIndex] / (mpeg1 ? 1 : versionBits === 2 ? 2 : 4);

  const padding = (bytes[2] >> 1) & 0x01;
  const samplesPerFrame = mpeg1 ? 1152 : 576;
  return Math.floor((samplesPerFrame / 8) * (kbps * 1000) / sampleRate) + padding;
}
