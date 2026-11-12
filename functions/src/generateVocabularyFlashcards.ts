import { FieldValue } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getDb } from "./admin";

type Vocab = { term: string; translation: string; example?: string };

/** Skapar kort term→ översättning och översättning→ term (ingen AI). */
export const generateVocabularyFlashcards = onCall(
  {
    region: "europe-west1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const uid = request.auth.uid;
    const body = request.data as { homeworkId?: unknown } | null;
    if (body == null || typeof body !== "object") {
      throw new HttpsError("invalid-argument", "Ogiltigt anrop.");
    }
    const homeworkId =
      typeof body.homeworkId === "string" ? body.homeworkId.trim() : "";
    if (!homeworkId) {
      throw new HttpsError("invalid-argument", "homeworkId saknas.");
    }

    const db = getDb();
    const userSnap = await db.doc(`users/${uid}`).get();
    const userFamilyId = userSnap.data()?.familyId;
    if (typeof userFamilyId !== "string" || userFamilyId === "") {
      throw new HttpsError("failed-precondition", "Saknar familj för användaren.");
    }

    const hwRef = db.doc(`homework/${homeworkId}`);
    const hwSnap = await hwRef.get();
    if (!hwSnap.exists) {
      throw new HttpsError("not-found", "Läxan hittades inte.");
    }
    const hw = hwSnap.data() ?? {};
    const hwFamily = hw.familyId;
    if (hwFamily !== userFamilyId) {
      throw new HttpsError("permission-denied", "Tillhör inte din familj.");
    }
    const hType = typeof hw.homeworkType === "string" ? hw.homeworkType.trim() : "text";
    if (hType !== "vocabulary") {
      throw new HttpsError("failed-precondition", "Läxan är inte en gloslista.");
    }

    const vRaw = hw.vocabulary;
    const pairs: Vocab[] = [];
    if (Array.isArray(vRaw)) {
      for (const e of vRaw) {
        if (e != null && typeof e === "object") {
          const term = typeof (e as { term?: unknown }).term === "string" ? (e as { term: string }).term.trim() : "";
          const trans =
            typeof (e as { translation?: unknown }).translation === "string"
              ? (e as { translation: string }).translation.trim()
              : "";
          if (term && trans) pairs.push({ term, translation: trans });
        }
      }
    }

    if (pairs.length === 0) {
      throw new HttpsError("failed-precondition", "Läxan saknar strukturerade glosor.");
    }

    const homeworkTitle =
      typeof hw.title === "string" && hw.title.trim() !== "" ? hw.title.trim() : "Glosor";
    const homeworkSubjectRaw = hw.subject;
    const homeworkSubject =
      typeof homeworkSubjectRaw === "string" && homeworkSubjectRaw.trim() !== ""
        ? homeworkSubjectRaw.trim()
        : null;

    type Card = { front: string; back: string };

    const cards: Card[] = [];
    for (const p of pairs) {
      cards.push({
        front: p.term,
        back: p.translation,
      });
      cards.push({
        front: p.translation,
        back: p.term,
      });
    }

    const oldDeckId =
      typeof hw.linkedDeckId === "string" ? hw.linkedDeckId.trim() : null;
    if (oldDeckId) {
      const oldCardsSnap = await db
        .collection("flashcards")
        .where("deckId", "==", oldDeckId)
        .get();
      const deleteBatch = db.batch();
      for (const d of oldCardsSnap.docs) {
        deleteBatch.delete(d.ref);
      }
      deleteBatch.delete(db.doc(`decks/${oldDeckId}`));
      await deleteBatch.commit();
      logger.info(
        `generateVocabularyFlashcards: replaced deck=${oldDeckId} with ${cards.length} cards (deleted ${oldCardsSnap.size} old cards)`
      );
    }

    const deckRef = db.collection("decks").doc();
    const deckId = deckRef.id;
    const batch = db.batch();

    batch.set(deckRef, {
      familyId: userFamilyId,
      homeworkId,
      title: homeworkTitle,
      subject: homeworkSubject,
      cardCount: cards.length,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (const c of cards) {
      const cardRef = db.collection("flashcards").doc();
      batch.set(cardRef, {
        deckId,
        familyId: userFamilyId,
        front: c.front,
        back: c.back,
        source: "vocabulary",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        repetitions: 0,
        easeFactor: 2.5,
        intervalDays: 0,
        lastReviewedAt: null,
        nextReviewAt: null,
        lastQuizVerdict: null,
        lastQuizAt: null,
      });
    }

    batch.update(hwRef, {
      linkedDeckId: deckId,
      updatedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    logger.info(`generateVocabularyFlashcards done deck=${deckId} cards=${cards.length}`);

    return { deckId, cardCount: cards.length };
  }
);
