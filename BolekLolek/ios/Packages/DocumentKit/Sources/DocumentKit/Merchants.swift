import Foundation

/// Turns "PLATNOSC KARTA 02.03 BIEDRONKA 1234 WARSZAWA PL" into "Biedronka" and files it under a category.
public enum Merchants {
    public static let categories = [
        "groceries", "eating_out", "transport", "fuel", "shopping", "health", "subscriptions", "utilities", "housing",
        "taxes_insurance", "travel", "cash", "fees", "interest", "loans", "savings", "transfers", "income", "refund", "other",
    ]

    private struct Known { let needles: [String]; let name: String; let category: String }

    private static let known: [Known] = [
        // groceries
        Known(needles: ["biedronka"], name: "Biedronka", category: "groceries"), Known(needles: ["lidl"], name: "Lidl", category: "groceries"),
        Known(needles: ["zabka"], name: "Żabka", category: "groceries"), Known(needles: ["carrefour"], name: "Carrefour", category: "groceries"),
        Known(needles: ["auchan"], name: "Auchan", category: "groceries"), Known(needles: ["kaufland"], name: "Kaufland", category: "groceries"),
        Known(needles: ["netto"], name: "Netto", category: "groceries"), Known(needles: ["dino "], name: "Dino", category: "groceries"),
        Known(needles: ["stokrotka"], name: "Stokrotka", category: "groceries"), Known(needles: ["lewiatan"], name: "Lewiatan", category: "groceries"),
        Known(needles: ["intermarche"], name: "Intermarché", category: "groceries"), Known(needles: ["frisco"], name: "Frisco", category: "groceries"),
        Known(needles: ["aldi"], name: "Aldi", category: "groceries"), Known(needles: ["tesco"], name: "Tesco", category: "groceries"),
        Known(needles: ["sainsbury"], name: "Sainsbury's", category: "groceries"), Known(needles: ["asda"], name: "Asda", category: "groceries"),
        Known(needles: ["morrisons"], name: "Morrisons", category: "groceries"), Known(needles: ["waitrose"], name: "Waitrose", category: "groceries"),
        Known(needles: ["whole foods"], name: "Whole Foods", category: "groceries"), Known(needles: ["trader joe"], name: "Trader Joe's", category: "groceries"),
        Known(needles: ["kroger"], name: "Kroger", category: "groceries"), Known(needles: ["safeway"], name: "Safeway", category: "groceries"),
        // eating out
        Known(needles: ["mcdonald"], name: "McDonald's", category: "eating_out"), Known(needles: ["kfc"], name: "KFC", category: "eating_out"),
        Known(needles: ["burger king"], name: "Burger King", category: "eating_out"), Known(needles: ["starbucks"], name: "Starbucks", category: "eating_out"),
        Known(needles: ["costa coffee", "costa "], name: "Costa", category: "eating_out"), Known(needles: ["pyszne"], name: "Pyszne.pl", category: "eating_out"),
        Known(needles: ["wolt"], name: "Wolt", category: "eating_out"), Known(needles: ["glovo"], name: "Glovo", category: "eating_out"),
        Known(needles: ["uber eats", "ubereats"], name: "Uber Eats", category: "eating_out"), Known(needles: ["deliveroo"], name: "Deliveroo", category: "eating_out"),
        Known(needles: ["just eat"], name: "Just Eat", category: "eating_out"), Known(needles: ["pret a manger"], name: "Pret", category: "eating_out"),
        Known(needles: ["subway"], name: "Subway", category: "eating_out"), Known(needles: ["restauracja", "restaurant", "kawiarnia", "cafe ", "bistro", "pizzeria"], name: "Restaurant or café", category: "eating_out"),
        // transport
        Known(needles: ["uber"], name: "Uber", category: "transport"), Known(needles: ["bolt"], name: "Bolt", category: "transport"),
        Known(needles: ["freenow", "free now"], name: "FreeNow", category: "transport"), Known(needles: ["orlen"], name: "Orlen", category: "fuel"),
        Known(needles: ["shell"], name: "Shell", category: "fuel"), Known(needles: ["circle k"], name: "Circle K", category: "fuel"),
        Known(needles: ["moya"], name: "Moya", category: "fuel"), Known(needles: ["lotos"], name: "Lotos", category: "fuel"),
        Known(needles: ["jakdojade"], name: "Jakdojade", category: "transport"), Known(needles: ["ztm", "mpk ", "zarzad transportu"], name: "Public transport", category: "transport"),
        Known(needles: ["koleo"], name: "Koleo", category: "transport"), Known(needles: ["pkp", "intercity"], name: "PKP", category: "transport"),
        Known(needles: ["flixbus"], name: "FlixBus", category: "transport"), Known(needles: ["parking"], name: "Parking", category: "transport"),
        Known(needles: ["tfl ", "transport for london"], name: "TfL", category: "transport"), Known(needles: ["trainline"], name: "Trainline", category: "transport"),
        // shopping
        Known(needles: ["allegro"], name: "Allegro", category: "shopping"), Known(needles: ["zalando"], name: "Zalando", category: "shopping"),
        Known(needles: ["amazon", "amzn"], name: "Amazon", category: "shopping"), Known(needles: ["empik"], name: "Empik", category: "shopping"),
        Known(needles: ["reserved"], name: "Reserved", category: "shopping"), Known(needles: ["h&m", "h & m"], name: "H&M", category: "shopping"),
        Known(needles: ["zara"], name: "Zara", category: "shopping"), Known(needles: ["decathlon"], name: "Decathlon", category: "shopping"),
        Known(needles: ["vinted"], name: "Vinted", category: "shopping"), Known(needles: ["olx"], name: "OLX", category: "shopping"),
        Known(needles: ["temu"], name: "Temu", category: "shopping"), Known(needles: ["aliexpress"], name: "AliExpress", category: "shopping"),
        Known(needles: ["sinsay"], name: "Sinsay", category: "shopping"), Known(needles: ["ebay"], name: "eBay", category: "shopping"),
        Known(needles: ["ikea"], name: "IKEA", category: "shopping"), Known(needles: ["leroy merlin"], name: "Leroy Merlin", category: "shopping"),
        Known(needles: ["castorama"], name: "Castorama", category: "shopping"), Known(needles: ["media markt", "mediamarkt"], name: "Media Markt", category: "shopping"),
        Known(needles: ["walmart"], name: "Walmart", category: "shopping"), Known(needles: ["target"], name: "Target", category: "shopping"),
        Known(needles: ["costco"], name: "Costco", category: "shopping"),
        // health
        Known(needles: ["apteka", "dr.max", "dr max", "pharmacy", "boots "], name: "Pharmacy", category: "health"),
        Known(needles: ["rossmann"], name: "Rossmann", category: "health"), Known(needles: ["hebe"], name: "Hebe", category: "health"),
        Known(needles: ["medicover"], name: "Medicover", category: "health"), Known(needles: ["lux med", "luxmed"], name: "Lux Med", category: "health"),
        Known(needles: ["enel-med", "enelmed"], name: "Enel-Med", category: "health"), Known(needles: ["znanylekarz"], name: "ZnanyLekarz", category: "health"),
        // subscriptions
        Known(needles: ["netflix"], name: "Netflix", category: "subscriptions"), Known(needles: ["spotify"], name: "Spotify", category: "subscriptions"),
        Known(needles: ["youtube"], name: "YouTube", category: "subscriptions"), Known(needles: ["hbo", "max.com"], name: "HBO Max", category: "subscriptions"),
        Known(needles: ["disney"], name: "Disney+", category: "subscriptions"), Known(needles: ["apple.com/bill", "apple.com bill", "itunes", "icloud"], name: "Apple", category: "subscriptions"),
        Known(needles: ["google one", "google storage", "google *"], name: "Google", category: "subscriptions"), Known(needles: ["canva"], name: "Canva", category: "subscriptions"),
        Known(needles: ["openai", "chatgpt"], name: "OpenAI", category: "subscriptions"), Known(needles: ["anthropic", "claude.ai"], name: "Anthropic", category: "subscriptions"),
        Known(needles: ["audible"], name: "Audible", category: "subscriptions"), Known(needles: ["storytel"], name: "Storytel", category: "subscriptions"),
        Known(needles: ["canal+", "canal plus"], name: "Canal+", category: "subscriptions"), Known(needles: ["prime video"], name: "Prime Video", category: "subscriptions"),
        Known(needles: ["patreon"], name: "Patreon", category: "subscriptions"), Known(needles: ["github"], name: "GitHub", category: "subscriptions"),
        Known(needles: ["dropbox"], name: "Dropbox", category: "subscriptions"), Known(needles: ["microsoft 365", "office 365"], name: "Microsoft 365", category: "subscriptions"),
        // utilities and telecom
        Known(needles: ["tauron"], name: "Tauron", category: "utilities"), Known(needles: ["pge "], name: "PGE", category: "utilities"),
        Known(needles: ["enea"], name: "Enea", category: "utilities"), Known(needles: ["energa"], name: "Energa", category: "utilities"),
        Known(needles: ["pgnig"], name: "PGNiG", category: "utilities"), Known(needles: ["wodociagi", "mpwik"], name: "Water utility", category: "utilities"),
        Known(needles: ["orange"], name: "Orange", category: "utilities"), Known(needles: ["play "], name: "Play", category: "utilities"),
        Known(needles: ["t-mobile", "tmobile"], name: "T-Mobile", category: "utilities"), Known(needles: ["plus gsm", "polkomtel"], name: "Plus", category: "utilities"),
        Known(needles: ["upc ", "vectra", "netia", "inea"], name: "Internet provider", category: "utilities"),
        Known(needles: ["british gas", "edf energy", "thames water", "octopus energy"], name: "Utility", category: "utilities"),
        Known(needles: ["vodafone", "o2 ", "giffgaff"], name: "Mobile provider", category: "utilities"),
        // taxes and insurance
        Known(needles: ["zus", "zaklad ubezpieczen spolecznych"], name: "ZUS", category: "taxes_insurance"),
        Known(needles: ["urzad skarbowy", "us "], name: "Tax office", category: "taxes_insurance"), Known(needles: ["hmrc"], name: "HMRC", category: "taxes_insurance"),
        Known(needles: ["pzu"], name: "PZU", category: "taxes_insurance"), Known(needles: ["warta"], name: "Warta", category: "taxes_insurance"),
        Known(needles: ["ergo hestia"], name: "Ergo Hestia", category: "taxes_insurance"), Known(needles: ["allianz"], name: "Allianz", category: "taxes_insurance"),
        Known(needles: ["council tax"], name: "Council tax", category: "taxes_insurance"),
        // travel
        Known(needles: ["ryanair"], name: "Ryanair", category: "travel"), Known(needles: ["wizz"], name: "Wizz Air", category: "travel"),
        Known(needles: ["lot polish", "lot.com"], name: "LOT", category: "travel"), Known(needles: ["booking.com"], name: "Booking.com", category: "travel"),
        Known(needles: ["airbnb"], name: "Airbnb", category: "travel"), Known(needles: ["expedia"], name: "Expedia", category: "travel"),
        Known(needles: ["lufthansa"], name: "Lufthansa", category: "travel"), Known(needles: ["easyjet"], name: "easyJet", category: "travel"),
        Known(needles: ["hotel"], name: "Hotel", category: "travel"),
    ]

