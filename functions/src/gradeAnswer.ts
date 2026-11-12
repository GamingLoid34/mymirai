import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

type Verdict = "correct" | "partial" | "wrong";

function stripCodeFence(s: string): string {
  let t = s.trim();
  const m = /^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/m.exec(t);
  if (m) return m[1].trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  }
  return t;
}

function parseGradeResponse(raw: string): { verdict: Verdict; feedback: string } {
  const clipped = stripCodeFence(raw);
  let parsed: unknown;
  try {
    parsed = JSON.parse(clipped);
  } catch {
    throw new Error("parse");
  }
  if (parsed == null || typeof parsed !== "object") {
    throw new Error("shape");
  }
  const verdict = (parsed as { verdict?: unknown }).verdict;
  const feedback = (parsed as { feedback?: unknown }).feedback;
  if (verdict !== "correct" && verdict !== "partial" && verdict !== "wrong") {
    throw new Error("verdict");
  }
  if (typeof feedback !== "string" || feedback.trim() === "") {
    throw new Error("feedback");
  }
  return { verdict, feedback: feedback.trim() };
}

export const gradeAnswer = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const body = request.data;
    if (body == null || typeof body !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop: saknar data.");
    }
    const deckId = typeof (body as { deckId?: unknown }).deckId === "string"
      ? (body as { deckId: string }).deckId.trim()
      : "";
    const cardId = typeof (body as { cardId?: unknown }).cardId === "string"
      ? (body as { cardId: string }).cardId.trim()
      : "";
    const userAnswer = typeof (body as { userAnswer?: unknown }).userAnswer === "string"
      ? (body as { userAnswer: string }).userAnswer.trim()
      : "";
    if (!deckId || !cardId || userAnswer.length < 1) {
      throw new HttpsError("invalid-argument", "deckId, cardId och userAnswer krävs.");
    }

    logger.info(`[gradeAnswer] start cardId=${cardId}`);

    const db = getDb();
    const userSnap = await db.doc(`users/${uid}`).get();
    const userFamilyId = userSnap.data()?.familyId;
    if (typeof userFamilyId !== "string" || userFamilyId === "") {
      throw new HttpsError("failed-precondition", "Saknar familj för användaren.");
    }

    const cardSnap = await db.doc(`flashcards/${cardId}`).get();
    if (!cardSnap.exists) {
      throw new HttpsError("not-found", "Kortet hittades inte.");
    }
    const card = cardSnap.data() ?? {};
    if (card.familyId !== userFamilyId) {
      throw new HttpsError("permission-denied", "Kortet tillhör inte din familj.");
    }
    if (card.deckId !== deckId) {
      throw new HttpsError("invalid-argument", "Kortet matchar inte leken.");
    }
    const front = typeof card.front === "string" ? card.front.trim() : "";
    const back = typeof card.back === "string" ? card.back.trim() : "";
    if (!front || !back) {
      throw new HttpsError("failed-precondition", "Kortet saknar fråga eller facit.");
    }

    const sys = `Du är lärare för svenska barn i grundskolan. Bedöm barnets svar mot facit.
Returnera ENBART giltig JSON:
{"verdict":"correct"|"partial"|"wrong","feedback":"..."}
Regler:
- "correct": barnet kan kärnan.
- "partial": halvt rätt eller saknar nyans.
- "wrong": inte alls rätt eller blankt.
- feedback: 1-2 meningar, vänligt, konkret vad som var rätt/saknades.`;
    const userPrompt = `Fråga: ${front}\nFacit: ${back}\nBarnets svar: ${userAnswer}`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let textOut = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 300,
        system: sys,
        messages: [{ role: "user", content: userPrompt }],
      });
      textOut = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[gradeAnswer] anthropic", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte bedöma svaret just nu. Försök igen senare.",
      );
    }

    let parsed: { verdict: Verdict; feedback: string };
    try {
      parsed = parseGradeResponse(textOut);
    } catch {
      throw new HttpsError("internal", "Kunde inte tolka AI-svar.");
    }

    logger.info(
      `[gradeAnswer] done verdict=${parsed.verdict} answerLen=${userAnswer.length}`,
    );
    return parsed;
  },
);
