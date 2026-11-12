import Anthropic from "@anthropic-ai/sdk";
import { FieldValue } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const chatWithDocument = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "1GiB",
    timeoutSeconds: 180,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const body = request.data as {
      documentId?: unknown;
      userMessage?: unknown;
      history?: unknown;
    };

    const docId = typeof body.documentId === "string" ? body.documentId.trim() : "";
    const userMessage =
      typeof body.userMessage === "string" ? body.userMessage.trim() : "";

    const historyRaw = Array.isArray(body.history) ? body.history : [];

    const historyMsgs: Anthropic.Messages.MessageParam[] = [];
    for (const row of historyRaw) {
      if (row != null && typeof row === "object") {
        const rr = row as { role?: unknown; content?: unknown };
        const r = rr.role === "assistant" ? "assistant" : rr.role === "user" ? "user" : null;
        const c =
          typeof rr.content === "string" ? rr.content.trim().slice(0, 6000) : "";
        if (r === "assistant" || r === "user") {
          historyMsgs.push({ role: r, content: c });
          if (historyMsgs.length > 24) historyMsgs.shift();
        }
      }
    }

    if (!docId || !userMessage) {
      throw new HttpsError("invalid-argument", "documentId och userMessage krävs.");
    }
    const db = getDb();
    const dRef = db.doc(`documents/${docId}`);
    const snap = await dRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Dokumentet finns inte.");

    const d = snap.data() ?? {};
    const ownerUid = typeof d.ownerUid === "string" ? d.ownerUid : "";
    if (ownerUid !== uid) throw new HttpsError("permission-denied", "Äger inte dokument.");

    let docText =
      typeof d.extractedText === "string" && d.extractedText.trim() !== ""
        ? d.extractedText.trim().slice(0, 140_000)
        : "";

    const sum = typeof d.summary === "string" ? d.summary.trim() : "";
    if ((docText.length < 120 || docText.split(/\s/).length < 120) && sum.length > 0) {
      docText = `(Sammanfattning)\n${sum}\n\n${docText}`;
    }

    const title =
      typeof d.title === "string" ? d.title.trim().slice(0, 240) : "Dokument";
    docText = `[Dokument: ${title}]\n${docText}`.slice(0, 200_000);

    const systemPrompt = [
      "Du hjälper användaren förstå dokumentet på svenska.",
      "Svara endast baserat på dokumentet mellan <<<DOC och DOC>>> om det inte räcker—säg tydligt att det inte står.",
      "Var koncis och med referenser som ‘tidigt i texten’ eller ‘mot slutet’. inga lösa utan-källa påståenden.",
      `<<<DOC\n${docText}\nDOC>>>`,
    ].join("\n");

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    const messagesOut: Anthropic.Messages.MessageParam[] = [
      ...historyMsgs.map((hm) =>
        hm.role === "assistant"
          ? ({
              role: "assistant" as const,
              content: String(hm.content).slice(0, 6000),
            })
          : ({ role: "user" as const, content: String(hm.content).slice(0, 6000) })
      ),
      { role: "user", content: userMessage.slice(0, 4000) },
    ];

    let reply = "";

    try {
      const completion = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 4096,
        system: systemPrompt,
        messages: messagesOut,
      });

      reply = completion.content
        .map((blk) => (blk.type === "text" ? blk.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[chatWithDocument] anthropic", e);
      throw new HttpsError("unavailable", "Kunde inte svara på frågan just nu.");
    }
    if (!reply) {
      throw new HttpsError("unavailable", "Tom svarsrad.");
    }

    const turnsRef = dRef.collection("chat_turns");

    await turnsRef.doc().set({
      role: "user",
      content: userMessage,
      createdAt: FieldValue.serverTimestamp(),
    });

    await turnsRef.doc().set({
      role: "assistant",
      content: reply,
      createdAt: FieldValue.serverTimestamp(),
    });

    logger.info("[chatWithDocument]", { uidLen: uid.length, docIdLen: docId.length });

    return { reply };
  }
);
