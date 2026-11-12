import Anthropic from "@anthropic-ai/sdk";
import { FieldValue } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";
import { mergedExtractedForQaParse } from "./homeworkSourceText";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const maxPairs = 50;

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

function squashWs(s: string): string {
  return s.trim().replace(/\s+/g, " ");
}

function isAnswerInSource(answer: string, source: string): boolean {
  const a = squashWs(answer);
  const h = squashWs(source);
  if (a.length < 1) return false;
  return h.includes(a);
}

type Pair = { question: string; answer: string };

function parsePairsPayload(rawContent: string): { pairs: Pair[] } {
  const clipped = stripCodeFence(rawContent);
  try {
    const parsed: unknown = JSON.parse(clipped);
    if (
      parsed == null ||
      typeof parsed !== "object" ||
      !("pairs" in parsed) ||
      !Array.isArray((parsed as { pairs: unknown }).pairs)
    ) {
      throw new Error("bad shape");
    }
    const arr = (parsed as { pairs: unknown[] }).pairs.map((entry) => {
      if (
        entry == null ||
        typeof entry !== "object" ||
        !("question" in entry && "answer" in entry)
      ) {
        throw new Error("bad pair entry");
      }
      const ee = entry as { question?: unknown; answer?: unknown };
      return {
        question: typeof ee.question === "string" ? ee.question : "",
        answer: typeof ee.answer === "string" ? ee.answer : "",
      };
    });
    return { pairs: arr };
  } catch {
    throw new Error("parse");
  }
}

const systemPrompt = `Du extraherar frågor och svar som redan finns i svenskt skolmaterial.
Returnera ENDAST giltig JSON i exakt detta format, inget annat:
{"pairs": [{"question": "...", "answer": "..."}, ...]}

Regler:
- question = frågan ordagrant som i texten, utan numrering på raden (ingen "1." eller "Fråga 3:").
- answer = svaret ordagrant, utan prefix som "Svar:" i själva svarens text.
- Behåll originalformulering även om språket är ogrammatiskt.
- Hoppa över rader som inte är fråga+svar-par (rubriker, instruktioner, brödtext utan svar).
- Om inga par hittas: returnera {"pairs": []}.`;

export const parseQuestionsAndAnswers = onCall(
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
    const hwFamily = hw.familyId;
    if (hwFamily !== userFamilyId) {
      throw new HttpsError("permission-denied", "Tillhör inte din familj.");
    }

    const hwRec = hw as Record<string, unknown>;
    const extractedText = mergedExtractedForQaParse(hwRec);
    if (!extractedText) {
      throw new HttpsError(
        "failed-precondition",
        "Läxan saknar extraherad text (märk Q&A-bilagan eller extrahera text).",
      );
    }

    const homeworkTitle =
      typeof hw.title === "string" && hw.title.trim() !== ""
        ? hw.title.trim()
        : "Fragor";
    const homeworkSubjectRaw = hw.subject;
    const homeworkSubject =
      typeof homeworkSubjectRaw === "string" &&
      homeworkSubjectRaw.trim() !== ""
        ? homeworkSubjectRaw.trim()
        : null;

    const userMessage = `Här är materialet (endast frågor/svar-delen):\n\n${extractedText}`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    let textOut = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 8000,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      });
      textOut = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[parseQuestionsAndAnswers] anthropic", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte tolka materialet just nu. Försök igen senare.",
      );
    }

    let pairs: Pair[];
    try {
      const parsed = parsePairsPayload(textOut);
      pairs = parsed.pairs.map((p) => ({
        question: p.question.trim(),
        answer: p.answer.trim(),
      }));
    } catch {
      logger.error("[parseQuestionsAndAnswers] json_parse_failed", { len: textOut.length });
      throw new HttpsError("internal", "Kunde inte tolka AI-svar.");
    }

    const valid: Pair[] = [];
    for (const p of pairs) {
      if (p.question.length < 2 || p.answer.length < 2) continue;
      if (!isAnswerInSource(p.answer, extractedText)) {
        logger.warn("[parseQuestionsAndAnswers] drop_pair_answer_not_in_source", {
          answerLen: p.answer.length,
        });
        continue;
      }
      valid.push(p);
      if (valid.length >= maxPairs) break;
    }

    if (valid.length < 1) {
      throw new HttpsError(
        "failed-precondition",
        "Hittade inga frågor med svar i materialet.",
      );
    }

    const deckTitle = `${homeworkTitle} (frågor från materialet)`;
    const deckRef = db.collection("decks").doc();
    const deckId = deckRef.id;
    const batch = db.batch();

    batch.set(deckRef, {
      familyId: userFamilyId,
      homeworkId,
      title: deckTitle,
      subject: homeworkSubject,
      cardCount: valid.length,
      cardSource: "extracted",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (const p of valid) {
      const cardRef = db.collection("flashcards").doc();
      batch.set(cardRef, {
        deckId,
        familyId: userFamilyId,
        front: p.question,
        back: p.answer,
        sourceQuote: p.answer,
        source: "extracted",
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

    logger.info("[parseQuestionsAndAnswers] done", {
      deckId,
      cardCount: valid.length,
    });

    return { deckId, cardCount: valid.length };
  },
);
