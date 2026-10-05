import AgentCore
import XCTest
@testable import LolekRuntime

/// Not a pass/fail test: generates the Polish review set. Skipped unless POLISH_REVIEW_OUT is set.
///     POLISH_REVIEW_OUT=~/Developer/polish-review/outputs.json LOLEK_MODEL_DIR=~/Developer/lolek-models \
///     OPENROUTER_API_KEY=sk-or-... swift test --filter PolishReviewGenerator
/// Both models answer through the app's own code path (same session, same Polish system prompt, no tools).
final class PolishReviewGenerator: XCTestCase {
    private struct Prompt: Decodable { let id: String; let category: String; let prompt: String }

    func testGeneratePolishReviewSet() async throws {
        guard let out = ProcessInfo.processInfo.environment["POLISH_REVIEW_OUT"], !out.isEmpty else { throw XCTSkip("set POLISH_REVIEW_OUT") }
        let modelDir = ProcessInfo.processInfo.environment["LOLEK_MODEL_DIR"] ?? ""
        let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        let url = try XCTUnwrap(Bundle.module.url(forResource: "polish_review_prompts", withExtension: "json", subdirectory: "Fixtures"))
        let prompts = try JSONDecoder().decode([Prompt].self, from: Data(contentsOf: url))

        let qwenProvider: LlamaCppProvider? = modelDir.isEmpty ? nil : LlamaCppProvider(
            model: LocalModels.qwen35, store: ModelStore(directory: URL(fileURLWithPath: (modelDir as NSString).expandingTildeInPath))
        )
        if let store = qwenProvider.map({ _ in ModelStore(directory: URL(fileURLWithPath: (modelDir as NSString).expandingTildeInPath)) }),
           !store.isInstalled(LocalModels.qwen35) { try store.markVerified(LocalModels.qwen35) }
        let kimiProvider: OpenRouterProvider? = key.isEmpty ? nil : OpenRouterProvider(apiKey: { key })

        struct AllowAll: ApprovalHandler { func decide(_ r: ApprovalRequest) async -> ApprovalDecision { .allowOnce } }
        func answer(_ provider: any ModelProvider, _ text: String) async -> (String, Double) {
            let session = AgentSession(mode: .lolek, provider: provider, registry: ToolRegistry([]), approvalHandler: AllowAll(), language: .pl)
            let started = Date()
            let reply = (try? await session.send(text).last?.text) ?? "[błąd generowania]"
            return (reply, Date().timeIntervalSince(started))
        }

        var results: [[String: Any]] = []
        for item in prompts {
            var row: [String: Any] = ["id": item.id, "category": item.category, "prompt": item.prompt]
            if let qwenProvider {
                let (text, seconds) = await answer(qwenProvider, item.prompt)
                row["qwen"] = text; row["qwen_seconds"] = (seconds * 10).rounded() / 10
            }
            if let kimiProvider {
                let (text, seconds) = await answer(kimiProvider, item.prompt)
                row["kimi"] = text; row["kimi_seconds"] = (seconds * 10).rounded() / 10
            }
            print("[\(item.id)] done")
            results.append(row)
            let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
        }
    }
}
