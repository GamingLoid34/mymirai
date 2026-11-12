import Anthropic from "@anthropic-ai/sdk";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type DocumentData } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import mammoth from "mammoth";
import { PDFParse } from "pdf-parse";
import sharp from "sharp";

/**
 * Extrahering för vuxen-dokument (Firestore `documents`).
 * Återanvänder samma pipeline som läxbilagan i `extractText.ts` utan att ändra den filen.
 */
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const adminApp = getApps()[0] ?? initializeApp();

const maxBytes = 25 * 1024 * 1024;
const maxOutChars = 50_000;
const pdfPageLimit = 30;
const minPdfTextChars = 30;

const ocrSystem = `Du är en OCR-motor. Returnera ENDAST den text som syns på bilden, ren prosa, behåll radbrytningar bara där det är meningsfullt. Ingen kommentar, ingen markdown.`;

function parseFirebaseStorageDownloadUrl(urlStr: string): { bucket: string; filePath: string } {
  const raw = urlStr.trim();
  if (raw.startsWith("gs://")) {
    const rest = raw.slice("gs://".length);
    const i = rest.indexOf("/");
    if (i === -1) {
      throw new HttpsError("failed-precondition", "Ogiltig lagrings-URL.");
    }
    return { bucket: rest.slice(0, i), filePath: rest.slice(i + 1) };
  }
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new HttpsError("failed-precondition", "Ogiltig lagrings-URL.");
  }
  if (!u.hostname.includes("firebasestorage.googleapis.com")) {
    throw new HttpsError("failed-precondition", "Ogiltig lagrings-URL.");
  }
  const m = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  if (!m) {
    throw new HttpsError("failed-precondition", "Ogiltig lagrings-URL.");
  }
  const filePath = decodeURIComponent(m[2].replace(/\+/g, " "));
  return { bucket: m[1], filePath };
}

function guessMimeFromFileName(name: string | undefined): string | null {
  if (!name) return null;
  const lower = name.toLowerCase();
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".docx")) {
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".heic") || lower.endsWith(".heif")) return "image/heic";
  if (lower.endsWith(".gif")) return "image/gif";
  return null;
}

function normalizeImageMediaTypeForAnthropic(
  mime: string,
): "image/jpeg" | "image/png" | "image/gif" | "image/webp" {
  const m = mime.toLowerCase();
  if (m === "image/jpeg" || m === "image/jpg") return "image/jpeg";
  if (m === "image/png") return "image/png";
  if (m === "image/gif") return "image/gif";
  if (m === "image/webp") return "image/webp";
  throw new HttpsError(
    "unimplemented",
    "Endast PDF, Word och bild stöds just nu.",
  );
}

function clipText(s: string): string {
  if (s.length <= maxOutChars) return s;
  return s.slice(0, maxOutChars);
}

function resolveAttachmentLocation(data: DocumentData): {
  bucketName: string;
  filePath: string;
  attachmentMimeType: string | undefined;
  attachmentFileName: string | undefined;
} {
  const attachment = data.attachment as
    | { storagePath?: string; mimeType?: string; fileName?: string }
    | undefined;
  const attachmentStorageUrl = data.attachmentStorageUrl as string | undefined;

  const gsOrPath =
    typeof attachment?.storagePath === "string" && attachment.storagePath.trim() !== ""
      ? attachment.storagePath.trim()
      : "";

  let bucketName: string;
  let filePath: string;

  if (gsOrPath.startsWith("gs://")) {
    const p = parseFirebaseStorageDownloadUrl(gsOrPath);
    bucketName = p.bucket;
    filePath = p.filePath;
  } else if (gsOrPath !== "") {
    bucketName = getStorage(adminApp).bucket().name;
    filePath = gsOrPath.replace(/^\/+/, "");
  } else if (
    typeof attachmentStorageUrl === "string" &&
    attachmentStorageUrl.trim() !== ""
  ) {
    const p = parseFirebaseStorageDownloadUrl(attachmentStorageUrl.trim());
    bucketName = p.bucket;
    filePath = p.filePath;
  } else {
    throw new HttpsError(
      "failed-precondition",
      "Ingen bilaga är uppladdad för det här dokumentet.",
    );
  }

  const attachmentMimeType =
    typeof attachment?.mimeType === "string" && attachment.mimeType.trim() !== ""
      ? attachment.mimeType.trim()
      : undefined;
  const attachmentFileName =
    typeof attachment?.fileName === "string" && attachment.fileName.trim() !== ""
      ? attachment.fileName.trim()
      : undefined;

  return {
    bucketName,
    filePath,
    attachmentMimeType,
    attachmentFileName,
  };
}

