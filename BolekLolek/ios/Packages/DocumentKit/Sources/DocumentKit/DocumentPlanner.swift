import AgentCore
import Foundation

/// Reads the user's message and, when it is clearly about a statement or document, picks the tool call itself.
/// Anything it is unsure about is left to the model. Built from what a 4B model got wrong in testing: it skipped
/// the tools and made numbers up, or called list_documents and stopped.
public struct DocumentPlanner: TurnPlanner {
    private let store: DocumentStore

    public init(store: DocumentStore) { self.store = store }

    // MARK: Vocabulary (folded: lowercase, no diacritics; matched as word prefixes)

    private static let summaryWords = ["stresc", "streszcz", "podsumuj", "podsumow", "wyjasni", "wytlumacz", "omow", "opisz", "przeanaliz", "analiz",
                                       "summar", "explain", "overview", "describe", "analys", "analyz", "review"]
    private static let statementWords = ["wyciag", "statement", "konto", "konta", "account", "transakcj", "transaction", "bank"]
    private static let documentWords = ["umow", "dokument", "faktur", "invoice", "contract", "document", "agreement", "pdf", "plik", "file", "pism", "regulamin",
                                        "ofert", "offer", "polis", "zalacznik", "attachment", "list"]
    private static let financialWords = ["wydal", "wydat", "zaplac", "plac", "koszt", "kosztuj", "ile", "saldo", "wplyn", "wplyw", "otrzyma", "zarob", "przychod",
                                         "dochod", "bilans", "subskryp", "oplat", "gotowk", "bankomat", "rachun", "spent", "spend", "paid", "pay", "cost", "balance",
                                         "income", "received", "earn", "withdr", "cash", "fee", "biggest", "largest", "most", "much", "many", "how", "total", "razem",
                                         "lacznie", "transakc", "kupil", "wyplac", "przelew", "transfer", "saved", "oszczed", "platnos", "zaplat", "wydatk", "expens", "payment"]
    private static let incomeWords = ["wplyn", "wplyw", "otrzyma", "zarobi", "przychod", "dochod", "income", "received", "earn", "salary", "pensj", "wynagrodz",
                                      "deposit", "came", "credited", "uznan"]
    private static let superlatives = ["najwiek", "najwiec", "najdrozs", "najwyzs", "biggest", "largest", "highest", "most", "expensive", "top"]
    private static let totalsWords = ["lacznie", "razem", "w sumie", "total", "altogether", "overall", "saldo", "balance", "bilans", "wiecej niz zarobi", "net"]

    /// Ordered: specific before general. `ambiguous` means more than one category could be meant.
    private static let categories: [(id: String, stems: [String], ambiguous: Bool)] = [
        ("groceries", ["spozyw", "grocer", "supermarket"], false),
        ("eating_out", ["restaura", "kawiarn", "lunch", "takeaway", "dining", "eating out", "cafe", "coffee", "kawa "], false),
        ("subscriptions", ["subskryp", "subscription", "streaming"], false),
        ("fuel", ["paliw", "benzyn", "fuel", "petrol", "gasoline", "tankowa"], false),
        ("transport", ["transport", "taxi", "taksowk", "dojazd", "commut", "przejazd"], false),
        ("health", ["zdrowi", "lekarz", "apteka", "health", "pharmacy", "doctor", "medical"], false),
        ("utilities", ["rachunki", "media", "prad", "internet", "telefon", "utilit", "bills", "mobile", "energy"], false),
        ("housing", ["czynsz", "mieszkani", "rent", "wynajem", "mortgage"], false),
        ("taxes_insurance", ["podat", "ubezpiecz", "tax", "insurance"], false),
        ("travel", ["podroz", "wakacj", "hotel", "flight", "holiday", "lot "], false),
        ("cash", ["gotowk", "bankomat", "cash", "atm"], false),
        ("fees", ["oplat", "prowizj", "fees", "fee ", "charges"], false),
        ("interest", ["odsetk", "interest"], false),
        ("loans", ["kredyt", "rata", "raty", "pozyczk", "loan"], false),
        ("savings", ["oszczedn", "lokat", "savings"], false),
        ("refund", ["zwrot", "refund"], false),
        ("shopping", ["zakupy", "shopping", "ubrani", "clothes"], false),
        ("eating_out", ["jedzeni", "food", "zywnosc"], true),
    ]

