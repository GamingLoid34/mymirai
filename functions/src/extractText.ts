import Anthropic from "@anthropic-ai/sdk";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import mammoth from "mammoth";
import { PDFParse } from "pdf-parse";
import sharp from "sharp";

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

export const extractTextFromAttachment = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "1GiB",
    timeoutSeconds: 300,
  },
  async (request) => {
    const rawHomeworkId = (request.data as { homeworkId?: unknown } | null)?.homeworkId;
    logger.info("[extract] start", {
      uid: request.auth?.uid ?? null,
      homeworkId: typeof rawHomeworkId === "string" ? rawHomeworkId : null,
      homeworkIdLength: typeof rawHomeworkId === "string" ? rawHomeworkId.length : null,
    });

    if (!request.auth?.uid) {
      logger.warn("[extract] throwing unauthenticated", {
        reason: "missing_auth_uid",
      });
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const raw = request.data;
    if (raw == null || typeof raw !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop: saknar data.");
    }
    const homeworkId = (raw as { homeworkId?: unknown }).homeworkId;
    if (typeof homeworkId !== "string" || homeworkId.trim() === "") {
      throw new HttpsError("invalid-argument", "homeworkId saknas.");
    }

    const db = getFirestore(adminApp);

    const userSnap = await db.doc(`users/${uid}`).get();
    const userFamilyId = userSnap.data()?.familyId;
    logger.info("[extract] user lookup", {
      uid,
      userExists: userSnap.exists,
      userFamilyId: typeof userFamilyId === "string" ? userFamilyId : null,
    });
    if (typeof userFamilyId !== "string" || userFamilyId.trim() === "") {
      logger.warn("[extract] throwing failed-precondition", {
        reason: "missing_user_familyId",
        uid,
      });
      throw new HttpsError(
        "failed-precondition",
        "Saknar familjetillhörighet för användaren.",
      );
    }

    const hwRef = db.doc(`homework/${homeworkId.trim()}`);
    const hwSnap = await hwRef.get();
    logger.info("[extract] homework lookup", {
      homeworkId: homeworkId.trim(),
      homeworkExists: hwSnap.exists,
      homeworkFamilyId: hwSnap.exists ? hwSnap.data()?.familyId : null,
    });
    if (!hwSnap.exists) {
      logger.warn("[extract] throwing not-found", {
        reason: "homework_not_found_in_firestore",
        homeworkId: homeworkId.trim(),
      });
      throw new HttpsError("not-found", "Läxan hittades inte.");
    }
    const hw = hwSnap.data() ?? {};
    const docFamily = hw.familyId;
    if (docFamily !== userFamilyId) {
      logger.warn("[extract] throwing permission-denied", {
        reason: "family_mismatch",
        homeworkId: homeworkId.trim(),
        homeworkFamilyId: docFamily,
        userFamilyId,
      });
      throw new HttpsError("permission-denied", "Ingen åtkomst till den här läxan.");
    }

    type AttachmentRow = {
      storageUrl?: string;
      mimeType?: string;
      fileName?: string;
    };

    const readAttachments = (data: Record<string, unknown>): AttachmentRow[] => {
      const raw = data.attachments;
      if (!Array.isArray(raw)) return [];
      const out: AttachmentRow[] = [];
      for (const e of raw) {
        if (e != null && typeof e === "object") {
          const o = e as Record<string, unknown>;
          out.push({
            storageUrl: typeof o.storageUrl === "string" ? o.storageUrl : undefined,
            mimeType: typeof o.mimeType === "string" ? o.mimeType : undefined,
            fileName: typeof o.fileName === "string" ? o.fileName : undefined,
          });
        }
      }
      return out;
    };

    const payloadWithIndex = raw as { attachmentIndex?: unknown };
    let requestedAttachmentIndex: number | undefined;
    const rawIdx = payloadWithIndex.attachmentIndex;
    if (rawIdx != null && rawIdx !== "") {
      const n =
        typeof rawIdx === "number"
          ? rawIdx
          : typeof rawIdx === "string"
            ? parseInt(rawIdx.trim(), 10)
            : typeof rawIdx === "bigint"
              ? Number(rawIdx)
              : NaN;
      if (Number.isFinite(n) && n >= 0) {
        requestedAttachmentIndex = Math.floor(Number(n));
      }
    }

    const attList = readAttachments(hw as Record<string, unknown>);

    let attachmentStorageUrl: string | undefined;
    let attachmentMimeType: string | undefined;
    let attachmentFileName: string | undefined;

    if (requestedAttachmentIndex !== undefined) {
      const row = attList[requestedAttachmentIndex];
      if (
        row &&
        typeof row.storageUrl === "string" &&
        row.storageUrl.trim() !== ""
      ) {
        attachmentStorageUrl = row.storageUrl.trim();
        attachmentMimeType = row.mimeType;
        attachmentFileName = row.fileName;
      } else if (
        requestedAttachmentIndex === 0 &&
        typeof hw.attachmentStorageUrl === "string" &&
        hw.attachmentStorageUrl.trim() !== ""
      ) {
        attachmentStorageUrl = hw.attachmentStorageUrl.trim();
        attachmentMimeType = hw.attachmentMimeType as string | undefined;
        attachmentFileName = hw.attachmentFileName as string | undefined;
      } else {
        throw new HttpsError(
          "invalid-argument",
          "Ogiltigt bilageindex eller saknad URL för bilagan.",
        );
      }
    } else if (
      typeof hw.attachmentStorageUrl === "string" &&
      hw.attachmentStorageUrl.trim() !== ""
    ) {
      attachmentStorageUrl = hw.attachmentStorageUrl.trim();
      attachmentMimeType = hw.attachmentMimeType as string | undefined;
      attachmentFileName = hw.attachmentFileName as string | undefined;
    } else if (
      attList.length > 0 &&
      typeof attList[0]?.storageUrl === "string" &&
      attList[0]!.storageUrl!.trim() !== ""
    ) {
      const first = attList[0]!;
      attachmentStorageUrl = first.storageUrl!.trim();
      attachmentMimeType = first.mimeType;
      attachmentFileName = first.fileName;
    } else {
      throw new HttpsError(
        "failed-precondition",
        "Ingen bilaga är uppladdad för den här läxan.",
      );
    }
    if (typeof attachmentMimeType !== "string" || attachmentMimeType.trim() === "") {
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
    const { bucket: bucketName, filePath } = parseFirebaseStorageDownloadUrl(
      attachmentStorageUrl.trim(),
    );

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

    const kindTag = mimeLower.startsWith("image/")
      ? "image"
      : mimeLower;
    logger.info("extractText_start", {
      kind: kindTag,
      size: buffer.length,
      homeworkId: homeworkId.trim(),
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
        logger.info("extractText_done", {
          source: "image",
          outLen: out.length,
          homeworkId: homeworkId.trim(),
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
          logger.info("extractText_pdf_no_layer", {
            outLen: text.length,
            homeworkId: homeworkId.trim(),
          });
          return {
            text: "",
            source: "pdf" as const,
            warning: "no_text_layer",
          };
        }
        const out = clipText(text);
        logger.info("extractText_done", {
          source: "pdf",
          outLen: out.length,
          homeworkId: homeworkId.trim(),
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
        logger.info("extractText_done", {
          source: "docx",
          outLen: out.length,
          homeworkId: homeworkId.trim(),
        });
        return { text: out, source: "docx" as const };
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("extractText_error", e);
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