    private struct Rule { let needles: [String]; let category: String }

    /// Generic words, checked after known merchants. Folded (no diacritics).
    private static let rules: [Rule] = [
        Rule(needles: ["bankomat", "wyplata gotowki", "wyplata z bankomatu", "cash withdrawal", "atm ", "cash machine"], category: "cash"),
        Rule(needles: ["odsetki", "interest paid", "interest charged", "interest "], category: "interest"),
        Rule(needles: ["oplata za", "prowizja", "oplata miesieczna", "oplata za prowadzenie", "fee", "charge", "maintenance", "abonament za konto"], category: "fees"),
        Rule(needles: ["rata kredytu", "splata kredytu", "kredyt", "pozyczka", "loan", "mortgage", "splata karty"], category: "loans"),
        Rule(needles: ["czynsz", "wspolnota mieszkaniowa", "spoldzielnia", "rent ", "landlord", "najem"], category: "housing"),
        Rule(needles: ["ubezpieczenie", "insurance", "podatek", "tax "], category: "taxes_insurance"),
        Rule(needles: ["lokata", "oszczednosci", "savings", "konto oszczednosciowe", "skarbonka"], category: "savings"),
        Rule(needles: ["zwrot", "refund", "reversal", "chargeback"], category: "refund"),
        Rule(needles: ["wynagrodzenie", "pensja", "salary", "payroll", "wages"], category: "income"),
        Rule(needles: ["przelew wlasny", "own transfer", "between accounts", "miedzy rachunkami", "przelew na rachunek wlasny"], category: "transfers"),
    ]

