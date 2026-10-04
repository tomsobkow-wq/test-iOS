import AgentCore
import AppIntents
import Foundation

/// The one set of services shared by the chat and by App Intents, so a payment
/// logged from a Shortcut lands in the same store the assistants read.
enum AppServices {
    static let spending: SpendingStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SpendingStore(fileURL: base.appendingPathComponent("BolekLolek/spending.json"))
    }()

    static let device = DeviceServices(
        weather: AppleWeather(),
        calendar: EventKitCalendar(),
        contacts: SystemContacts(),
        notifications: LocalNotifications(),
        urlOpener: SystemURLOpener(),
        spending: spending
    )
}

/// The action the Shortcuts "Transaction" automation calls on every Apple Pay
/// payment. Apple does not let apps create that automation themselves, so the
/// assistant walks the user through a one-time setup.
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log payment"
    static let description = IntentDescription("Records an Apple Pay payment on this iPhone for spending tracking.")
    static let openAppWhenRun = false

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Amount")
    var amount: String

    @Parameter(title: "Card")
    var card: String?

    func perform() async throws -> some IntentResult {
        guard let parsed = AmountParser.parse(amount) else { return .result() }
        let expense = Expense(
            date: Date(),
            minorUnits: parsed.minorUnits,
            currency: parsed.currency,
            merchant: merchant,
            category: ExpenseCategorizer.category(forMerchant: merchant),
            card: card,
            source: .automatic
        )
        await AppServices.spending.add(expense)
        return .result()
    }
}
