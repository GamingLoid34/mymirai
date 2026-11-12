import { SpeechClient } from "@google-cloud/speech";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDefaultBucket } from "./admin";

/** Laddar ljudfil från default Storage-bucket (samma projekt). */
export const transcribeUserAudio = onCall(
  {
    region: "europe-west1",
    memory: "1GiB",
    timeoutSeconds: 300,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const path =
      typeof request.data?.storagePath === "string" ? request.data.storagePath.trim() : "";
    const mime =
      typeof request.data?.mimeType === "string" ? request.data.mimeType.trim() : "audio/mpeg";

    if (!path.startsWith(`users/${uid}/`) && !path.includes(`/${uid}/`)) {
      throw new HttpsError(
        "permission-denied",
        "Ogiltig eller obehörig lagringsväg för ljud.",
      );
    }

    const bucket = getDefaultBucket();
    const file = bucket.file(path);
    const [buf] = await file.download().catch((e) => {
      logger.warn("transcribeUserAudio download", e);
      throw new HttpsError("not-found", "Kunde inte hämta ljudfilen.");
    });

    const max = 10 * 1024 * 1024;
    if (buf.length > max) {
      throw new HttpsError("invalid-argument", "Filen är för stor (max ~10 MB).");
    }

    const client = new SpeechClient();

    let encoding: "MP3" | "LINEAR16" | "WEBM_OPUS" = "MP3";
    if (mime.includes("wav")) encoding = "LINEAR16";
    else if (mime.includes("webm")) encoding = "WEBM_OPUS";

    const sr = mime.includes("wav") ? 16000 : undefined;

    let text = "";
    try {
      const cfg = {
        languageCode: "sv-SE",
        alternativeLanguageCodes: ["en-US"],
        enableAutomaticPunctuation: true,
        model: "latest_long" as const,
        encoding,
        ...(sr != null ? { sampleRateHertz: sr } : {}),
      };
      const resp = await client.recognize({ audio: { content: buf }, config: cfg });
      const response = resp[0];
      const parts =
        (response.results ?? [])
          .map((r) => r.alternatives?.[0]?.transcript ?? "")
          .filter(Boolean);
      text = parts.join("\n").trim();
    } catch (e) {
      logger.error("transcribeUserAudio speech", e);
      throw new HttpsError(
        "unavailable",
        "Tal-till-text misslyckades. Kontrollera att Speech-to-Text API är aktivt i GCP-projektet.",
      );
    }

    if (!text) {
      throw new HttpsError(
        "failed-precondition",
        "Kunde inte höra någon tydlig text. Prova igen med tydligare ljud.",
      );
    }

    return { text };
  }
);
