import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

type CardRow = {
  id: string;
  deckId: string;
  front: string;
  back: string;
  sourceQuote?: string;
};

type QuestionOpen = {
  type: "open";
  cardId: string;
  deckId: string;
  front: string;
};

type QuestionMc = {
  type: "multiple_choice";
  cardId: string;
  deckId: string;
  front: string;
  options: string[];
  correctIndex: number;
  sourceQuote?: string;
};

type QuestionOut = QuestionOpen | QuestionMc;

function stripCodeFence(s: string): string {
  let t = s.trim();
  const m = /^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/m.exec(t);
  if (m) return m[1].trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  }
  return t;
}

function coerceCount(raw: unknown): number {
  if (typeof raw !== "number" || !Number.isFinite(raw)) return 15;
  const n = Math.floor(raw);
  if ([10, 15, 20].includes(n)) return n;
  return Math.min(20, Math.max(10, n));
}

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function parseMc(raw: string): { options: string[]; correctIndex: number } {
  const clipped = stripCodeFence(raw);
  let parsed: unknown;
  try {
    parsed = JSON.parse(clipped);
  } catch {
    throw new Error("parse");
  }
  if (parsed == null || typeof parsed !== "object") throw new Error("shape");
  const options = (parsed as { options?: unknown }).options;
  const ci = (parsed as { correctIndex?: unknown }).correctIndex;
  if (!Array.isArray(options) || options.length !== 4) throw new Error("options");
  const textOpts = options.map((x) =>
    typeof x === "string" ? x.trim() : "",
  ) as string[];
  if (textOpts.some((s) => s.length < 1)) throw new Error("empty");
  if (typeof ci !== "number" || !Number.isInteger(ci) || ci < 0 || ci > 3) {
    throw new Error("index");
  }
  return { options: textOpts, correctIndex: ci };
}

async function fetchCardsForDecks(
  deckIds: string[],
  familyId: string,
): Promise<CardRow[]> {
  const db = getDb();
  const rows: CardRow[] = [];

  await Promise.all(
    deckIds.map(async (deckId) => {
      const snap = await db
        .collection("flashcards")
        .where("deckId", "==", deckId)
        .get();
      for (const d of snap.docs) {
        const data = d.data() ?? {};
        if (data.familyId !== familyId) continue;
        const front = typeof data.front === "string" ? data.front.trim() : "";
        const back = typeof data.back === "string" ? data.back.trim() : "";
        if (!front || !back) continue;
        const sqRaw =
          typeof data.sourceQuote === "string" ? data.sourceQuote.trim() : "";
        rows.push({
          id: d.id,
          deckId,
          front,
          back,
          ...(sqRaw !== "" ? { sourceQuote: sqRaw } : {}),
        });
      }
    }),
  );

  return rows;
}

function fallbackMc(
  correctBack: string,
  otherBacks: string[],
): { options: string[]; correctIndex: number } {
  const uniq = [...new Set(otherBacks.map((x) => x.trim()).filter(Boolean))];
  uniq.sort(() => Math.random() - 0.5);
  const distractors: string[] = [];
  for (const b of uniq) {
    if (b === correctBack) continue;
    if (distractors.length >= 3) break;
    const short =
      b.length > 72 ? `${b.slice(0, 69)}…`.trim()
      : b;
    distractors.push(short);
    if (distractors.length === 3) break;
  }
  while (distractors.length < 3) {
    distractors.push("Jag vet inte");
  }

  let correct = correctBack.length > 72 ? `${correctBack.slice(0, 69)}…` : correctBack;
  if (correct.length < 3) correct = correctBack.slice(0, Math.min(correctBack.length, 72));

  const placement = Math.floor(Math.random() * 4);
  const options: string[] = [];
  let di = 0;
  for (let i = 0; i < 4; i++) {
    if (i === placement) {
      options.push(correct);
    } else {
      options.push(distractors[di] ?? `Alternativ ${di + 1}`);
      di += 1;
    }
  }
  return { options, correctIndex: placement };
}

