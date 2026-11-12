import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const minChars = 20;
const maxChars = 50_000;

const systemPrompt = `Du hjälper svenska skolelever. Skriv en kort sammanfattning av materialet.
Regler: 4–8 korta meningar, raka meningar, inga numrerade eller avmarkerade listor, ren brödtext.
Behåll viktiga begrepp och årtal. Tonen ska vara tydlig och lugn, anpassad till barn.`;

const systemPromptAdult = `Du skriver för en vuxen läsare på expertnivå (svenska).
Regler: 4–10 meningar som en tät, professionell sammanfattning. Raka meningar, ren brödtext (inga punktlistor).
Behåll precision: begrepp, definitioner och nyanser där de behövs. Ton: tydlig, neutral, utan utfyllnad.`;

export const summarizeHomework = onCall(
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

    const rawText = (data as { text?: unknown }).text;
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

    const audienceRaw = (data as { audience?: unknown }).audience;
    const isAdult = audienceRaw === "adult";

    const gh = (data as { gradeHint?: unknown }).gradeHint;
    let gradeLine = "";
    if (!isAdult && typeof gh === "string" && gh.trim() !== "") {
      gradeLine = ` Anpassa språknivån till elev i ${gh.trim()}.`;
    }

    const systemUsed = isAdult ? systemPromptAdult : systemPrompt + gradeLine;
    const userIntro = isAdult
      ? "Sammanfatta följande material. Svara endast med sammanfattningen.\n\n"
      : "Sammanfatta följande skolmaterial. Svara endast med sammanfattningen.\n\n";

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    let summary: string;
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 800,
        system: systemUsed,
        messages: [
          {
            role: "user",
            content: `${userIntro}${text}`,
          },
        ],
      });
      summary = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("anthropic_summarizeHomework", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte skapa sammanfattning just nu. Försök igen senare.",
      );
    }

    if (!summary) {
      throw new HttpsError(
        "unavailable",
        "Fick tomt svar. Försök igen.",
      );
    }

    return { summary };
  }
);

export { extractTextFromAttachment } from "./extractText";
export { extractTextFromDocument } from "./extractTextFromDocument";
export { generateFlashcards } from "./generateFlashcards";
export { gradeAnswer } from "./gradeAnswer";
export { generateTest } from "./generateTest";
export { extractFromUrl } from "./extractFromUrl";
export { parseVocabulary } from "./parseVocabulary";
export { parseQuestionsAndAnswers } from "./parseQuestionsAndAnswers";
export { generateVocabularyFlashcards } from "./generateVocabularyFlashcards";
export { parseMathProblems, explainMathStep, varyMathProblem } from "./mathHomework";
export { chatWithDocument } from "./chatWithDocument";
export { transcribeUserAudio } from "./transcribeUserAudio";
export { listeningStory } from "./listeningStory";
export { suggestHomeworkMetadata } from "./suggestHomeworkMetadata";
export { documentAudio } from "./documentAudio";
export { transcribeRecording } from "./transcribeRecording";
export { summarizeRecording } from "./summarizeRecording";
export { polishDictation } from "./polishDictation";
