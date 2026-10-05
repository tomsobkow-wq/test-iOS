import AgentCore
import Foundation

/// A number the model may write as 12, 12.5 or "12,50".
struct LooseNumber: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        let s = try c.decode(String.self).replacingOccurrences(of: ",", with: ".").filter { "0123456789.-".contains($0) }
        guard let d = Double(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a number") }
        value = d
    }
}

public enum DocumentToolbox {
    /// Documents never leave the phone, so these are Lolek's. Bolek runs in the cloud and does not get them.
    public static func tools(store: DocumentStore) -> [any Tool] {
        [
            ListDocumentsTool(store: store), DocumentSummaryTool(store: store), StatementTransactionsTool(store: store),
            StatementBreakdownTool(store: store), DocumentSearchTool(store: store), DeleteDocumentTool(store: store),
        ]
    }
}

private func statement(_ store: DocumentStore, _ id: String?) async throws -> (StoredDocument, ParsedStatement) {
    if let document = await store.document(id: id), let statement = document.statement { return (document, statement) }
    // The named document may not be a statement; fall back to the latest statement.
    if let latest = await store.all.last(where: { $0.statement != nil }), let statement = latest.statement { return (latest, statement) }
    throw ToolError("There is no bank statement in the user's documents.")
}

public struct ListDocumentsTool: Tool, ConditionallyAvailable {
    public let name = "list_documents"
    public let description = LocalizedText(en: "List the user's documents. Only needed when the user asks what documents exist or has several; other tools default to the latest document.", pl: "Wyświetl dokumenty użytkownika. Potrzebne tylko gdy użytkownik pyta, jakie ma dokumenty, lub ma ich kilka; pozostałe narzędzia domyślnie używają ostatniego dokumentu.")
    public let parametersSchema = #"{"type":"object","properties":{}}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.read
    let store: DocumentStore
    public func isAvailable() async -> Bool { !(await store.isEmpty) }
    public func run(argumentsJSON: String) async throws -> String {
        let all = await store.all
        return all.isEmpty ? "No documents yet." : all.map(\.oneLine).joined(separator: "\n")
    }
}

public struct DocumentSummaryTool: Tool, ConditionallyAvailable {
    public let name = "document_summary"
    public let description = LocalizedText(
        en: "Get the summary of a document or bank statement (default: the latest). For statements this has the totals, categories, top merchants and recurring payments.",
        pl: "Pobierz streszczenie dokumentu lub wyciągu bankowego (domyślnie ostatniego). Dla wyciągów zawiera sumy, kategorie, najwięksi sprzedawcy i płatności cykliczne."
    )
    public let parametersSchema = #"{"type":"object","properties":{"document_id":{"type":"string"}}}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.read
    let store: DocumentStore
    struct Args: Decodable { let document_id: String? }
    public func isAvailable() async -> Bool { !(await store.isEmpty) }
    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let document = await store.document(id: args.document_id) else { throw ToolError("No such document. Use list_documents.") }
        if let statement = document.statement { return StatementAnalyzer.digest(statement) }
        return document.summary ?? "This document has no summary yet. Use document_search to look inside it."
    }
}

public struct StatementTransactionsTool: Tool, ConditionallyAvailable {
    public let name = "statement_transactions"
    public let description = LocalizedText(
        en: "Find transactions in a bank statement and get exact totals for them. Use for any question like \"how much did I spend on X\", \"what did I pay to Y\", \"biggest payments in March\". Totals are computed exactly; never add numbers yourself.",
        pl: "Znajdź transakcje w wyciągu bankowym i podaj dokładne sumy. Użyj przy pytaniach typu „ile wydałem na X”, „co zapłaciłem Y”, „największe płatności w marcu”. Sumy są policzone dokładnie; nigdy nie dodawaj liczb samodzielnie."
    )
    public let parametersSchema = #"{"type":"object","properties":{"document_id":{"type":"string"},"from":{"type":"string","description":"YYYY-MM-DD"},"to":{"type":"string","description":"YYYY-MM-DD"},"category":{"type":"string","enum":["groceries","eating_out","transport","fuel","shopping","health","subscriptions","utilities","housing","taxes_insurance","travel","cash","fees","interest","loans","savings","transfers","income","refund","other"]},"merchant":{"type":"string"},"search":{"type":"string","description":"word in the description"},"direction":{"type":"string","enum":["in","out"]},"min_amount":{"type":"number"},"max_amount":{"type":"number"},"sort":{"type":"string","enum":["date","amount"]},"limit":{"type":"integer"}}}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.read
    let store: DocumentStore
    struct Args: Decodable {
        let document_id: String?; let from: String?; let to: String?; let category: String?; let merchant: String?
        let search: String?; let direction: String?; let min_amount: LooseNumber?; let max_amount: LooseNumber?; let sort: String?; let limit: Int?
    }
    public func isAvailable() async -> Bool { await store.all.contains { $0.statement != nil } }
    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let (_, parsed) = try await statement(store, args.document_id)
        var query = StatementQuery()
        query.from = args.from.flatMap { DateParsing.parse($0, order: .dayFirst) }
        query.to = args.to.flatMap { DateParsing.parse($0, order: .dayFirst) }
        if let category = args.category, !category.isEmpty {
            guard Merchants.categories.contains(category) else { throw ToolError("Unknown category \"\(category)\". Use one of: \(Merchants.categories.joined(separator: ", ")).") }
            query.category = category
        }
        query.merchant = args.merchant; query.search = args.search
        query.direction = StatementQuery.Direction(rawValue: args.direction ?? "") ?? .both
        query.minAmount = args.min_amount.map { Int(($0.value * 100).rounded()) }
        query.maxAmount = args.max_amount.map { Int(($0.value * 100).rounded()) }
        query.sort = StatementQuery.Sort(rawValue: args.sort ?? "") ?? .date
        let limit = min(max(args.limit ?? 15, 1), 40)
        return StatementAnalyzer.render(StatementAnalyzer.filter(parsed, query), of: parsed, limit: limit)
    }
}

