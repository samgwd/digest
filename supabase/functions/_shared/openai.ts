// OpenAI Responses API in background mode. Generation is started with
// `background: true` and collected later via GET polls, so no edge-function
// invocation has to stay alive for the whole generation (hosted isolates are
// killed after a few minutes, which used to strand rows in 'generating').

import { type BookInput, instructions, prompt } from "./prompts.ts";

const ENDPOINT = "https://api.openai.com/v1/responses";
const DEFAULT_MODEL = "gpt-5.5";
const REQUEST_TIMEOUT_MS = 30_000;

interface ResponsesResponse {
  id?: string;
  status?: string;
  error?: { message?: string } | null;
  output_text?: string;
  output?: Array<{ content?: Array<{ text?: string }> }>;
}

export type DigestCheckResult =
  | { state: "in_progress" }
  | { state: "completed"; text: string }
  | { state: "failed"; message: string };

export async function startDigestGeneration(
  book: BookInput,
  apiKey: string,
  model?: string,
): Promise<{ responseID: string; model: string }> {
  const resolvedModel = model?.trim() || DEFAULT_MODEL;

  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: resolvedModel,
      instructions,
      input: prompt(book),
      reasoning: { effort: "low" },
      text: { format: { type: "text" }, verbosity: "high" },
      max_output_tokens: 7000,
      background: true,
      store: true,
    }),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(await httpErrorMessage(response));
  }

  const decoded = (await response.json()) as ResponsesResponse;
  if (!decoded.id) {
    throw new Error("OpenAI did not return a background response id.");
  }
  return { responseID: decoded.id, model: resolvedModel };
}

export async function checkDigestGeneration(
  responseID: string,
  apiKey: string,
): Promise<DigestCheckResult> {
  const response = await fetch(`${ENDPOINT}/${encodeURIComponent(responseID)}`, {
    headers: { "Authorization": `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  // An unreadable poll (a different account's key, a transient OpenAI error)
  // says nothing about the job itself — report in-progress and let the claim
  // expiry deal with jobs nobody can ever collect.
  if (!response.ok) {
    return { state: "in_progress" };
  }

  const decoded = (await response.json()) as ResponsesResponse;

  switch (decoded.status) {
    case "queued":
    case "in_progress":
      return { state: "in_progress" };
    case "completed":
    case "incomplete": {
      // 'incomplete' means the output hit max_output_tokens; keep the text,
      // matching what the previous synchronous call would have returned.
      const text = extractText(decoded);
      if (text) {
        return { state: "completed", text };
      }
      return { state: "failed", message: "OpenAI returned an empty digest." };
    }
    default:
      return {
        state: "failed",
        message: decoded.error?.message
          ? `OpenAI error: ${decoded.error.message}`
          : `OpenAI generation ended with status '${decoded.status ?? "unknown"}'.`,
      };
  }
}

function extractText(decoded: ResponsesResponse): string {
  const outputText = decoded.output_text?.trim();
  if (outputText) {
    return outputText;
  }
  return (decoded.output ?? [])
    .flatMap((item) => item.content ?? [])
    .map((content) => content.text)
    .filter((text): text is string => typeof text === "string")
    .join("\n\n")
    .trim();
}

async function httpErrorMessage(response: Response): Promise<string> {
  let message = `OpenAI returned status ${response.status}.`;
  try {
    const parsed = await response.json();
    if (typeof parsed?.error?.message === "string") {
      message = `OpenAI error (status ${response.status}): ${parsed.error.message}`;
    }
  } catch {
    // keep the generic status message
  }
  return message;
}
