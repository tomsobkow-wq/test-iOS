import XCTest

/// Drives the real app on the phone and saves screenshots, so a developer (or Claude) can see what a user sees.
/// Run: xcodebuild test -scheme BolekLolekUI -destination 'id=<udid>' -resultBundlePath <path>
final class BolekFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Sends and waits until the answer is finished (not a fixed sleep); returns how long it took.
    @discardableResult
    private func ask(_ text: String, timeout: TimeInterval = 150) -> TimeInterval {
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "message field")
        field.tap()
        field.typeText(text)
        app.buttons["send-button"].tap()
        let start = Date()
        Thread.sleep(forTimeInterval: 1.0)
        let idle = app.otherElements["chat-idle"]
        _ = idle.waitForExistence(timeout: timeout)
        return Date().timeIntervalSince(start)
    }

    private func send(_ text: String, waitSeconds: TimeInterval) {
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "message field")
        field.tap()
        field.typeText(text)
        app.buttons["send-button"].tap()
        Thread.sleep(forTimeInterval: waitSeconds)
    }

    func testBolekHelloAndFlights() throws {
        shot("01-launch")
        let bolek = app.buttons["Bolek"].firstMatch
        if bolek.waitForExistence(timeout: 10) { bolek.tap() }
        shot("02-bolek-open")
        send("Hello, who are you?", waitSeconds: 25)
        shot("03-hello-reply")
        send("Find flights from Warsaw to Lisbon on 2026-11-19, back 2026-11-26", waitSeconds: 60)
        shot("04-flights-reply")
    }

    func testWatchNeedsApprovalThenLolekAnswers() throws {
        let bolek = app.buttons["Bolek"].firstMatch
        if bolek.waitForExistence(timeout: 10) { bolek.tap() }
        send("Watch flights from Warsaw to Lisbon on 2026-12-03, back 2026-12-10, and alert me below 700 PLN", waitSeconds: 45)
        shot("05-approval-asked")
        let allow = app.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 20) {
            allow.tap()
            Thread.sleep(forTimeInterval: 30)
            shot("06-watch-created")
        } else {
            XCTFail("no approval prompt appeared")
        }
        let lolek = app.buttons["Lolek"].firstMatch
        if lolek.waitForExistence(timeout: 10) { lolek.tap() }
        shot("07-lolek-open")
        send("What can you do without internet?", waitSeconds: 60)
        shot("08-lolek-reply")
    }

    func testPlusMenuOffersGmailAndExplainsWhenNotSetUp() throws {
        let plus = app.buttons["Add a document or statement"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "plus menu")
        plus.tap()
        shot("09-plus-menu")
        let connect = app.buttons["Connect Gmail"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 5), "Connect Gmail entry")
        connect.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("10-after-connect-tap")
    }

    /// Needs wyciag-wrzesien-2026.csv in the app's Documents folder (copied there with devicectl).
    func testStatementQuestions() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_IMPORT"] = "wyciag-wrzesien-2026.csv"
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        shot("11-statement-summary")
        let questions = [
            "Ile wydałem w Biedronce we wrześniu?",
            "Ile wydałem na paliwo?",
            "Jaki był mój największy wydatek?",
            "Ile łącznie wydałem i ile zarobiłem?",
        ]
        for (index, question) in questions.enumerated() {
            send(question, waitSeconds: index == 0 ? 90 : 45)
            shot("12-q\(index + 1)")
        }
    }

    /// Mail screen with a made-up mailbox (BOLEK_DEBUG_MAIL_FIXTURE): no real email is ever shown.
    func testMailScreenWithFixtureMailbox() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "2"
        app.launch()
        let button = app.buttons["mail-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "mail button")
        Thread.sleep(forTimeInterval: 1.5)
        shot("20-lolek-with-mail-button")
        button.tap()
        Thread.sleep(forTimeInterval: 3)
        shot("21-mail-today")
        app.buttons["Unread"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("22-mail-unread")
        app.buttons["All"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        app.swipeUp()
        shot("23-mail-all-scrolled")
        app.buttons["People"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Weekend'")).firstMatch
        if row.waitForExistence(timeout: 5) { row.tap() }
        Thread.sleep(forTimeInterval: 2)
        shot("24-mail-detail")
    }

    /// Lolek's real on-device model answering over the made-up mailbox, and the Summarise button from the Mail screen.
    func testMailQuestionsWithFixtureMailbox() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        var timings: [String] = []
        func step(_ name: String, _ text: String) {
            let seconds = ask(text)
            timings.append("\(name) \(Int(seconds))s")
            shot("\(name) \(Int(seconds))s")
        }
        step("30-today", "What emails did I get today?")
        step("31-unread", "Ile mam nieprzeczytanych maili?")
        step("32-people", "Which of today's emails are from real people?")
        step("33-promos", "How many promotion emails today?")
        app.buttons["mail-button"].tap()
        Thread.sleep(forTimeInterval: 3)
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Weekend'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Weekend row")
        row.tap()
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mail-summarise"].tap()
        let start = Date()
        Thread.sleep(forTimeInterval: 2)
        _ = app.otherElements["chat-idle"].waitForExistence(timeout: 150)
        shot("34-summarise \(Int(Date().timeIntervalSince(start)))s")
        step("35-followup", "Ile ta rezerwacja kosztuje?")
        let note = XCTAttachment(string: timings.joined(separator: "\n"))
        note.name = "timings"
        note.lifetime = .keepAlways
        add(note)
    }

    /// Open an email from the Mail screen, summarise it, then ask a money question that must be answered from the email.
    func testOpenedEmailFollowUpStaysOnTheEmail() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["mail-button"].tap()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["All"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Weekend'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Weekend row")
        row.tap()
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mail-summarise"].tap()
        Thread.sleep(forTimeInterval: 2)
        _ = app.otherElements["chat-idle"].waitForExistence(timeout: 200)
        shot("40-summary")
        let seconds = ask("Ile ta rezerwacja kosztuje?", timeout: 200)
        shot("41-followup \(Int(seconds))s")
    }

    // MARK: Phone functions (never calls anyone, never taps Send)

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Taps the system permission prompts we expect (location, notifications, calendar, contacts). Never anything about calls.
    /// Contacts get the least access: "Select Contacts" with nothing selected.
    private func answerSystemPrompts() {
        let hosts: [XCUIApplication] = [springboard, app]
        for host in hosts {
            let alert = host.alerts.firstMatch
            if alert.exists {
                let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").lowercased()
                if text.contains("call") { alert.buttons.allElementsBoundByIndex.first { $0.label.lowercased().contains("cancel") }?.tap(); return }
                for name in ["Allow While Using App", "Allow Full Access", "Allow", "Continue", "OK"] {
                    let button = alert.buttons[name]
                    if button.exists { button.tap(); return }
                }
            }
            // The contacts chooser is never answered automatically.
        }
    }

    /// Like `ask`, but also answers permission prompts and approves in-app requests that are not about phone calls.
    @discardableResult
    private func askHandlingPrompts(_ text: String, approve: Bool = false, timeout: TimeInterval = 120) -> TimeInterval {
        let field = app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "message field")
        field.tap()
        field.typeText(text)
        app.buttons["send-button"].tap()
        let start = Date()
        Thread.sleep(forTimeInterval: 1.0)
        while Date().timeIntervalSince(start) < timeout {
            answerSystemPrompts()
            if approve, app.buttons["Allow"].exists {
                let asksAboutCalling = app.staticTexts.allElementsBoundByIndex.contains { $0.label.lowercased().contains("phone call") || $0.label.lowercased().contains("zadzwo") }
                if asksAboutCalling {
                    app.buttons["Not now"].tap()
                    XCTFail("a call approval appeared; refused")
                } else {
                    app.buttons["Allow"].tap()
                }
            }
            if app.otherElements["chat-idle"].exists { break }
            if app.state != .runningForeground { break }  // Messages or Maps took over
            Thread.sleep(forTimeInterval: 1)
        }
        return Date().timeIntervalSince(start)
    }

    private func lastReplyContains(_ needle: String) -> Bool {
        app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains(needle) }
    }

    func testPhoneFunctionsWithoutCallingAnyone() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 4)
        var report: [String] = []

        // Weather for a named place (no location needed).
        var seconds = askHandlingPrompts("What's the weather in Warsaw?")
        shot("50-weather-warsaw \(Int(seconds))s")
        report.append("weather named: \(lastReplyContains("°") ? "ok" : "NO TEMPERATURE")")

        // Weather here: needs the location permission; the answer names your town, so no screenshot is kept.
        seconds = askHandlingPrompts("What's the weather here?")
        report.append("weather here: \(lastReplyContains("°") ? "ok" : "NO TEMPERATURE") \(Int(seconds))s")

        seconds = askHandlingPrompts("Set a timer for 1 minute")
        shot("51-timer \(Int(seconds))s")
        seconds = askHandlingPrompts("Remind me to drink water in 2 minutes")
        shot("52-reminder \(Int(seconds))s")

        let note = XCTAttachment(string: "weather/timer/reminder done")
        note.name = "report"
        note.lifetime = .keepAlways
        add(note)
    }

    func testPhoneFunctionsContactsCalendarTextMaps() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 4)
        var report: [String] = []
        var seconds: TimeInterval = 0

        // Contacts are not part of the automated run: iOS's picker lists real names, and sharing contacts is the owner's choice.

        // Calendar: one test event far in the future, then read that day back (only the test event is there).
        seconds = askHandlingPrompts("Add a calendar event called Lolek test on 2027-01-02 at 03:00 for 30 minutes", approve: true)
        shot("54-calendar-add \(Int(seconds))s")
        seconds = askHandlingPrompts("What is on my calendar on 2027-01-02?")
        shot("55-calendar-read \(Int(seconds))s")

        // Text: only prepares a draft to a made-up number; the test never taps Send.
        seconds = askHandlingPrompts("Text +48000000000 saying: Lolek test, please ignore", approve: true)
        Thread.sleep(forTimeInterval: 3)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "56-text-draft (app state \(app.state.rawValue))"
        screen.lifetime = .keepAlways
        add(screen)
        report.append("text: app went to background = \(app.state != .runningForeground)")
        app.activate()
        Thread.sleep(forTimeInterval: 3)

        // Maps: opens Apple Maps; no screenshot because it would show where you are.
        seconds = askHandlingPrompts("Directions to Zamek Królewski in Warsaw")
        Thread.sleep(forTimeInterval: 3)
        report.append("maps: app went to background = \(app.state != .runningForeground)")
        app.activate()
        Thread.sleep(forTimeInterval: 2)

        let note = XCTAttachment(string: report.joined(separator: "\n"))
        note.name = "report"
        note.lifetime = .keepAlways
        add(note)

        // Remove the test event again.
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 6)
    }
}
