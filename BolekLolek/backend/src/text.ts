/** Lowercase, no accents, so "Rower elektryczny" matches "rower elektryczny" and "Łódź" matches "lodz". */
export function fold(text: string): string {
  return text.replace(/ł/g, "l").replace(/Ł/g, "L").normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

/** Words of two or more letters, and any number (a lone "3" in "Urbano 3" is part of the model name). */
export function words(text: string): string[] {
  return fold(text).split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 1 || /\d/.test(w));
}

/** Share of the wanted words that appear in the title (0 to 1). */
export function overlap(wanted: string[], title: string): number {
  if (wanted.length === 0) return 0;
  const haystack = fold(title);
  return wanted.filter((w) => haystack.includes(w)).length / wanted.length;
}
