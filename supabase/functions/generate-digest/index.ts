// Shared digest generation. Clients bring their own OpenAI / ElevenLabs API
// keys in the request body; keys live only in this invocation's memory and
// are never persisted or logged. All table/storage writes happen here with
// the service role — clients are read-only via RLS.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { BookInput } from "../_shared/prompts.ts";
import { sanitize } from "../_shared/sanitize.ts";
import { chunkText } from "../_shared/chunk.ts";
import { checkDigestGeneration, startDigestGeneration } from "../_shared/openai.ts";
import { concatMp3, synthesizeChunk } from "../_shared/elevenlabs.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

// One fixed voice for every book — a single shared MP3 per digest, never
// regenerated. Not client parameters by design.
const VOICE_ID = "lUTamkMw7gOzZbFIwmq4";
const SPEECH_MODEL = "eleven_flash_v2_5";

const AUDIO_BUCKET = "digest-audio";
const RATE_LIMIT_PER_HOUR = 10;
const BOOK_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,79}$/;

interface RequestBody {
  action?: string;
  book?: { id?: string; title?: string; author?: string; angle?: string };
  openaiKey?: string;
  elevenLabsKey?: string;
  model?: string;
}

// Prefer the new sb_secret_* / sb_publishable_* API keys (injected as JSON
// name->key dictionaries); fall back to the legacy JWT keys, which is what
// the local CLI still injects.
function resolveApiKey(dictionaryEnv: string, legacyEnv: string): string {
  const dictionaryJSON = Deno.env.get(dictionaryEnv);
  if (dictionaryJSON) {
    try {
      const keys = JSON.parse(dictionaryJSON) as Record<string, string>;
      const key = keys["default"] ?? Object.values(keys)[0];
      if (key) return key;
    } catch {
      // fall through to the legacy key
    }
  }
  return Deno.env.get(legacyEnv)!;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    resolveApiKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY"),
  );

  const userID = await authenticatedUserID(req);
  if (!userID) {
    return json({ error: "Not authenticated." }, 401);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const action = body.action;
  if (action !== "digest" && action !== "audio" && action !== "check") {
    return json({ error: "action must be 'digest', 'audio' or 'check'." }, 400);
  }

  const book = validateBook(body.book);
  if (!book) {
    return json({ error: "Invalid book payload." }, 400);
  }

  // Checks are polls, not generation requests — they start nothing and cost
  // nothing, so they bypass the hourly generation rate limit.
  if (action === "check") {
    return await handleCheck(admin, book, body);
  }

  const allowed = await withinRateLimit(admin, userID);
  if (!allowed) {
    return json({ error: "Too many generation requests. Try again later." }, 429);
  }

  if (action === "digest") {
    return await handleDigest(admin, book, userID, body);
  }
  return await handleAudio(admin, book, userID, body);
});

async function handleDigest(
  admin: SupabaseClient,
  book: BookInput,
  userID: string,
  body: RequestBody,
): Promise<Response> {
  const outcome = await claim(admin, "claim_digest", {
    p_book_id: book.id,
    p_title: book.title,
    p_author: book.author,
    p_angle: book.angle,
    p_user: userID,
  });

  if (outcome === "ready") {
    await warnOnTitleMismatch(admin, book);
    return json({ status: "ready" }, 200);
  }
  if (outcome === "in_progress") {
    return json({ status: "generating" }, 200);
  }
  if (outcome !== "claimed") {
    return json({ error: "Could not claim digest generation." }, 500);
  }

  const openaiKey = body.openaiKey?.trim();
  if (!openaiKey) {
    await admin
      .from("digests")
      .update({ status: "failed", error: "No OpenAI key was provided.", claim_expires_at: null })
      .eq("book_id", book.id);
    return json({ error: "An OpenAI API key is required to generate this digest." }, 400);
  }

  await logRequest(admin, userID, book.id, "digest");

  // Background mode: OpenAI runs the generation on its side and we only keep
  // the response id. Later `check` calls collect the result, so nothing
  // depends on this isolate staying alive.
  try {
    const started = await startDigestGeneration(book, openaiKey, body.model);
    await admin
      .from("digests")
      .update({ openai_response_id: started.responseID, model: started.model })
      .eq("book_id", book.id);
  } catch (error) {
    const message = scrubError(error, [openaiKey]);
    await admin
      .from("digests")
      .update({
        status: "failed",
        error: message,
        openai_response_id: null,
        claim_expires_at: null,
      })
      .eq("book_id", book.id);
    return json({ error: message }, 502);
  }

  return json({ status: "generating" }, 202);
}

