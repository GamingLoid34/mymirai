import { Readability } from "@mozilla/readability";
import { JSDOM } from "jsdom";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const maxBodyBytes = 5 * 1024 * 1024;
const timeoutMs = 10_000;
const maxOutChars = 50_000;
/** Minsta textlängd efter readability — för kort ⇒ troligen paywall/nav. */
const minExtractedChars = 80;

const browserUa =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
  + "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

function parseHttpUrl(raw: string): URL {
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    throw new HttpsError(
      "invalid-argument",
      "Ogiltig adress — använd http eller https.",
    );
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") {
    throw new HttpsError(
      "invalid-argument",
      "Endast http- och https-länkar stöds.",
    );
  }
  return u;
}

function clipText(s: string): string {
  if (s.length <= maxOutChars) return s;
  return s.slice(0, maxOutChars);
}

function htmlFragmentToPlain(html: string): string {
  const frag = new JSDOM(`<body>${html}</body>`);
  try {
    const txt = frag.window.document.body?.textContent ?? "";
    return txt.replace(/\s+/g, " ").trim();
  } finally {
    frag.window.close();
  }
}

export const extractFromUrl = onCall(
  {
    region: "europe-west1",
    memory: "512MiB",
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const body = request.data;
    if (body == null || typeof body !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop: saknar data.");
    }
    const rawUrl = (body as { url?: unknown }).url;
    if (typeof rawUrl !== "string" || rawUrl.trim() === "") {
      throw new HttpsError("invalid-argument", "Ange en webbadress.");
    }

    const target = parseHttpUrl(rawUrl).href;
    logger.info("[extractFromUrl] start", {
      uid: request.auth.uid,
      host: new URL(target).hostname,
    });

    let html: string;
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), timeoutMs);
      let res: Response;
      try {
        res = await fetch(target, {
          method: "GET",
          redirect: "follow",
          signal: ctrl.signal,
          headers: {
            "User-Agent": browserUa,
            Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "sv,en-US;q=0.9,en;q=0.8",
          },
        });
      } finally {
        clearTimeout(timer);
      }
      if (!res.ok) {
        throw new HttpsError(
          "failed-precondition",
          "Kunde inte läsa sidan.",
        );
      }

      const cl = res.headers.get("content-length");
      if (cl != null && cl !== "") {
        const n = parseInt(cl, 10);
        if (!Number.isNaN(n) && n > maxBodyBytes) {
          throw new HttpsError(
            "failed-precondition",
            "Kunde inte läsa sidan.",
          );
        }
      }

      const ct = res.headers.get("content-type")?.toLowerCase() ?? "";
      if (ct.includes("application/pdf") ||
          ct.includes("application/octet-stream") ||
          ct.startsWith("image/")) {
        throw new HttpsError(
          "failed-precondition",
          "Länkar till filer eller bilder stöds inte än.",
        );
      }

      const buf = new Uint8Array(await res.arrayBuffer());
      if (buf.byteLength > maxBodyBytes) {
        throw new HttpsError(
          "failed-precondition",
          "Kunde inte läsa sidan.",
        );
      }
      html = new TextDecoder("utf-8").decode(buf);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      const msg = `${e}`;
      logger.warn("[extractFromUrl] fetch_failed", msg);
      if (msg.includes("abort") || msg.includes("AbortError")) {
        throw new HttpsError(
          "deadline-exceeded",
          "Sidans svar tog för lång tid.",
        );
      }
      throw new HttpsError(
        "failed-precondition",
        "Kunde inte läsa sidan.",
      );
    }

    let titleRaw = "";
    let textContent = "";
    let domForRead: JSDOM | undefined;
    try {
      domForRead = new JSDOM(html, { url: target });
      const reader = new Readability(domForRead.window.document);
      const article = reader.parse();
      titleRaw = typeof article?.title === "string" ? article.title.trim() : "";
      if (article?.content && typeof article.content === "string") {
        textContent = htmlFragmentToPlain(article.content);
      }
    } catch (err) {
      logger.error("[extractFromUrl] readability_parse", err);
      throw new HttpsError(
        "failed-precondition",
        "Kunde inte läsa sidan.",
      );
    } finally {
      try {
        domForRead?.window.close();
      } catch {
        // ignore
      }
    }

    const title = titleRaw;

    if (textContent.length < minExtractedChars) {
      logger.info("[extractFromUrl] readability_empty", {
        titleLen: title.length,
        textLen: textContent.length,
      });
      throw new HttpsError(
        "failed-precondition",
        "Kunde inte läsa sidan.",
      );
    }

    const clipped = clipText(textContent);
    logger.info("[extractFromUrl] done", { textLen: clipped.length });
    return {
      title: title || "(Ingen titel)",
      text: clipped,
      sourceType: "article",
    };
  },
);
