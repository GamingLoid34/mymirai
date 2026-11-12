import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

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

export const parseVocabulary = onCall(
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
    const body = request.data as { rawText?: unknown; sourceLanguage?: unknown; targetLanguage?: unknown } | null;
    if (body == null || typeof body !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop.");
    }
    const raw = typeof body.rawText === "string" ? body.rawText.trim() : "";
    if (raw.length < 3 || raw.length > 20_000) {
      throw new HttpsError("invalid-argument", "Text måste vara 3–20 000 tecken.");
    }
    const srcLang = typeof body.sourceLanguage === "string" ? body.sourceLanguage.trim() || "English" : "English";
    const tgtLang = typeof body.targetLanguage === "string" ? body.targetLanguage.trim() || "Svenska" : "Svenska";

    const system = `Du parsar gloslista från svensk skolundervisning.
Indata: text med ord-par. Format kan variera (kolon, likhetstecken, komma, tankestreck, pil, numrering).
Strukturera till JSON ENBART i formen {"items":[{"term":"...","translation":"...","example": optional string}]}.
- term = (${srcLang})
- translation = (${tgtLang})
 Behåll stavning. Hoppa rubriker/tomma rader. Om en rad inte är ett par, ignorera den.`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let textOut = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 4096,
        system,
        messages: [{ role: "user", content: raw }],
      });
      textOut = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("parseVocabulary anthropic", e);
      throw new HttpsError("unavailable", "Kunde inte parsa glosorna just nu.");
    }

    let items: { term: string; translation: string; example?: string }[];
    try {
      const clipped = stripCodeFence(textOut);
      const parsed: unknown = JSON.parse(clipped);
      if (
        parsed == null ||
        typeof parsed !== "object" ||
        !Array.isArray((parsed as { items?: unknown }).items)
      ) {
        throw new Error("shape");
      }
      const rawItems = (parsed as { items: unknown[] }).items;
      items = [];
      for (const e of rawItems) {
        if (e != null && typeof e === "object" && "term" in e && "translation" in e) {
          const term = typeof (e as { term?: unknown }).term === "string" ? String((e as { term?: string }).term).trim() : "";
          const trans =
            typeof (e as { translation?: unknown }).translation === "string"
              ? String((e as { translation?: string }).translation).trim()
              : "";
          if (!term || !trans) continue;
          const example =
            "example" in e && typeof (e as { example?: unknown }).example === "string"
              ? String((e as { example?: string }).example).trim()
              : undefined;
          items.push(example ? { term, translation: trans, example } : { term, translation: trans });
          if (items.length >= 200) break;
        }
      }
    } catch (_e) {
      logger.warn("parseVocabulary json fail", textOut.slice(0, 300));
      throw new HttpsError("internal", "Kunde inte tolka AI-svaret för glosor.");
    }
    if (items.length === 0) {
      throw new HttpsError("failed-precondition", "Inga giltiga glos-par hittades.");
    }

    return { items };
  }
);
