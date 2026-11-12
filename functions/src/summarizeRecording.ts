import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

function stripCodeFence(s: string): string {
  let t = s.trim();
  const m = /^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/m.exec(t);
  if (m) return m[1].trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  }
  return t;
}

interface RecordingSummaryShape {
  summary: string;
  decisions: string[];
  actionItems: string[];
  openQuestions: string[];
}

function parseSummaryResponse(raw: string): RecordingSummaryShape {
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
  const p = parsed as Record<string, unknown>;
  const summary = typeof p.summary === "string" ? p.summary.trim() : "";
  if (!summary) throw new Error("summary");
  const toStringArray = (v: unknown): string[] =>
    Array.isArray(v)
      ? v.filter((x): x is string => typeof x === "string" && x.trim() !== "").map((x) => x.trim())
      : [];
  return {
    summary,
    decisions: toStringArray(p.decisions),
    actionItems: toStringArray(p.actionItems),
    openQuestions: toStringArray(p.openQuestions),
  };
}

function formatSummaryText(s: RecordingSummaryShape): string {
  const sections: string[] = [`Sammanfattning\n${s.summary}`];
  if (s.decisions.length > 0) {
    sections.push(`Beslut\n${s.decisions.map((d) => `• ${d}`).join("\n")}`);
  }
  if (s.actionItems.length > 0) {
    sections.push(`Att göra\n${s.actionItems.map((d) => `• ${d}`).join("\n")}`);
  }
  if (s.openQuestions.length > 0) {
    sections.push(`Öppna frågor\n${s.openQuestions.map((d) => `• ${d}`).join("\n")}`);
  }
  return sections.join("\n\n");
}

export const summarizeRecording = onCall(
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
    const rawDocId = (request.data as { documentId?: unknown } | null)?.documentId;
    const documentId = typeof rawDocId === "string" ? rawDocId.trim() : "";
    if (!documentId) {
      throw new HttpsError("invalid-argument", "documentId krävs.");
    }

    const db = getDb();
    const docRef = db.doc(`documents/${documentId}`);
    const docSnap = await docRef.get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Dokumentet finns inte.");
    }
    const doc = docSnap.data() ?? {};
    const ownerUid = typeof doc.ownerUid === "string" ? doc.ownerUid : "";
    if (ownerUid !== uid) {
      throw new HttpsError("permission-denied", "Äger inte dokumentet.");
    }
    const extractedText = typeof doc.extractedText === "string" ? doc.extractedText.trim() : "";
    if (!extractedText) {
      throw new HttpsError("failed-precondition", "Dokumentet saknar transkript att sammanfatta.");
    }

    const sys = `Du sammanfattar mötestranskript på svenska (behåll citat på originalspråket om mötet var på engelska).
Returnera ENBART giltig JSON:
{"summary":"...","decisions":["..."],"actionItems":["..."],"openQuestions":["..."]}
Regler:
- summary: 3-6 meningar, tät och saklig.
- decisions/actionItems/openQuestions: korta punkter, tom lista om inget relevant hittas.
- Hitta inte på information som inte finns i transkriptet.`;
    const userPrompt = `Transkript:\n\n${extractedText}`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let textOut = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 1200,
        system: sys,
        messages: [{ role: "user", content: userPrompt }],
      });
      textOut = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[summarizeRecording] anthropic", e);
      throw new HttpsError("unavailable", "Kunde inte skapa sammanfattning just nu. Försök igen senare.");
    }

    let parsed: RecordingSummaryShape;
    try {
      parsed = parseSummaryResponse(textOut);
    } catch {
      throw new HttpsError("internal", "Kunde inte tolka AI-svar.");
    }

    const formatted = formatSummaryText(parsed);
    await docRef.update({
      summary: formatted,
      updatedAt: new Date(),
    });

    logger.info("[summarizeRecording] ok", { documentId, chars: formatted.length });

    return { summary: formatted };
  },
);