    public static func category(for text: String, merchantCategory: String?, minorUnits: Int) -> String {
        let folded = " " + text.folded + " "
        // Money coming back from a shop is a refund, not shopping.
        if minorUnits > 0, merchantCategory != nil, !folded.contains("wynagrodzenie"), !folded.contains("salary") { return "refund" }
        if let merchantCategory { return merchantCategory }
        for rule in rules where rule.needles.contains(where: { folded.contains($0) }) {
            // A "fee" word on a credit is usually a refund, not a fee.
            if rule.category == "fees", minorUnits > 0 { continue }
            return rule.category
        }
        if folded.contains("przelew") || folded.contains("transfer") || folded.contains("blik") || folded.contains("payment from") {
            return minorUnits > 0 ? "income" : "transfers"
        }
        return minorUnits > 0 ? "income" : "other"
    }

    public static func knownMerchant(in text: String) -> (name: String, category: String)? {
        let folded = " " + text.folded + " "
        for entry in known where entry.needles.contains(where: { folded.contains($0) }) { return (entry.name, entry.category) }
        return nil
    }

    // MARK: Cleaning unknown merchants

    private static func tolerant(_ phrase: String) -> String {
        let classes: [Character: String] = ["a": "[aą]", "c": "[cć]", "e": "[eę]", "l": "[lł]", "n": "[nń]", "o": "[oó]", "s": "[sś]", "z": "[zźż]"]
        return phrase.map { classes[$0] ?? NSRegularExpression.escapedPattern(for: String($0)) }.joined()
    }

