import Anthropic from "@anthropic-ai/sdk";
import { defineSecret } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

function stripFence(s: string): string {
  let t = s.trim();
  const m = /^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/m.exec(t);
  if (m) return m[1].trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?/, "").replace(/```$/, "").trim();
  }
  return t;
}

export const parseMathProblems = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Inloggning krävs.");
    const txt = typeof request.data?.extractedText === "string" ? request.data.extractedText.trim() : "";
    if (txt.length < 10 || txt.length > 50_000) {
      throw new HttpsError("invalid-argument", "extractedText måste vara 10–50 000 tecken.");
    }
    const system = `Du strukturerar text från en mattestencil eller lärobok för grundskolan.
Returnera JSON {"problems":[{"originalText":"själva arbetsuppgiften på en rad"}]}
Separera tydliga uppgifter om flera finns.`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let out = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 4096,
        system,
        messages: [{ role: "user", content: txt }],
      });
      out = message.content.map((b) => (b.type === "text" ? b.text : "")).join("").trim();
    } catch (e) {
      logger.error("parseMathProblems", e);
      throw new HttpsError("unavailable", "Kunde inte analysera matteenheterna.");
    }
    let problems: { originalText: string }[] = [];
    try {
      const parsed = JSON.parse(stripFence(out)) as { problems?: unknown };
      const arr = Array.isArray(parsed.problems) ? parsed.problems : [];
      problems = [];
      for (const p of arr) {
        if (p != null && typeof p === "object" && typeof (p as { originalText?: unknown }).originalText === "string") {
          const ox = ((p as { originalText: string }).originalText).trim();
          if (ox.length > 0) problems.push({ originalText: ox });
          if (problems.length >= 40) break;
        }
      }
    } catch {
      throw new HttpsError("internal", "Kunde inte läsa strukturerat svar för matte.");
    }
    if (problems.length === 0) throw new HttpsError("failed-precondition", "Inga problem hittades.");
    return { problems };
  }
);

export const explainMathStep = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Inloggning krävs.");
    const p = typeof request.data?.problemText === "string" ? request.data.problemText.trim() : "";
    if (p.length < 3 || p.length > 8000) {
      throw new HttpsError("invalid-argument", "problemText måste vara 3–8 000 tecken.");
    }
    const sys = `Du förklarar en grundskoleuppgift steg för steg på lätt svenska.
Ge inte klara slutsvarsiffran om det inte behövs; fokusera på resonemang och metod.`;

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 1500,
        system: sys,
        messages: [{ role: "user", content: p }],
      });
      const text = message.content.map((b) => (b.type === "text" ? b.text : "")).join("").trim();
      if (!text) throw new HttpsError("unavailable", "Tomt förklaringssvar.");
      return { explanation: text };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("explainMathStep", e);
      throw new HttpsError("unavailable", "Kunde inte förklara just nu.");
    }
  }
);

export const varyMathProblem = onCall(
  {
    region: "europe-west1",
    secrets: [anthropicApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Inloggning krävs.");
    const p = typeof request.data?.problemText === "string" ? request.data.problemText.trim() : "";
    if (p.length < 3 || p.length > 8000) {
      throw new HttpsError("invalid-argument", "problemText måste vara 3–8 000 tecken.");
    }
    let gradeHint: number | null = null;
    const gh = request.data?.gradeHint;
    if (typeof gh === "number") gradeHint = Math.floor(gh);
    if (typeof gh === "string" && gh.trim()) {
      const n = Number.parseInt(gh.trim(), 10);
      if (!Number.isNaN(n)) gradeHint = n;
    }

    const base = typeof request.data?.homeworkId === "string" ? request.data.homeworkId.trim() : "";
    let gradeFromDoc: number | null = null;

    const db = getDb();
    if (base !== "") {
      const hwSnap = await db.doc(`homework/${base}`).get();
      if (!hwSnap.exists) {
        throw new HttpsError("not-found", "Läxan hittades inte.");
      }
      const fh = hwSnap.data()?.familyId;
      const uSnap = await db.doc(`users/${request.auth.uid}`).get();
      if (fh !== uSnap.data()?.familyId) {
        throw new HttpsError("permission-denied", "Saknar behörighet.");
      }

      const g = hwSnap.data()?.gradeHint;
      if (typeof g === "number") gradeFromDoc = Math.floor(g);
    }

    const effective = gradeHint ?? gradeFromDoc;
    if (effective != null && effective >= 7) {
      throw new HttpsError(
        "failed-precondition",
        "Variera siffror är avstängt för åk 7 eller högre ännu.",
      );
    }

    const sys =
      "Du hjälper en elev med repetition. Ändra ENDAST konkreta tal eller siffervärden;" +
      " behåll samma struktur och svårighetsgrad för en grundsärskole-/mellanstadieelev.\n" +
      `Returnera JSON {"variants":["variant1","variant2"]} med exakt 5 sträng-varianter.`;
    const client = new Anthropic({ apiKey: anthropicApiKey.value() });
    let out = "";
    try {
      const message = await client.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: sys,
        messages: [{ role: "user", content: p }],
      });
      out = message.content.map((b) => (b.type === "text" ? b.text : "")).join("").trim();
    } catch (e) {
      logger.error("varyMathProblem", e);
      throw new HttpsError("unavailable", "Kunde inte skapa variationer nu.");
    }
    try {
      const parsed = JSON.parse(stripFence(out)) as { variants?: unknown };
      const vs = Array.isArray(parsed.variants) ? parsed.variants.filter((x) => typeof x === "string").map(String) : [];
      if (vs.length < 3) throw new Error("too few");
      return { variants: vs.slice(0, 10) };
    } catch (_e1) {
      throw new HttpsError("internal", "Kunde inte tolka matte-varianterna.");
    }
  }
);