public struct StatementBreakdownTool: Tool, ConditionallyAvailable {
    public let name = "statement_breakdown"
    public let description = LocalizedText(
        en: "Group a bank statement's transactions by category, merchant or month, with exact totals.",
        pl: "Pogrupuj transakcje z wyciągu według kategorii, sprzedawcy lub miesiąca, z dokładnymi sumami."
    )
    public let parametersSchema = #"{"type":"object","properties":{"by":{"type":"string","enum":["category","merchant","month"]},"document_id":{"type":"string"},"from":{"type":"string"},"to":{"type":"string"},"direction":{"type":"string","enum":["in","out"]}},"required":["by"]}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.read
    let store: DocumentStore
    struct Args: Decodable { let by: String; let document_id: String?; let from: String?; let to: String?; let direction: String? }
    public func isAvailable() async -> Bool { await store.all.contains { $0.statement != nil } }
    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let group = StatementAnalyzer.GroupBy(rawValue: args.by) else { throw ToolError("\"by\" must be category, merchant or month.") }
        let (_, parsed) = try await statement(store, args.document_id)
        var query = StatementQuery()
        query.from = args.from.flatMap { DateParsing.parse($0, order: .dayFirst) }
        query.to = args.to.flatMap { DateParsing.parse($0, order: .dayFirst) }
        query.direction = StatementQuery.Direction(rawValue: args.direction ?? "") ?? .both
        return StatementAnalyzer.breakdown(parsed, by: group, query: query)
    }
}

public struct DocumentSearchTool: Tool, ConditionallyAvailable {
    public let name = "document_search"
    public let description = LocalizedText(
        en: "Search inside the user's documents (contracts, letters, invoices) and get the most relevant passages. Use it to answer questions about a document's content.",
        pl: "Szukaj w dokumentach użytkownika (umowy, listy, faktury) i pobierz najbardziej pasujące fragmenty. Użyj, aby odpowiadać na pytania o treść dokumentu."
    )
    public let parametersSchema = #"{"type":"object","properties":{"query":{"type":"string"},"document_id":{"type":"string"}},"required":["query"]}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.read
    let store: DocumentStore
    struct Args: Decodable { let query: String; let document_id: String? }
    public func isAvailable() async -> Bool { await store.all.contains { $0.kind == .text } }
    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        let hits = await store.search(args.query, in: args.document_id, limit: 3)
        guard !hits.isEmpty else { return "No passage matches \"\(args.query)\". Try different words, or say the document does not mention it." }
        return hits.map { hit in
            "From \"\(hit.document.name)\"\(hit.chunk.page.map { ", page \($0)" } ?? ""):\n\(hit.chunk.text)"
        }.joined(separator: "\n---\n")
    }
}

public struct DeleteDocumentTool: Tool, ConditionallyAvailable {
    public let name = "delete_document"
    public let description = LocalizedText(en: "Permanently delete a document from this phone.", pl: "Trwale usuń dokument z tego telefonu.")
    public let parametersSchema = #"{"type":"object","properties":{"document_id":{"type":"string"}},"required":["document_id"]}"#
    public let tier = ToolTier.lolek
    public let risk = ToolRisk.destructive
    let store: DocumentStore
    struct Args: Decodable { let document_id: String }
    public func isAvailable() async -> Bool { !(await store.isEmpty) }
    public func run(argumentsJSON: String) async throws -> String {
        let args = try ToolArguments.decode(Args.self, from: argumentsJSON)
        guard let document = await store.document(id: args.document_id) else { throw ToolError("No such document.") }
        _ = await store.remove(id: document.id)
        return "Deleted \"\(document.name)\"."
    }
}