    private static let noiseRegexes: [NSRegularExpression] = {
        let phrases = [
            "platnosc karta debetowa", "platnosc karta", "platnosc blik", "transakcja karta", "transakcja kartowa", "zakup przy uzyciu karty",
            "operacja karta", "karta debetowa", "przelew zewnetrzny", "przelew wewnetrzny", "przelew przychodzacy", "przelew wychodzacy",
            "przelew na rachunek", "przelew z rachunku", "przelew", "zlecenie state", "zlecenie stale", "polecenie zaplaty", "blik",
            "apple pay", "google pay", "card payment to", "card payment", "debit card purchase", "purchase authorized on", "pos purchase",
            "direct debit", "standing order", "faster payment", "bill payment", "online transfer", "transfer to", "transfer from",
            "payment to", "payment from", "bank transfer", "contactless", "card purchase", "visa", "mastercard",
        ]
        let cities = ["warszawa", "krakow", "wroclaw", "poznan", "gdansk", "gdynia", "lodz", "katowice", "szczecin", "lublin", "bialystok", "london", "dublin", "berlin"]
        var patterns = phrases.map { #"(?i)\b"# + tolerant($0) + #"\b"# }
        patterns += cities.map { #"(?i)\b"# + tolerant($0) + #"\b"# }
        patterns += [
            #"\b\d{1,2}[./]\d{1,2}([./]\d{2,4})?\b"#,   // dates
            #"[*xX]{2,}\d{2,4}"#,                         // masked card numbers
            #"\b\d{5,}\b"#,                               // long ids
            #"#\d+"#,
            #"\bnr\.?\s*\w*\d\w*"#,
            #"\b(PL|GB|UK|US|DE|IE|NL)\b\s*$"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    public static func cleanName(_ raw: String) -> String {
        if let known = knownMerchant(in: raw) { return known.name }
        var text = raw
        for regex in noiseRegexes {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        let words = text.split(whereSeparator: { " ,;:|/-".contains($0) || $0 == "\u{00A0}" })
            .map(String.init).filter { $0.contains(where: \.isLetter) }
        guard !words.isEmpty else { return raw.collapsedWhitespace.prefix(30).description }
        return words.prefix(3).map { word in
            word.count <= 3 ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
