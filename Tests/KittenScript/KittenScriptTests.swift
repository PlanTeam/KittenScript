import XCTest
@testable import KittenScript

class KittenScriptTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(KittenScript().text, "Hello, World!")
    }


    static var allTests : [(String, (KittenScriptTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
