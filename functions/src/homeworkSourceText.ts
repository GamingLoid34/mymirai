/**
 * Urval av extraherad text per bilageroll (roadmap v6).
 * Klienten sparar `attachments[].role` och `extractedText`.
 */

export type AttachmentRow = {
  role: string;
  extractedText: string;
};

export function readAttachmentRows(hw: Record<string, unknown>): AttachmentRow[] {
  const raw = hw.attachments;
  if (!Array.isArray(raw)) return [];
  const out: AttachmentRow[] = [];
  for (const e of raw) {
    if (e == null || typeof e !== "object") continue;
    const o = e as Record<string, unknown>;
    const roleRaw = typeof o.role === "string" ? o.role.trim().toLowerCase() : "mixed";
    const extracted =
      typeof o.extractedText === "string" ? o.extractedText.trim() : "";
    out.push({
      role: roleRaw !== "" ? roleRaw : "mixed",
      extractedText: extracted,
    });
  }
  return out;
}

/** Fallback när inga bilagerader eller alla saknar text. */
export function fullExtractedText(hw: Record<string, unknown>): string {
  return typeof hw.extractedText === "string" ? hw.extractedText.trim() : "";
}

/**
 * Underlag för saga (listeningStory) och generateFlashcards — undvik Q&A-dokument.
 */
export function mergedExtractedExcludingQa(hw: Record<string, unknown>): string {
  const rows = readAttachmentRows(hw);
  if (rows.length === 0) {
    return fullExtractedText(hw);
  }
  const pieces = rows
    .filter((r) => r.role !== "qa")
    .map((r) => r.extractedText)
    .filter((t) => t.length > 0);
  const joined = pieces.join("\n\n");
  if (joined.length > 0) {
    return joined;
  }
  return fullExtractedText(hw);
}

/**
 * Underlag för parseQuestionsAndAnswers — först explicit qa, annars mixed, annars hela fältet.
 */
export function mergedExtractedForQaParse(hw: Record<string, unknown>): string {
  const rows = readAttachmentRows(hw);
  const full = fullExtractedText(hw);
  if (rows.length === 0) {
    return full;
  }

  const qaParts = rows
    .filter((r) => r.role === "qa")
    .map((r) => r.extractedText)
    .filter((t) => t.length > 0);
  if (qaParts.length > 0) {
    return qaParts.join("\n\n");
  }

  const mixedParts = rows
    .filter((r) => r.role === "mixed")
    .map((r) => r.extractedText)
    .filter((t) => t.length > 0);
  if (mixedParts.length > 0) {
    return mixedParts.join("\n\n");
  }

  return full;
}