export const extractTextFromDocument = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "1GiB",
    timeoutSeconds: 300,
  },
  async (request) => {
    const rawDocumentId = (request.data as { documentId?: unknown } | null)?.documentId;

    logger.info("[extractDoc] start", {
      uid: request.auth?.uid ?? null,
      documentId: typeof rawDocumentId === "string" ? rawDocumentId : null,
      documentIdLength: typeof rawDocumentId === "string" ? rawDocumentId.length : null,
    });

    if (!request.auth?.uid) {
      logger.warn("[extractDoc] unauthenticated");
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const raw = request.data;
    if (raw == null || typeof raw !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop: saknar data.");
    }
    const documentId = (raw as { documentId?: unknown }).documentId;
    if (typeof documentId !== "string" || documentId.trim() === "") {
      throw new HttpsError("invalid-argument", "documentId saknas.");
    }

    const db = getFirestore(adminApp);
    const docRef = db.doc(`documents/${documentId.trim()}`);
    const docSnap = await docRef.get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Dokumentet hittades inte.");
    }
    const docData = docSnap.data() ?? {};
    const ownerUid = docData.ownerUid as string | undefined;
    if (typeof ownerUid !== "string" || ownerUid.trim() === "" || ownerUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Du har inte behörighet att läsa det här dokumentet.",
      );
    }

    const {
      bucketName,
      filePath,
      attachmentMimeType: mimeFromFirestore,
      attachmentFileName,
    } = resolveAttachmentLocation(docData);

    let attachmentMimeType = mimeFromFirestore;
    if (
      attachmentMimeType == null ||
      (typeof attachmentMimeType === "string" && attachmentMimeType.trim() === "")
    ) {
      const g = guessMimeFromFileName(attachmentFileName);
      if (g) {
        attachmentMimeType = g;
      } else {
        throw new HttpsError(
          "failed-precondition",
          "Saknar bilagans filtyp — spara om med känd filändelse.",
        );
      }
    }

    const mimeLower = attachmentMimeType.trim().toLowerCase();

    const bucket = getStorage(adminApp).bucket(bucketName);
    const file = bucket.file(filePath);
    const [meta] = await file.getMetadata();
    const sizeNum = Number(meta.size ?? 0);
    if (sizeNum > maxBytes) {
      throw new HttpsError(
        "resource-exhausted",
        "Filen är för stor (max 25 MB).",
      );
    }
    if (sizeNum === 0) {
      throw new HttpsError("failed-precondition", "Bilagan är tom.");
    }

    const [buffer] = await file.download();
    if (buffer.length > maxBytes) {
      throw new HttpsError(
        "resource-exhausted",
        "Filen är för stor (max 25 MB).",
      );
    }

    const kindTag = mimeLower.startsWith("image/") ? "image" : mimeLower;
    logger.info("extractTextDoc_start", {
      kind: kindTag,
      size: buffer.length,
      documentId: documentId.trim(),
    });

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    try {
      if (mimeLower.startsWith("image/")) {
        let imageBytes: Buffer = buffer;
        let mediaType = mimeLower;
        if (mimeLower === "image/heic" || mimeLower === "image/heif") {
          imageBytes = await sharp(buffer).jpeg({ quality: 90 }).toBuffer();
          mediaType = "image/jpeg";
        }
        const anthropicMime = normalizeImageMediaTypeForAnthropic(mediaType);
        const b64 = imageBytes.toString("base64");
        const message = await client.messages.create({
          model: "claude-haiku-4-5",
          max_tokens: 4000,
          system: ocrSystem,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: {
                    type: "base64",
                    media_type: anthropicMime,
                    data: b64,
                  },
                },
                {
                  type: "text",
                  text: "Läs av all synlig text.",
                },
              ],
            },
          ],
        });
        const text = message.content
          .map((b) => (b.type === "text" ? b.text : ""))
          .join("")
          .trim();
        const out = clipText(text);
        logger.info("extractTextDoc_done", {
          source: "image",
          outLen: out.length,
          documentId: documentId.trim(),
        });
        return { text: out, source: "image" as const };
      }

      if (mimeLower === "application/pdf") {
        const parser = new PDFParse({ data: buffer });
        let text: string;
        try {
          const tr = await parser.getText({ first: pdfPageLimit });
          text = (tr.text ?? "").trim();
        } finally {
          await parser.destroy();
        }
        if (text.length < minPdfTextChars) {
          logger.info("extractTextDoc_pdf_no_layer", {
            outLen: text.length,
            documentId: documentId.trim(),
          });
          return {
            text: "",
            source: "pdf" as const,
            warning: "no_text_layer",
          };
        }
        const out = clipText(text);
        logger.info("extractTextDoc_done", {
          source: "pdf",
          outLen: out.length,
          documentId: documentId.trim(),
        });
        return { text: out, source: "pdf" as const };
      }

      const isDocx =
        mimeLower ===
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
        (attachmentFileName?.toLowerCase().endsWith(".docx") ?? false);
      if (isDocx) {
        const result = await mammoth.extractRawText({ buffer });
        const text = (result.value ?? "").trim();
        const out = clipText(text);
        logger.info("extractTextDoc_done", {
          source: "docx",
          outLen: out.length,
          documentId: documentId.trim(),
        });
        return { text: out, source: "docx" as const };
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("extractTextDoc_error", e);
      throw new HttpsError(
        "unavailable",
        "Kunde inte läsa filen. Försök igen senare.",
      );
    }

    throw new HttpsError(
      "unimplemented",
      "Endast PDF, Word och bild stöds just nu.",
    );
  },
);