    private static let months: [(stem: String, number: Int)] = [
        ("stycz", 1), ("jan", 1), ("lut", 2), ("feb", 2), ("marc", 3), ("mar", 3), ("kwie", 4), ("apr", 4), ("maj", 5), ("may", 5), ("czerw", 6), ("jun", 6),
        ("lip", 7), ("jul", 7), ("sierp", 8), ("aug", 8), ("wrzes", 9), ("sep", 9), ("pazdz", 10), ("oct", 10), ("listop", 11), ("nov", 11), ("grud", 12), ("dec", 12),
    ]

    // MARK: Planning

    public func plan(userText: String, language: ConversationLanguage) async -> [ToolCall] {
        let documents = await store.all
        guard !documents.isEmpty else { return [] }
        let folded = " " + userText.folded.collapsedWhitespace + " "
        let tokens = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ stems: [String]) -> Bool { stems.contains { stem in tokens.contains { $0.hasPrefix(stem.trimmingCharacters(in: .whitespaces)) } || (stem.contains(" ") && folded.contains(stem)) } }

        let statements = documents.filter { $0.statement != nil }
        let texts = documents.filter { $0.kind == .text }
        let mentionsStatement = has(Self.statementWords)
        let mentionsDocument = has(Self.documentWords) || documents.contains { doc in
            Stemmer.tokens(doc.name.replacingOccurrences(of: ".", with: " ")).contains { name in name.count > 3 && Stemmer.tokens(userText).contains(name) }
        }
        let wantsSummary = has(Self.summaryWords)

        // Which document is this about?
        let aboutStatement: Bool
        switch (statements.isEmpty, texts.isEmpty) {
        case (false, true): aboutStatement = true
        case (true, false): aboutStatement = false
        default: aboutStatement = mentionsStatement || (!mentionsDocument && has(Self.financialWords))
        }

