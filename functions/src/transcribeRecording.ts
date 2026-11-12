import { SpeechClient } from "@google-cloud/speech";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb, getDefaultBucket } from "./admin";

const maxAudioMinutes = 60;

const allowedLanguages = new Set(["sv-SE", "en-US", "en-GB"]);

/**
 * Mötesinspelningar (VO-06): kräver longRunningRecognize med GCS-URI, till
 * skillnad från transcribeUserAudio (synkron, ~60s/10MB, oförändrad för
 * chattdiktering). Läser ljudets Storage-path från dokumentets attachment,
 * skriver resultatet till extractedText server-side.
 */
export const transcribeRecording = onCall(
  {
    region: "europe-west1",
    memory: "1GiB",
    timeoutSeconds: 540,
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
    const rawLang = (body as { languageCode?: unknown } | null)?.languageCode;
    const languageCode =
      typeof rawLang === "string" && allowedLanguages.has(rawLang) ? rawLang : "sv-SE";

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

    const attachment = doc.attachment as { storagePath?: unknown; mimeType?: unknown } | undefined;
    const storagePath =
      typeof attachment?.storagePath === "string" ? attachment.storagePath.trim() : "";
    if (!storagePath) {
      throw new HttpsError("failed-precondition", "Dokumentet saknar ljudbilaga.");
    }

    const bucket = getDefaultBucket();
    const file = bucket.file(storagePath);
    const [metadata] = await file.getMetadata().catch((e) => {
      logger.warn("[transcribeRecording] getMetadata", e);
      throw new HttpsError("not-found", "Kunde inte hitta ljudfilen.");
    });
    const sizeBytes = Number(metadata.size ?? 0);
    // Grov uppskattning: m4a/aac ~ 128kbps => ~16 KB/s.
    const estimatedSeconds = sizeBytes / 16000;
    if (estimatedSeconds > maxAudioMinutes * 60 * 1.5) {
      throw new HttpsError(
        "invalid-argument",
        `Max ${maxAudioMinutes} minuter i denna version.`,
      );
    }

    const client = new SpeechClient();
    const gcsUri = `gs://${bucket.name}/${storagePath}`;

    let text = "";
    try {
      const [operation] = await client.longRunningRecognize({
        audio: { uri: gcsUri },
        config: {
          languageCode,
          enableAutomaticPunctuation: true,
          model: "latest_long",
          encoding: "MP3",
        },
      });
      const [response] = await operation.promise();
      const parts = (response.results ?? [])
        .map((r) => r.alternatives?.[0]?.transcript ?? "")
        .filter(Boolean);
      text = parts.join("\n").trim();
    } catch (e) {
      logger.error("[transcribeRecording] speech", e);
      throw new HttpsError(
        "unavailable",
        "Tal-till-text misslyckades. Försök igen senare.",
      );
    }

    if (!text) {
      throw new HttpsError(
        "failed-precondition",
        "Kunde inte höra någon tydlig text i inspelningen.",
      );
    }

    await docRef.update({
      extractedText: text,
      updatedAt: new Date(),
    });

    logger.info("[transcribeRecording] ok", { documentId, chars: text.length });

    return { chars: text.length };
  },
);