// Poll a digest that is generating in OpenAI background mode. Whichever check
// first observes a terminal state writes it to the row; the caller's key is
// needed to read the response and is never persisted, same as for generation.
async function handleCheck(
  admin: SupabaseClient,
  book: BookInput,
  body: RequestBody,
): Promise<Response> {
  const { data: row, error } = await admin
    .from("digests")
    .select("status, error, openai_response_id")
    .eq("book_id", book.id)
    .maybeSingle();

  if (error) {
    return json({ error: "Could not read digest status." }, 500);
  }
  if (!row) {
    return json({ status: "none" }, 200);
  }
  if (row.status === "ready") {
    return json({ status: "ready" }, 200);
  }
  if (row.status === "failed") {
    return json({ status: "failed", error: row.error ?? "Digest generation failed." }, 200);
  }

  const openaiKey = body.openaiKey?.trim();
  if (!row.openai_response_id || !openaiKey) {
    // Nothing to poll (row predates background mode) or nothing to poll
    // with — report the stored status; another device's checks or the claim
    // expiry will move the row on.
    return json({ status: "generating" }, 200);
  }

  const result = await checkDigestGeneration(row.openai_response_id, openaiKey);

  if (result.state === "completed") {
    const sanitized = sanitize(result.text);
    if (!sanitized) {
      await admin
        .from("digests")
        .update({
          status: "failed",
          error: "OpenAI returned an empty digest.",
          openai_response_id: null,
          claim_expires_at: null,
        })
        .eq("book_id", book.id)
        .eq("status", "generating");
      return json({ status: "failed", error: "OpenAI returned an empty digest." }, 200);
    }
    await admin
      .from("digests")
      .update({
        status: "ready",
        digest_text: sanitized,
        error: null,
        claim_expires_at: null,
      })
      .eq("book_id", book.id)
      .eq("status", "generating");
    return json({ status: "ready" }, 200);
  }

  if (result.state === "failed") {
    const message = scrubError(new Error(result.message), [openaiKey]);
    await admin
      .from("digests")
      .update({
        status: "failed",
        error: message,
        openai_response_id: null,
        claim_expires_at: null,
      })
      .eq("book_id", book.id)
      .eq("status", "generating");
    return json({ status: "failed", error: message }, 200);
  }

  return json({ status: "generating" }, 200);
}

async function handleAudio(
  admin: SupabaseClient,
  book: BookInput,
  userID: string,
  body: RequestBody,
): Promise<Response> {
  const outcome = await claim(admin, "claim_audio", {
    p_book_id: book.id,
    p_user: userID,
  });

  if (outcome === "ready") {
    return json({ status: "ready" }, 200);
  }
  if (outcome === "in_progress") {
    return json({ status: "generating" }, 200);
  }
  if (outcome === "no_digest") {
    return json({ error: "The digest text must be generated before audio." }, 409);
  }
  if (outcome !== "claimed") {
    return json({ error: "Could not claim audio generation." }, 500);
  }

  const elevenLabsKey = body.elevenLabsKey?.trim();
  if (!elevenLabsKey) {
    await admin
      .from("digests")
      .update({
        audio_status: "failed",
        audio_error: "No ElevenLabs key was provided.",
        audio_claim_expires_at: null,
      })
      .eq("book_id", book.id);
    return json({ error: "An ElevenLabs API key is required to generate audio." }, 400);
  }

  await logRequest(admin, userID, book.id, "audio");
  EdgeRuntime.waitUntil(runAudioJob(admin, book.id, elevenLabsKey));
  return json({ status: "generating" }, 202);
}

