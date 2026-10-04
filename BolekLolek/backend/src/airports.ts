// Models and people say "Warszawa" or "Lizbona"; the flight data wants IATA codes. A small table of the cities that
// matter for Polish travellers covers most requests. Anything else asks the user for the airport code.
const CITIES: Record<string, string> = {
  // Poland
  warszawa: "WAW", warsaw: "WAW", krakow: "KRK", cracow: "KRK", gdansk: "GDN", wroclaw: "WRO", poznan: "POZ", katowice: "KTW",
  lodz: "LCJ", szczecin: "SZZ", rzeszow: "RZE", lublin: "LUZ", bydgoszcz: "BZG", modlin: "WMI",
  // Europe
  lizbona: "LIS", lisbon: "LIS", porto: "OPO", madryt: "MAD", madrid: "MAD", barcelona: "BCN", malaga: "AGP", alicante: "ALC", palma: "PMI",
  londyn: "LON", london: "LON", paryz: "PAR", paris: "PAR", rzym: "ROM", rome: "ROM", mediolan: "MIL", milan: "MIL", wenecja: "VCE", venice: "VCE",
  neapol: "NAP", naples: "NAP", berlin: "BER", monachium: "MUC", munich: "MUC", frankfurt: "FRA", amsterdam: "AMS", bruksela: "BRU", brussels: "BRU",
  wieden: "VIE", vienna: "VIE", praga: "PRG", prague: "PRG", budapeszt: "BUD", budapest: "BUD", ateny: "ATH", athens: "ATH", stambul: "IST", istanbul: "IST",
  kopenhaga: "CPH", copenhagen: "CPH", sztokholm: "STO", stockholm: "STO", oslo: "OSL", helsinki: "HEL", dublin: "DUB", zurych: "ZRH", zurich: "ZRH",
  genewa: "GVA", geneva: "GVA", edynburg: "EDI", edinburgh: "EDI", malta: "MLA", larnaka: "LCA", dubrownik: "DBV", split: "SPU",
  // Elsewhere
  nowyjork: "NYC", newyork: "NYC", chicago: "CHI", losangeles: "LAX", dubaj: "DXB", dubai: "DXB", bangkok: "BKK", tokio: "TYO", tokyo: "TYO",
  kair: "CAI", cairo: "CAI", marrakesz: "RAK", marrakech: "RAK", tunis: "TUN", agadir: "AGA", teneryfa: "TFS", tenerife: "TFS",
};

function key(text: string): string {
  return text.toLowerCase().replace(/ł/g, "l").normalize("NFD").replace(/\p{Diacritic}/gu, "").replace(/[^a-z]/g, "");
}

export type Airport = { code: string } | { error: string };

/** "WAW", "waw", "Warszawa" and "Kraków" all work. */
export function resolveAirport(input: string): Airport {
  const trimmed = input.trim();
  if (/^[A-Za-z]{3}$/.test(trimmed)) return { code: trimmed.toUpperCase() };
  const code = CITIES[key(trimmed)];
  if (code) return { code };
  return { error: `I do not know an airport for "${input}". Ask the user for the 3-letter airport code (for example WAW, KRK, LIS).` };
}
