import { randomUUID } from "crypto";

import Anthropic from "@anthropic-ai/sdk";
import { defineSecret, defineString } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb, getDefaultBucket } from "./admin";
import { mergedExtractedExcludingQa } from "./homeworkSourceText";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const elevenLabsApiKey = defineSecret("ELEVENLABS_API_KEY");

/** Röst-ID från ElevenLabs Voice Library — sätt projekt‑param eller använd default‑exempel. */
const elevenVoiceId = defineString("ELEVENLABS_VOICE_ID", {
  default: "21m00Tcm4TlvDq8ikWAM",
});

const maxSourceChars = 14_000;
const maxStoryChars = 2_600;
const signedUrlMinutes = 90;

function trimSource(raw: string): string {
  const t = raw.trim().replace(/\r\n/g, "\n");
  return t.length > maxSourceChars ? `${t.slice(0, maxSourceChars)}\n…` : t;
}

async function synthElevenLabs(text: string, apiKey: string, voiceId: string): Promise<Buffer> {
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Accept: "audio/mpeg",
      "Content-Type": "application/json",
      "xi-api-key": apiKey,
    },
    body: JSON.stringify({
      text,
      model_id: "eleven_multilingual_v2",
    }),
  });
  if (!res.ok) {
    const errBody = await res.text().catch(() => "");
    logger.warn("[listeningStory] elevenlabs_http", {
      status: res.status,
      snippet: errBody.slice(0, 200),
    });
    throw new Error(`elevenlabs_${res.status}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

export const listeningStory = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey, elevenLabsApiKey],
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

    const rawHwId = (body as { homeworkId?: unknown }).homeworkId;
    const homeworkId =
      typeof rawHwId === "string" ? rawHwId.trim() : "";
    const rawText = (body as { text?: unknown }).text;
    const fallbackText =
      typeof rawText === "string" ? rawText.trim() : "";

    if (!homeworkId && !fallbackText) {
      throw new HttpsError(
        "invalid-argument",
        "Ange homeworkId eller text för sagan.",
      );
    }

    const db = getDb();
    const userSnap = await db.doc(`users/${uid}`).get();
    const userFamilyId = userSnap.data()?.familyId;
    if (typeof userFamilyId !== "string" || userFamilyId === "") {
      throw new HttpsError("failed-precondition", "Saknar familj för användaren.");
    }

    let sourceBlock = "";
    let titleForMeta = "Lyssna";

    if (homeworkId) {
      const hwRef = db.doc(`homework/${homeworkId}`);
      const hwSnap = await hwRef.get();
      if (!hwSnap.exists) {
        throw new HttpsError("not-found", "Läxan hittades inte.");
      }
      const hw = hwSnap.data() ?? {};
      if (hw.familyId !== userFamilyId) {
        throw new HttpsError("permission-denied", "Läxan tillhör inte din familj.");
      }
      const summary = typeof hw.summary === "string" ? hw.summary.trim() : "";
      const hwRec = hw as Record<string, unknown>;
      const extracted = mergedExtractedExcludingQa(hwRec);
      titleForMeta =
        typeof hw.title === "string" && hw.title.trim() !== ""
          ? hw.title.trim()
          : "Läxa";
      const parts: string[] = [];
      if (summary) parts.push(`SAMMANFATTNING:\n${summary}`);
      if (extracted) parts.push(`UNDERLAG (text ur materialet):\n${trimSource(extracted)}`);
      if (!summary && !extracted) {
        throw new HttpsError(
          "failed-precondition",
          "Läxan saknar text att bygga saga från.",
        );
      }
      sourceBlock = parts.join("\n\n");
    } else {
      sourceBlock = trimSource(fallbackText);
      if (sourceBlock.length < 80) {
        throw new HttpsError(
          "invalid-argument",
          "Texten är för kort för en saga (minst ~80 tecken).",
        );
      }
    }

    const sys = `Du skriver en kort muntlig berättelse på svenska för skolbarn (grundskola).
Läxan ska bli lättare att ta till sig genom att du berättar fakta med varma, tydliga formuleringar — inte som en punktlista.
Regler:
- Håll dig till fakta och begrepp som finns i källmaterialet. Lägg inte till nya fakta.
- Ingen dialog med rollfigurer; du får använda "vi" och "tänk på att…" sparsamt.
- Cirka 850–1500 tecken (kort att lyssna på i en sittning).
- Ren löpande text utan rubriker, asterisker eller numrering.
Svara endast med berättelsen, ingen inledning eller avslutande förklaring.`;

    const userPrompt = `Bygg en lyssningsvänlig saga utifrån följande underlag:\n\n${sourceBlock}`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let story = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 1200,
        system: sys,
        messages: [{ role: "user", content: userPrompt }],
      });
      story = message.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("")
        .trim();
    } catch (e) {
      logger.error("[listeningStory] anthropic", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte skapa saga just nu. Försök igen senare.",
      );
    }

    if (!story || story.length < 120) {
      throw new HttpsError(
        "internal",
        "Fick ingen användbar saga från AI.",
      );
    }
    if (story.length > maxStoryChars) {
      story = `${story.slice(0, maxStoryChars - 1).trim()}…`;
    }

    let audio: Buffer;
    try {
      audio = await synthElevenLabs(
        story,
        elevenLabsApiKey.value(),
        elevenVoiceId.value().trim() || "21m00Tcm4TlvDq8ikWAM",
      );
    } catch (e) {
      logger.error("[listeningStory] synth", e);
      throw new HttpsError(
        "failed-precondition",
        "Kunde inte skapa ljud (ElevenLabs). Kontrollera API‑nyckel och röst‑ID.",
      );
    }

    if (audio.length < 500) {
      throw new HttpsError(
        "internal",
        "Fick för litet ljud från ElevenLabs.",
      );
    }

    const objectName = `listeningStories/${userFamilyId}/${randomUUID()}.mp3`;
    const bucket = getDefaultBucket();
    const file = bucket.file(objectName);

    await file.save(audio, {
      contentType: "audio/mpeg",
      resumable: false,
      metadata: {
        metadata: {
          uid,
          ...(homeworkId ? { homeworkId } : {}),
          title: titleForMeta.slice(0, 120),
        },
      },
    });

    const [audioUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + signedUrlMinutes * 60 * 1000,
    });

    logger.info("[listeningStory] ok", {
      chars: story.length,
      audioBytes: audio.length,
      objectNameLen: objectName.length,
    });

    return {
      storyText: story,
      audioUrl,
      title: titleForMeta,
    };
  },
);