async function runAudioJob(
  admin: SupabaseClient,
  bookID: string,
  elevenLabsKey: string,
): Promise<void> {
  try {
    const { data, error } = await admin
      .from("digests")
      .select("digest_text")
      .eq("book_id", bookID)
      .single();
    if (error || !data?.digest_text) {
      throw new Error("Digest text is missing.");
    }

    const chunks = chunkText(data.digest_text);
    if (chunks.length === 0) {
      throw new Error("Digest text produced no audio chunks.");
    }

    const audioParts: Uint8Array[] = [];
    for (const chunk of chunks) {
      audioParts.push(await synthesizeChunk(chunk, elevenLabsKey, VOICE_ID, SPEECH_MODEL));
    }
    const combined = concatMp3(audioParts);

    const storagePath = `${bookID}.mp3`;
    const upload = await admin.storage
      .from(AUDIO_BUCKET)
      .upload(storagePath, combined, { contentType: "audio/mpeg", upsert: true });
    if (upload.error) {
      throw new Error(`Audio upload failed: ${upload.error.message}`);
    }

    await admin
      .from("digests")
      .update({
        audio_status: "ready",
        audio_storage_path: storagePath,
        audio_error: null,
        audio_claim_expires_at: null,
      })
      .eq("book_id", bookID);
  } catch (error) {
    console.error(`Audio job failed for ${bookID}`);
    await admin
      .from("digests")
      .update({
        audio_status: "failed",
        audio_error: scrubError(error, [elevenLabsKey]),
        audio_claim_expires_at: null,
      })
      .eq("book_id", bookID);
  }
}

async function authenticatedUserID(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return null;

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    resolveApiKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY"),
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

function validateBook(book: RequestBody["book"]): BookInput | null {
  if (!book) return null;
  const { id, title, author } = book;
  if (typeof id !== "string" || !BOOK_ID_PATTERN.test(id)) return null;
  if (typeof title !== "string" || title.length === 0 || title.length > 300) return null;
  if (typeof author !== "string" || author.length === 0 || author.length > 200) return null;

  const angle = typeof book.angle === "string" ? book.angle.slice(0, 2000) : "";
  return { id, title, author, angle };
}

async function withinRateLimit(admin: SupabaseClient, userID: string): Promise<boolean> {
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count, error } = await admin
    .from("generation_requests")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userID)
    .gte("created_at", oneHourAgo);

  if (error) {
    console.error("Rate limit check failed; allowing request.");
    return true;
  }
  return (count ?? 0) < RATE_LIMIT_PER_HOUR;
}

async function logRequest(
  admin: SupabaseClient,
  userID: string,
  bookID: string,
  kind: "digest" | "audio",
): Promise<void> {
  await admin
    .from("generation_requests")
    .insert({ user_id: userID, book_id: bookID, kind });
}

async function claim(
  admin: SupabaseClient,
  fn: "claim_digest" | "claim_audio",
  args: Record<string, string>,
): Promise<string | null> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) {
    console.error(`${fn} RPC failed: ${error.message}`);
    return null;
  }
  return data?.[0]?.outcome ?? null;
}

async function warnOnTitleMismatch(admin: SupabaseClient, book: BookInput): Promise<void> {
  const { data } = await admin
    .from("digests")
    .select("title")
    .eq("book_id", book.id)
    .single();
  if (data && data.title !== book.title) {
    console.warn(
      `Possible slug collision for '${book.id}': stored title '${data.title}' vs requested '${book.title}'.`,
    );
  }
}

// Errors are persisted to client-readable columns — remove key material and
// cap length before they leave this process.
function scrubError(error: unknown, secrets: string[]): string {
  let message = error instanceof Error ? error.message : String(error);
  for (const secret of secrets) {
    if (secret) {
      message = message.split(secret).join("[redacted]");
    }
  }
  message = message.replace(/sk-[A-Za-z0-9_-]{8,}/g, "[redacted]");
  return message.slice(0, 500);
}

function json(payload: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
