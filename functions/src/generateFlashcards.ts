import Anthropic from "@anthropic-ai/sdk";
import { FieldValue } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";
import { mergedExtractedExcludingQa } from "./homeworkSourceText";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

function coerceCount(raw: unknown): number {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    const n = Math.floor(raw);
    if (n < 1) return 10;
    return Math.min(n, 15);
  }
  return 10;
}

function stripCodeFence(s: string): string {
  let t = s.trim();
  const m = /^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/m.exec(t);
  if (m) {
    return m[1].trim();
  }
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  }
  return t;
}

type ParsedCard = { front: string; back: string; sourceQuote?: string | null };

function parseCardsPayload(rawContent: string): { cards: ParsedCard[] } {
  const clipped = stripCodeFence(rawContent);
  try {
    const parsed: unknown = JSON.parse(clipped);
    if (
      parsed == null ||
      typeof parsed !== "object" ||
      !("cards" in parsed) ||
      !Array.isArray((parsed as { cards: unknown }).cards)
    ) {
      throw new Error("bad shape");
    }
    const arr = (parsed as { cards: unknown[] }).cards.map((entry) => {
      if (
        entry == null ||
        typeof entry !== "object" ||
        !("front" in entry && "back" in entry)
      ) {
        throw new Error("bad card entry");
      }
      const ee = entry as { front?: unknown; back?: unknown; sourceQuote?: unknown };
      const sq =
        typeof ee.sourceQuote === "string" ? ee.sourceQuote.trim() : "";
      return {
        front: typeof ee.front === "string" ? ee.front : "",
        back: typeof ee.back === "string" ? ee.back : "",
        sourceQuote: sq.length >= 12 ? sq : undefined,
      };
    });
    return { cards: arr };
  } catch {
    throw new Error("parse");
  }
}

function squashWs(s: string): string {
  return s.trim().replace(/\s+/g, " ");
}

/** Källcitat måste vara verbatim del av läxans underlag (Chunk X). */
function verifiedSourceQuote(
  quote: string | null | undefined,
  haystack: string,
): string | undefined {
  if (!quote || quote.trim().length < 12) return undefined;
  const q = squashWs(quote);
  const h = squashWs(haystack);
  if (q.length > 580) return undefined;
  if (!h.includes(q)) return undefined;
  return quote.trim();
}

function citationHaystack(summary: string, extracted: string): string {
  const s = squashWs(summary);
  const e = squashWs(extracted);
  return `${s} ${e}`;
}

