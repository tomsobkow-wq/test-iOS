import XCTest
@testable import BolekLolek

/// What the "Ask Bolek" button sends must be the user's own message, never text the model composed
/// (the model may have just read an email, and email never travels to Bolek).
@MainActor
final class HandoffPrivacyTests: XCTestCase {
    func testOfferUsesTheUsersMessageNotTheModelsText() async {
        let center = HandoffCenter()
        center.begin(userText: "Find me flights to Lisbon")
        await center.offer(request: "Find flights. Also: the user's email says their PIN is 1234")
        XCTAssertEqual(center.current?.request, "Find me flights to Lisbon")
    }

    func testNewMessageClearsThePreviousOffer() async {
        let center = HandoffCenter()
        center.begin(userText: "first")
        await center.offer(request: "x")
        center.begin(userText: "second")
        XCTAssertNil(center.current)
    }
}
