import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const minChars = 20;
const maxChars = 50_000;
const clientTodayRe = /^\d{4}-\d{2}-\d{2}$/;

export type HomeworkType = "text" | "vocabulary" | "math";

export interface MetadataPayload {
  title: string;
  subject: string;
  dueAtIso: string | null;
  homeworkType: HomeworkType;
  confidence: number;
}

function stripCodeFence(s: string): string {
  let t = s.trim();
  const m = /^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/m.exec(t);
  if (m) return m[1].trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  }
  return t;
}

const isoDateRe = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Parsar och validerar AI-svaret till ett MetadataPayload.
 * Exporteras som ren funktion så att den är testbar utan Firebase.
 */
export function parseMetadataPayload(
  raw: string,
  knownSubjects: string[],
): MetadataPayload {
  const clipped = stripCodeFence(raw);
  let parsed: unknown;
  try {
    parsed = JSON.parse(clipped);
  } catch {
    throw new Error("json_parse");
  }
  if (parsed == null || typeof parsed !== "object") {
    throw new Error("bad_shape");
  }
  const p = parsed as Record<string, unknown>;

  const rawTitle = typeof p["title"] === "string" ? p["title"].trim() : "";
  const title = rawTitle.slice(0, 60) || "Ny läxa";

  let subject = typeof p["subject"] === "string" ? p["subject"].trim() : "";
  if (subject === "") subject = "Ämne";
  if (knownSubjects.length > 0) {
    const lower = subject.toLowerCase();
    const match = knownSubjects.find((s) => s.toLowerCase() === lower);
    if (match) subject = match;
  }

  const rawDue = p["dueAtIso"];
  let dueAtIso: string | null = null;
  if (typeof rawDue === "string" && isoDateRe.test(rawDue.trim())) {
    dueAtIso = rawDue.trim();
  }

  const rawType = p["homeworkType"];
  const allowed: HomeworkType[] = ["text", "vocabulary", "math"];
  const homeworkType: HomeworkType =
    typeof rawType === "string" && allowed.includes(rawType as HomeworkType)
      ? (rawType as HomeworkType)
      : "text";

  const rawConf = p["confidence"];
  let confidence =
    typeof rawConf === "number" && isFinite(rawConf) ? rawConf : 0.5;
  if (confidence < 0) confidence = 0;
  if (confidence > 1) confidence = 1;

  return { title, subject, dueAtIso, homeworkType, confidence };
}

export const suggestHomeworkMetadata = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }

    const data = request.data;
    if (data == null || typeof data !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop: saknar data.");
    }

    const d = data as Record<string, unknown>;

    const rawText = d["text"];
    if (typeof rawText !== "string") {
      throw new HttpsError("invalid-argument", "Fältet text måste vara en sträng.");
    }
    const text = rawText.trim();
    if (text.length < minChars || text.length > maxChars) {
      throw new HttpsError(
        "invalid-argument",
        `Texten ska vara ${minChars}–${maxChars} tecken (du har ${text.length}).`,
      );
    }

    const rawToday = d["clientToday"];
    if (typeof rawToday !== "string" || !clientTodayRe.test(rawToday.trim())) {
      throw new HttpsError(
        "invalid-argument",
        "Fältet clientToday måste vara ett datum på formatet YYYY-MM-DD.",
      );
    }
    const clientToday = rawToday.trim();

    const rawSubjects = d["knownSubjects"];
    const knownSubjects: string[] = [];
    if (Array.isArray(rawSubjects)) {
      for (const s of rawSubjects) {
        if (typeof s === "string" && s.trim().length > 0) {
          knownSubjects.push(s.trim());
        }
      }
    }
    const subjectsList =
      knownSubjects.length > 0
        ? `Välj helst ämne ur denna lista: ${knownSubjects.slice(0, 30).join(", ")}.`
        : "Ange ett kort ämnesnamn med stor begynnelsebokstav.";

    const systemPrompt = `Du är en hjälp för svenska skolläxor åk 2–9.
Analysera läxtexten och returnera metadata i exakt JSON — inget annat, inga kodstaket, ingen omgivande text.

Schema:
{"title": string, "subject": string, "dueAtIso": string|null, "homeworkType": "text"|"vocabulary"|"math", "confidence": number}

Regler:
- title: max 60 tecken, konkret och beskrivande (t.ex. "Glosor v.38 – engelska", "SO: Vasatiden s. 42–45").
- subject: ${subjectsList}
- dueAtIso: tolka relativa datum relativt idag (${clientToday}). Svensk veckokonvention (vecka börjar måndag). "till fredag" = nästa fredag. "v. NN" = ISO-vecka NN, ta fredag den veckan. Datum i förflutet = null. Tvetydigt = null. Format: YYYY-MM-DD.
- homeworkType: listor med ordpar/översättningar → "vocabulary"; övervägande räkneuppgifter/tal → "math"; annars "text".
- confidence: 0.0–1.0, hur säker du är.`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    let rawAnswer: string;
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 400,
        system: systemPrompt,
        messages: [{ role: "user", content: text }],
      });
      rawAnswer = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[suggestHomeworkMetadata] anthropic", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte tolka läxan just nu. Försök igen senare.",
      );
    }

    let payload: MetadataPayload;
    try {
      payload = parseMetadataPayload(rawAnswer, knownSubjects);
    } catch (e) {
      logger.error("[suggestHomeworkMetadata] parse_failed", { rawAnswer, e });
      throw new HttpsError(
        "unavailable",
        "Kunde inte tolka läxan just nu. Försök igen senare.",
      );
    }

    return payload;
  },
);