export const generateFlashcards = onCall(
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

    const rawHomeworkId = (body as { homeworkId?: unknown }).homeworkId;
    if (typeof rawHomeworkId !== "string" || rawHomeworkId.trim() === "") {
      throw new HttpsError("invalid-argument", "homeworkId saknas.");
    }
    const homeworkId = rawHomeworkId.trim();
    const count = coerceCount((body as { count?: unknown }).count);

    logger.info(`[generateFlashcards] start homeworkId=${homeworkId} count=${count}`, {
      uid,
    });

    const db = getDb();

    const userSnap = await db.doc(`users/${uid}`).get();
    const userFamilyId = userSnap.data()?.familyId;
    if (typeof userFamilyId !== "string" || userFamilyId === "") {
      throw new HttpsError("failed-precondition", "Saknar familj för användaren.");
    }

    const hwRef = db.doc(`homework/${homeworkId}`);
    const hwSnap = await hwRef.get();
    if (!hwSnap.exists) {
      throw new HttpsError("not-found", "Läxan hittades inte.");
    }
    const hw = hwSnap.data() ?? {};
    const hwRec = hw as Record<string, unknown>;
    const hwFamily = hw.familyId;
    if (hwFamily !== userFamilyId) {
      throw new HttpsError(
        "permission-denied",
        "Tillhör inte din familj.",
      );
    }

    const summary = typeof hw.summary === "string" ? hw.summary.trim() : "";
    if (!summary) {
      throw new HttpsError(
        "failed-precondition",
        "Läxan saknar sammanfattning. Generera den först.",
      );
    }

    const extractedRaw = mergedExtractedExcludingQa(hwRec);
    const extractedSnippet =
      extractedRaw.length > 12_000
        ? `${extractedRaw.slice(0, 12_000)}\n…`
        : extractedRaw;

    const homeworkTitle =
      typeof hw.title === "string" && hw.title.trim() !== ""
        ? hw.title.trim()
        : "Flashcards";
    const homeworkSubjectRaw = hw.subject;
    const homeworkSubject =
      typeof homeworkSubjectRaw === "string" &&
      homeworkSubjectRaw.trim() !== ""
        ? homeworkSubjectRaw.trim()
        : null;

    const sys = `Du är en pedagogisk hjälp som skapar flashcards för svenska barn i grundskolan.

Skapa exakt ${count} flashcards utifrån materialet nedan.

Regler:
- Varje kort har EN tydlig fråga (front) och EN tydlig faktisk svar (back).
- Frågorna ska testa förståelse — undvik triviala datumfrågor om de inte är centrala.
- Variera frågetyper: vad, varför, hur, jämför.
- Svaren ska vara korta — 1-2 meningar max.
- Språk på barnvänlig svenska, men inte barnsligt.
- Inga "true/false"-frågor.
- SOURCEQUOTE (chunk X): För VARJE kort ange sourceQuote — en KORT ordagrann citatruta (max ~400 tecken, högst två meningar)
  kopierad direkt ur KÄLLTEXTEN om den finns. Citatet ska stödja svaret (back).
  Om källtext saknas eller inget passande citat finns: sätt sourceQuote till "".

Returnera ENBART giltig JSON i exakt detta format:
{"cards": [{"front":"...","back":"...","sourceQuote":"..."}, ...]}`;

    const materialBlock = extractedSnippet
      ? `Sammanfattning:\n${summary}\n\nKälltext:\n${extractedSnippet}`
      : `Sammanfattning:\n${summary}\n\n(Ingen källtext — sätt sourceQuote till "" på alla kort.)`;

    const hay = citationHaystack(summary, extractedRaw);

    const userPrompt = `${materialBlock}\n\nSkapa ${count} flashcards.`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    let textOut = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: sys,
        messages: [
          {
            role: "user",
            content: userPrompt,
          },
        ],
      });
      textOut = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[generateFlashcards] anthropic", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte skapa flashcards just nu. Försök igen senare.",
      );
    }

    let trimmed: { front: string; back: string; sourceQuote?: string }[];
    try {
      const parsed = parseCardsPayload(textOut);
      if (parsed.cards.length > count) {
        trimmed = parsed.cards.slice(0, count).map((c) => ({
          front: c.front.trim(),
          back: c.back.trim(),
          sourceQuote: verifiedSourceQuote(c.sourceQuote, hay),
        }));
      } else {
        trimmed = parsed.cards.map((c) => ({
          front: c.front.trim(),
          back: c.back.trim(),
          sourceQuote: verifiedSourceQuote(c.sourceQuote, hay),
        }));
      }
    } catch {
      logger.error("[generateFlashcards] json_parse_failed length", textOut.length);
      throw new HttpsError(
        "internal",
        "Kunde inte tolka AI-svar",
      );
    }

    if (trimmed.length < 3 || trimmed.some((c) => c.front === "" || c.back === "")) {
      throw new HttpsError(
        "internal",
        "Otillräckligt antal giltiga flashcards.",
      );
    }

    const deckRef = db.collection("decks").doc();
    const deckId = deckRef.id;
    const batch = db.batch();

    batch.set(deckRef, {
      familyId: userFamilyId,
      homeworkId,
      title: homeworkTitle,
      subject: homeworkSubject,
      cardCount: trimmed.length,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (const c of trimmed) {
      const cardRef = db.collection("flashcards").doc();
      const citation =
        typeof c.sourceQuote === "string" && c.sourceQuote.trim() !== ""
          ? c.sourceQuote.trim()
          : null;
      batch.set(cardRef, {
        deckId,
        familyId: userFamilyId,
        front: c.front,
        back: c.back,
        ...(citation !== null ? { sourceQuote: citation } : {}),
        source: "ai",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        repetitions: 0,
        easeFactor: 2.5,
        intervalDays: 0,
        lastReviewedAt: null,
        nextReviewAt: null,
        lastQuizVerdict: null,
        lastQuizAt: null,
      });
    }

    batch.update(hwRef, {
      linkedDeckId: deckId,
      updatedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    logger.info(
      `[generateFlashcards] done deckId=${deckId} cardCount=${trimmed.length}`,
      {
        homeworkIdLen: homeworkId.length,
      },
    );

    return {
      deckId,
      cards: trimmed,
    };
  },
);
