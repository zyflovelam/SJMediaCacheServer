import XCTest
@testable import SJMediaCacheServer

final class PlaceholderTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertNotNil(SJMediaCacheServer.shared())
    }
}
