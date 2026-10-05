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
}
