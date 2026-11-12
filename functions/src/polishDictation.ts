import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const minChars = 3;
const maxChars = 20_000;

const systemPrompt = `Städa talspråk till skriven svenska: ta bort utfyllnadsord, rätta grammatik
och interpunktion, behåll allt innehåll och ordning, ändra inte betydelse, lägg inte till något.
Svara endast med den städade texten, ingen inledning eller förklaring.`;

export const polishDictation = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const rawText = (request.data as { text?: unknown } | null)?.text;
    const text = typeof rawText === "string" ? rawText.trim() : "";
    if (text.length < minChars || text.length > maxChars) {
      throw new HttpsError(
        "invalid-argument",
        `Texten ska vara ${minChars}–${maxChars} tecken.`,
      );
    }

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let polished = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: systemPrompt,
        messages: [{ role: "user", content: text }],
      });
      polished = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[polishDictation] anthropic", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte städa texten just nu. Försök igen senare.",
      );
    }

    if (!polished) {
      throw new HttpsError("internal", "Fick tomt svar. Försök igen.");
    }

    return { polishedText: polished };
  },
);