async function generateMcForCard(
  client: Anthropic,
  card: CardRow,
  fallbackPool: string[],
): Promise<{ options: string[]; correctIndex: number }> {
  const sys = `Du skapar en flervalsfråga för svensk grundskola.
Returnera ENDAST giltig JSON:
{"options":["","","",""],"correctIndex":0}

Regler:
- Exakt fyra svenska svarsalternativ, korta (max ett kort mening per rad).
- Ett är rätt svar och måste täcka samma fakta som Facit (omformulering ok).
- Tre är plausible distraktorer i samma stil och längd.
- Byt slumpmässig ordning: correctIndex är 0–3 för vilket som är det rätta alternativet.`;

  const user = `Fråga (visa för eleven): ${card.front}\nFacit (svara rätt): ${card.back}`;

  let textOut = "";
  try {
    const message = await client.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 450,
      system: sys,
      messages: [{ role: "user", content: user }],
    });
    textOut = message.content
      .map((block) => (block.type === "text" ? block.text : ""))
      .join("")
      .trim();
    return parseMc(textOut);
  } catch (e) {
    logger.warn("[generateTest] anthropic_mc_failed", { cardId: card.id, err: `${e}` });
    const pool = fallbackPool.filter((b) => b !== card.back);
    return fallbackMc(card.back, pool);
  }
}

export const generateTest = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "512MiB",
    timeoutSeconds: 180,
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

    const rawDeckIds = (body as { deckIds?: unknown }).deckIds;
    if (!Array.isArray(rawDeckIds) || rawDeckIds.length === 0) {
      throw new HttpsError("invalid-argument", "Välj minst en lek.");
    }
    const deckIds = rawDeckIds
      .filter((x): x is string => typeof x === "string")
      .map((s) => s.trim())
      .filter((s) => s !== "");
    const uniqueDeckIds = [...new Set(deckIds)];
    if (uniqueDeckIds.length === 0) {
      throw new HttpsError("invalid-argument", "Välj minst en lek.");
    }

    const count = coerceCount((body as { count?: unknown }).count);
    const mixRaw = (body as { mixWithMultipleChoice?: unknown }).mixWithMultipleChoice;
    const mixWithMultipleChoice = mixRaw !== false;

    const db = getDb();
    const userSnap = await db.doc(`users/${uid}`).get();
    const userFamilyId = userSnap.data()?.familyId;
    if (typeof userFamilyId !== "string" || userFamilyId === "") {
      throw new HttpsError("failed-precondition", "Saknar familj för användaren.");
    }

    for (const did of uniqueDeckIds) {
      const deckSnap = await db.doc(`decks/${did}`).get();
      if (!deckSnap.exists) {
        throw new HttpsError("not-found", "Leken hittades inte.");
      }
      const fam = deckSnap.data()?.familyId;
      if (fam !== userFamilyId) {
        throw new HttpsError("permission-denied", "Leken tillhör inte din familj.");
      }
    }

    logger.info("[generateTest] start", {
      uid,
      deckCount: uniqueDeckIds.length,
      count,
      mixWithMultipleChoice,
    });

    const pool = await fetchCardsForDecks(uniqueDeckIds, userFamilyId);
    if (pool.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Finns inga användbara kort i valda lekar.",
      );
    }

    const picked = shuffle(pool).slice(0, Math.min(count, pool.length));
    const allBacks = pool.map((c) => c.back);

    const client = mixWithMultipleChoice ? new Anthropic({ apiKey: anthropicApiKey.value() }) : null;

    const out: QuestionOut[] = [];
    for (const card of picked) {
      const wantMc =
        mixWithMultipleChoice &&
        picked.length >= 4 &&
        Math.random() < 0.4;

      if (wantMc && client) {
        const mc = await generateMcForCard(client, card, allBacks);
        out.push({
          type: "multiple_choice",
          cardId: card.id,
          deckId: card.deckId,
          front: card.front,
          options: mc.options,
          correctIndex: mc.correctIndex,
          ...(card.sourceQuote ? { sourceQuote: card.sourceQuote } : {}),
        });
      } else {
        out.push({
          type: "open",
          cardId: card.id,
          deckId: card.deckId,
          front: card.front,
          ...(card.sourceQuote ? { sourceQuote: card.sourceQuote } : {}),
        });
      }
    }

    shuffle(out); // slumpa ordningsföljd i själva provet

    logger.info("[generateTest] done", { questions: out.length });
    return { questions: out };
  },
);