        if aboutStatement, let document = statements.last, let statement = document.statement {
            return planStatement(statement, documentID: document.id, tokens: tokens, folded: folded, has: has, wantsSummary: wantsSummary, mentionsStatement: mentionsStatement)
        }
        if !texts.isEmpty { return await planText(texts, userText: userText, wantsSummary: wantsSummary, mentionsDocument: mentionsDocument) }
        return []
    }

    private func call(_ name: String, _ arguments: [String: Any]) -> ToolCall {
        let data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
        return ToolCall(id: "planned-\(UUID().uuidString.prefix(8))", name: name, argumentsJSON: String(decoding: data, as: UTF8.self))
    }

    private func planStatement(
        _ statement: ParsedStatement, documentID: String, tokens: [String], folded: String,
        has: ([String]) -> Bool, wantsSummary: Bool, mentionsStatement: Bool
    ) -> [ToolCall] {
        // Not a question about money at all ("Cześć", "co potrafisz"): leave it to the model.
        let category = Self.categories.first { entry in has(entry.stems) }
        var merchant = matchMerchant(in: tokens, statement: statement)
        // An explicit category ("gotówka", "fees") beats a merchant name the bank merely wrote in free text.
        if let found = merchant, !found.known, let category, !category.ambiguous { merchant = nil }
        let financial = has(Self.financialWords) || has(Self.superlatives) || merchant != nil || category != nil
        guard wantsSummary || financial else { return [] }

        // "Summarise / explain my statement", balance, totals.
        if wantsSummary && merchant == nil && category == nil { return [call("document_summary", ["document_id": documentID])] }
        if has(Self.totalsWords) && merchant == nil && category == nil { return [call("document_summary", ["document_id": documentID])] }

        var args: [String: Any] = ["document_id": documentID]
        let incoming = has(Self.incomeWords)
        if incoming { args["direction"] = "in" } else if category?.id != "income" { args["direction"] = "out" }
        if let range = monthRange(in: tokens, statement: statement) { args["from"] = range.from; args["to"] = range.to }

        // "What do I spend the most on?" asks about categories, not single payments.
        if has(Self.superlatives), merchant == nil, category == nil, folded.contains(" na co ") || folded.contains("what do i spend") || folded.contains("where does my money") {
            return [call("statement_breakdown", ["by": "category", "direction": "out", "document_id": documentID])]
        }
        if has(Self.superlatives) {
            args["sort"] = "amount"
            args["limit"] = 3
            if let merchant { args["merchant"] = merchant.name }
            if let category, !category.ambiguous, category.id != "income" { args["category"] = category.id }
            return [call("statement_transactions", args)]
        }
        if let merchant {
            args["merchant"] = merchant.name
            args.removeValue(forKey: "direction")   // "Ile zapłaciłem za Ubera" may include refunds; show both ways
            return [call("statement_transactions", args)]
        }
        if let category {
            if category.ambiguous { return [call("statement_breakdown", ["by": "category", "direction": "out", "document_id": documentID])] }
            if category.id == "income" { args.removeValue(forKey: "direction"); args["category"] = "income"; return [call("statement_transactions", args)] }
            args["category"] = category.id
            if ["refund", "interest"].contains(category.id) { args.removeValue(forKey: "direction") }
            return [call("statement_transactions", args)]
        }
        if incoming { return [call("statement_transactions", args)] }
        return [call("document_summary", ["document_id": documentID])]
    }

    private func planText(_ texts: [StoredDocument], userText: String, wantsSummary: Bool, mentionsDocument: Bool) async -> [ToolCall] {
        let target = texts.last!
        if wantsSummary && (mentionsDocument || texts.count == 1) { return [call("document_summary", ["document_id": target.id])] }
        let best = await store.search(userText, in: nil, limit: 1).first
        // Search when the question mentions documents or any passage shares real words with it. Retrieval is cheap and a
        // small model that is not shown the text will guess; small talk matches nothing and is left alone.
        if mentionsDocument || (best?.score ?? 0) >= 0.5 { return [call("document_search", ["query": userText])] }
        return []
    }

    // MARK: Matching

    /// Recognised brands match loosely, so Polish endings work ("Ubera" finds Uber, "Biedronce" finds Biedronka). Merchant names
    /// built from the bank's free text only match a whole word, so "month" cannot find "Monthly Account Fee".
    private func matchMerchant(in tokens: [String], statement: ParsedStatement) -> (name: String, known: Bool)? {
        let monthStems = Self.months.map(\.stem)
        func isMonthWord(_ token: String) -> Bool { monthStems.contains { token.hasPrefix($0) && token.count <= $0.count + 6 } }
        let userTokens = tokens.filter { $0.count >= 4 && !isMonthWord($0) }
        guard !userTokens.isEmpty else { return nil }
        func shared(_ a: String, _ b: String) -> Int { zip(a, b).prefix { $0 == $1 }.count }
        var best: (name: String, known: Bool, score: Int)?
        for merchant in Set(statement.transactions.map(\.merchant)) {
            let known = Merchants.knownMerchant(in: merchant) != nil
            for part in merchant.folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) where part.count >= 4 {
                for token in userTokens {
                    let common = shared(token, part)
                    let matches = known ? (common >= min(5, part.count, token.count) && common * 2 >= min(part.count, token.count)) : token == part
                    if matches, common > (best?.score ?? 0) { best = (merchant, known, common) }
                }
            }
        }
        return best.map { ($0.name, $0.known) }
    }

    private func monthRange(in tokens: [String], statement: ParsedStatement) -> (from: String, to: String)? {
        guard let start = statement.periodStart, let end = statement.periodEnd,
              DateParsing.monthKey(start) != DateParsing.monthKey(end) else { return nil }
        for token in tokens {
            guard let entry = Self.months.first(where: { token.hasPrefix($0.stem) && token.count <= $0.stem.count + 6 }) else { continue }
            let year = DateParsing.parts(end).year
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            guard let first = DateParsing.date(year: year, month: entry.number, day: 1),
                  let last = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
            return (String(format: "%04d-%02d-01", year, entry.number), String(format: "%04d-%02d-%02d", year, entry.number, last))
        }
        return nil
    }
}
