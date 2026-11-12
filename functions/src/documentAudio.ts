import { createHash } from "crypto";

import { defineSecret, defineString } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb, getDefaultBucket } from "./admin";

const elevenLabsApiKey = defineSecret("ELEVENLABS_API_KEY");

/** Röst-ID från ElevenLabs Voice Library — samma param som listeningStory. */
const elevenVoiceId = defineString("ELEVENLABS_VOICE_ID", {
  default: "21m00Tcm4TlvDq8ikWAM",
});

const maxTextChars = 20_000;
const signedUrlMinutes = 180;

function truncateAtSentence(text: string, maxChars: number): { text: string; truncated: boolean } {
  if (text.length <= maxChars) return { text, truncated: false };
  const slice = text.slice(0, maxChars);
  const lastBoundary = Math.max(
    slice.lastIndexOf(". "),
    slice.lastIndexOf("! "),
    slice.lastIndexOf("? "),
    slice.lastIndexOf("\n"),
  );
  const cut = lastBoundary > maxChars * 0.5 ? lastBoundary + 1 : maxChars;
  return { text: slice.slice(0, cut).trim(), truncated: true };
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
    logger.warn("[documentAudio] elevenlabs_http", {
      status: res.status,
      snippet: errBody.slice(0, 200),
    });
    throw new Error(`elevenlabs_${res.status}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

export const documentAudio = onCall(
  {
    region: "europe-west1",
    secrets: [elevenLabsApiKey],
    memory: "512MiB",
    timeoutSeconds: 180,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const body = request.data;
    const rawDocId = (body as { documentId?: unknown } | null)?.documentId;
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

    const extractedText =
      typeof doc.extractedText === "string" ? doc.extractedText.trim() : "";
    const summary = typeof doc.summary === "string" ? doc.summary.trim() : "";
    const sourceText = extractedText || summary;
    if (!sourceText) {
      throw new HttpsError(
        "failed-precondition",
        "Dokumentet saknar text att läsa upp.",
      );
    }

    const { text, truncated } = truncateAtSentence(sourceText, maxTextChars);
    const voiceId = elevenVoiceId.value().trim() || "21m00Tcm4TlvDq8ikWAM";
    const hash = createHash("sha256").update(text).update(voiceId).digest("hex");
    const objectName = `documents/${ownerUid}/${documentId}/audio/${hash}.mp3`;

    const bucket = getDefaultBucket();
    const file = bucket.file(objectName);
    const [exists] = await file.exists();

    if (!exists) {
      let audio: Buffer;
      try {
        audio = await synthElevenLabs(text, elevenLabsApiKey.value(), voiceId);
      } catch (e) {
        logger.error("[documentAudio] synth", e);
        throw new HttpsError(
          "failed-precondition",
          "Kunde inte skapa ljud (ElevenLabs). Kontrollera API-nyckel och röst-ID.",
        );
      }
      if (audio.length < 500) {
        throw new HttpsError("internal", "Fick för litet ljud från ElevenLabs.");
      }
      await file.save(audio, {
        contentType: "audio/mpeg",
        resumable: false,
        metadata: {
          metadata: {
            ownerUid,
            documentId,
          },
        },
      });
      await docRef.update({
        audioCachedAt: new Date(),
        audioStoragePath: objectName,
      });
      logger.info("[documentAudio] cache_miss_generated", {
        documentId,
        chars: text.length,
        audioBytes: audio.length,
      });
    } else {
      logger.info("[documentAudio] cache_hit", { documentId });
    }

    const [audioUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + signedUrlMinutes * 60 * 1000,
    });

    return { audioUrl, truncated };
  },
);
