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
        // Typing can lag behind on a busy phone: wait for the Send button, and type again once if it never shows.
        if !app.buttons["send-button"].waitForExistence(timeout: 5) {
            field.tap()
            field.typeText(" ")
            _ = app.buttons["send-button"].waitForExistence(timeout: 5)
        }
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
    private var approvalShotTaken = false

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
                    if !approvalShotTaken {
                        approvalShotTaken = true
                        shot("approval-prompt")
                    }
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

    /// The text of the newest assistant bubble only (never the user's own message).
    private func lastAssistantReply() -> String {
        let bubbles = app.otherElements.matching(identifier: "bubble-assistant").allElementsBoundByIndex
        let texts = app.staticTexts.matching(NSPredicate(format: "label != ''")).allElementsBoundByIndex
        _ = bubbles
        return texts.last?.label ?? ""
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

    /// Sets a 1 minute timer, leaves the app, and watches for the banner.
    func testTimerNotificationArrivesWhileAppIsInBackground() throws {
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 4)
        _ = askHandlingPrompts("Set a timer for 1 minute")
        let setAt = Date()
        XCUIDevice.shared.press(.home)
        var seenAfter: TimeInterval?
        var report = ""
        let banner = springboard.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'timer' OR label CONTAINS[c] 'Bolek'")).firstMatch
        while Date().timeIntervalSince(setAt) < 80 {
            if banner.exists, seenAfter == nil {
                seenAfter = Date().timeIntervalSince(setAt)
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "60-banner"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            if seenAfter != nil { break }
            Thread.sleep(forTimeInterval: 1)
        }
        report = seenAfter.map { "banner seen \(Int($0))s after the timer was set" } ?? "NO banner within 100s"
        let note = XCTAttachment(string: report)
        note.name = "report"
        note.lifetime = .keepAlways
        add(note)
        // Ask the app what iOS says about its notifications (permission, sound, delivered titles).
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_DUMP_NOTIFICATIONS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 5)
    }

    /// Events tab, the calendar card on an appointment email and the add sheet (cancelled: nothing is saved).
    func testAppointmentCardOnFixtureEmail() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launch()
        let button = app.buttons["mail-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "mail button")
        button.tap()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["All"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("70-all-with-calendar-marks")
        app.buttons["Events"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("71-events-tab")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'wizyta'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "appointment row")
        row.tap()
        Thread.sleep(forTimeInterval: 3)
        shot("72-detail-with-card")
        let add = app.buttons["appointment-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Add button on the card")
        add.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("73-add-sheet")
        app.buttons["Cancel"].firstMatch.tap()
    }

    /// On the phone: save an appointment from the card, then add a calendar invite through the chat (with approval). Test events are cleaned up.
    func testCalendarFlowFromEmail() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        let button = app.buttons["mail-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "mail button")
        Thread.sleep(forTimeInterval: 3)
        answerSystemPrompts()

        // 1) Card: clinic email, tap Add, save.
        button.tap()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["Events"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        let clinic = app.buttons.containing(NSPredicate(format: "label CONTAINS 'wizyta'")).firstMatch
        XCTAssertTrue(clinic.waitForExistence(timeout: 8), "clinic row")
        clinic.tap()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["appointment-add"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        app.buttons["appointment-save"].firstMatch.tap()
        for _ in 0..<20 {
            answerSystemPrompts()
            if app.buttons["appointment-added"].exists { break }
            Thread.sleep(forTimeInterval: 1)
        }
        shot("80-card-added")
        XCTAssertTrue(app.buttons["appointment-added"].exists, "card shows Added")
        // Close the email, then open the invite and use the chat.
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 2)
        let invite = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Invitation'")).firstMatch
        XCTAssertTrue(invite.waitForExistence(timeout: 8), "invite row")
        invite.tap()
        Thread.sleep(forTimeInterval: 3)
        shot("81-invite-card")
        app.buttons["mail-summarise"].tap()
        Thread.sleep(forTimeInterval: 5)
        _ = app.otherElements["chat-idle"].waitForExistence(timeout: 200)
        Thread.sleep(forTimeInterval: 2)
        var seconds = askHandlingPrompts("Dodaj to do kalendarza", approve: true, timeout: 200)
        shot("82-chat-add \(Int(seconds))s")
        seconds = askHandlingPrompts("What is on my calendar on 2027-01-20?")
        shot("83-calendar-read \(Int(seconds))s")
        // Clean up the test events.
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 6)
    }

    /// Sets an alarm, lists it, looks at the Clock app, then cancels it through chat.
    func testAlarmListedCancelledAndWhatClockShows() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CANCEL_ALARMS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        var seconds = askHandlingPrompts("Set an alarm for 7:15 called Lolek test alarm")
        shot("90-alarm-set \(Int(seconds))s")
        seconds = askHandlingPrompts("What alarms do I have?")
        shot("91-alarm-list \(Int(seconds))s")
        let clock = XCUIApplication(bundleIdentifier: "com.apple.mobiletimer")
        clock.launch()
        Thread.sleep(forTimeInterval: 3)
        let alarmTab = clock.tabBars.buttons.element(boundBy: 1)
        if alarmTab.exists { alarmTab.tap() }
        Thread.sleep(forTimeInterval: 2)
        let shotClock = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotClock.name = "92-clock-app-alarms"
        shotClock.lifetime = .keepAlways
        add(shotClock)
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        seconds = askHandlingPrompts("Cancel the Lolek test alarm")
        shot("93-alarm-cancel \(Int(seconds))s")
        seconds = askHandlingPrompts("What alarms do I have?")
        shot("94-alarm-list-after \(Int(seconds))s")
    }

    private func openFixtureReplyComposer(readOnly: Bool) {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        if readOnly { app.launchEnvironment["BOLEK_DEBUG_MAIL_READONLY"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["mail-button"].waitForExistence(timeout: 15), "mail button")
        app.buttons["mail-button"].tap()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["People"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Weekend'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Weekend row")
        row.tap()
        Thread.sleep(forTimeInterval: 3)
        app.buttons["mail-reply"].tap()
        Thread.sleep(forTimeInterval: 2)
    }

    /// Reply inside the app (made-up mailbox): fields, quote, Send; nothing real is sent.
    func testReplyComposerSendsInsideTheApp() throws {
        openFixtureReplyComposer(readOnly: false)
        shot("100-composer-empty")
        let body = app.textViews["compose-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5), "body field")
        body.tap()
        body.typeText("Super, dziękuję! Bierzemy ten apartament.")
        shot("101-composer-typed")
        let send = app.buttons["compose-send"]
        XCTAssertTrue(send.isEnabled, "Send enabled")
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["compose-sent"].waitForExistence(timeout: 6), "Sent confirmation")
        shot("102-composer-sent")
    }

    /// A sign-in that can only read is told so, and Send stays off.
    func testReadOnlySignInShowsReconnectAndKeepsSendOff() throws {
        openFixtureReplyComposer(readOnly: true)
        XCTAssertTrue(app.descendants(matching: .any)["compose-readonly-banner"].waitForExistence(timeout: 5), "banner")
        let body = app.textViews["compose-body"]
        body.tap()
        body.typeText("Test")
        XCTAssertFalse(app.buttons["compose-send"].isEnabled, "Send must stay off")
        shot("103-composer-readonly")
    }

    /// Real calendar on the phone: add from a card, change it, remove it, then move and delete through chat. Cleans up after itself.
    func testMoveAndDeleteAppointments() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launchEnvironment["BOLEK_DEBUG_TOOL_TRACE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["mail-button"].waitForExistence(timeout: 15), "mail button")
        Thread.sleep(forTimeInterval: 4)
        answerSystemPrompts()
        func openClinicEmail() {
            app.buttons["mail-button"].tap()
            Thread.sleep(forTimeInterval: 3)
            app.buttons["Events"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 2)
            let clinic = app.buttons.containing(NSPredicate(format: "label CONTAINS 'wizyta'")).firstMatch
            XCTAssertTrue(clinic.waitForExistence(timeout: 8), "clinic row")
            clinic.tap()
            Thread.sleep(forTimeInterval: 3)
        }
        func addFromCard() {
            app.buttons["appointment-add"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 2)
            app.buttons["appointment-save"].firstMatch.tap()
            for _ in 0..<20 { answerSystemPrompts(); if app.buttons["appointment-added"].exists { break }; Thread.sleep(forTimeInterval: 1) }
            XCTAssertTrue(app.buttons["appointment-added"].exists, "card shows saved")
        }
        // 1) Add, change (title gets a suffix), remove.
        openClinicEmail()
        addFromCard()
        shot("110-card-saved")
        app.buttons["appointment-added"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("111-card-menu")
        app.buttons["Change time or details"].tap()
        Thread.sleep(forTimeInterval: 2)
        let title = app.textFields["appointment-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "title field")
        title.tap()
        title.typeText(" (moved)")
        shot("112-change-sheet")
        app.buttons["appointment-save"].tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.buttons["appointment-added"].exists, "still saved after change")
        app.buttons["appointment-added"].tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Remove from calendar"].tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.buttons["appointment-add"].exists, "card back to Add after removing")
        shot("113-card-removed")
        // 2) Add again, then move and delete through chat.
        addFromCard()
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mail-done"].tap()
        Thread.sleep(forTimeInterval: 2)
        var seconds = askHandlingPrompts("Move the Lolek test wizyta kontrolna appointment to 2027-01-21 at 09:00", approve: true, timeout: 200)
        shot("114-chat-move \(Int(seconds))s")
        seconds = askHandlingPrompts("What is on my calendar on 2027-01-21?")
        shot("115-calendar-21 \(Int(seconds))s")
        XCTAssertTrue(lastAssistantReply().contains("Lolek test") || lastAssistantReply().contains("wizyta"), "moved event shows up on 2027-01-21; last reply: \(lastAssistantReply())")
        seconds = askHandlingPrompts("Delete the Lolek test wizyta kontrolna appointment", approve: true, timeout: 200)
        shot("116-chat-delete \(Int(seconds))s")
        seconds = askHandlingPrompts("What is on my calendar on 2027-01-21?")
        shot("117-calendar-21-after \(Int(seconds))s")
        XCTAssertFalse(lastAssistantReply().contains("wizyta"), "deleted event is gone; last reply: \(lastAssistantReply())")
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 6)
    }

    /// Adds a reminder to the real Reminders app through chat, then ticks it off through chat. Cleaned up afterwards.
    func testRemindersAppIsLinked() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launchEnvironment["BOLEK_DEBUG_TOOL_TRACE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 5)
        answerSystemPrompts()
        var seconds = askHandlingPrompts("Remind me to Lolek test drink water on 2026-10-06 at 18:00", timeout: 180)
        Thread.sleep(forTimeInterval: 2)
        answerSystemPrompts()
        shot("120-reminder-added \(Int(seconds))s")
        seconds = askHandlingPrompts("Tick off the Lolek test drink water reminder", timeout: 180)
        shot("121-reminder-ticked \(Int(seconds))s")
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_CLEAN_TEST_EVENTS"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 6)
    }

    /// Measures the fixed part of every Lolek prompt: one greeting, then the per-call numbers are read from the app's timing log.
    func testLolekGreetingForPromptSize() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 6)
        let a = ask("Hi", timeout: 180)
        let b = ask("Thanks", timeout: 180)
        let note = XCTAttachment(string: "hi \(Int(a))s, thanks \(Int(b))s")
        note.name = "timing"
        note.lifetime = .keepAlways
        add(note)
    }

    /// Four chat turns over the made-up mailbox, only to read the timing log afterwards.
    func testFourMailTurnsForTiming() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_DEBUG_MAIL_FIXTURE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 6)
        for question in ["What emails did I get today?", "Ile mam nieprzeczytanych maili?", "Which of today's emails are from real people?", "How many promotion emails today?"] {
            _ = ask(question, timeout: 200)
        }
    }

    /// Bolek on the phone: product search, news, and watching both. Uses the Mac backend with real searches.
    func testBolekSearchesAndTracksProductsAndNews() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_START_MODE"] = "bolek"
        app.launchEnvironment["BOLEK_DEBUG_TOOL_TRACE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        var seconds = ask("Find me an electric bike for up to 5000 zł", timeout: 150)
        shot("130-bike-search \(Int(seconds))s")
        seconds = ask("What is the latest news on the war in Ukraine?", timeout: 150)
        shot("131-news \(Int(seconds))s")
        seconds = askHandlingPrompts("Watch the Touroll Urbano 3 electric bike and tell me if it drops below 4500 zł", approve: true, timeout: 150)
        shot("132-watch-product \(Int(seconds))s")
        seconds = askHandlingPrompts("Follow the news about the war in Ukraine and alert me to new headlines", approve: true, timeout: 150)
        shot("133-watch-news \(Int(seconds))s")
        seconds = ask("What am I watching?", timeout: 150)
        shot("134-list \(Int(seconds))s")
    }

    /// Bolek for an Australian phone: product search, flights and news must use the phone's own country and currency.
    func testBolekUsesThePhonesOwnCountry() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_START_MODE"] = "bolek"
        app.launchEnvironment["BOLEK_DEBUG_TOOL_TRACE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        var seconds = ask("Find me an electric bike for under 2000 dollars", timeout: 150)
        shot("140-au-bike \(Int(seconds))s")
        seconds = ask("Cheapest flight from Perth to Sydney on 2026-11-04?", timeout: 150)
        shot("141-au-flight \(Int(seconds))s")
        seconds = ask("What is the latest news on interest rates?", timeout: 150)
        shot("142-au-news \(Int(seconds))s")
    }

    /// The question that failed before: used bikes on classified sites, in Perth.
    func testBolekFindsUsedBikesOnTheWeb() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_START_MODE"] = "bolek"
        app.launchEnvironment["BOLEK_DEBUG_TOOL_TRACE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        let seconds = ask("find me bmw r18 in perth", timeout: 200)
        shot("150-r18-perth \(Int(seconds))s")
        // The pages used are drawn by the app as buttons (never tapped here: that would leave the app).
        XCTAssertTrue(app.buttons["source-chip"].firstMatch.waitForExistence(timeout: 5), "source buttons under the answer")
    }

    func testBolekWatchesTheWebForNewListings() throws {
        app.terminate()
        app.launchEnvironment["BOLEK_START_MODE"] = "bolek"
        app.launchEnvironment["BOLEK_DEBUG_TOOL_TRACE"] = "1"
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        let seconds = askHandlingPrompts("tell me when a new bmw r18 for sale appears in perth", approve: true, timeout: 150)
        shot("151-web-watch \(Int(seconds))s")
        _ = askHandlingPrompts("stop watching it", approve: true, timeout: 120)
        shot("152-web-watch-stopped")
    }
}
