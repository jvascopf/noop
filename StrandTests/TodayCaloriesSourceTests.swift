import XCTest
@testable import Strand

/// The Today calorie tile opens the source it shows: the strap's heart-rate estimate when the day has one,
/// Apple Health's active energy only otherwise (personal fork).
final class TodayCaloriesSourceTests: XCTestCase {
    func testTheStrapEstimateWinsOverHealth() {
        let both = MetricCatalog.todayCaloriesMetric(hasImportedKcal: true, hasOnDeviceKcal: true)
        XCTAssertEqual(both?.key, "energy_kcal")
        XCTAssertEqual(both?.source, "my-whoop")
    }

    func testHealthIsTheFallbackWithoutStrapHR() {
        let health = MetricCatalog.todayCaloriesMetric(hasImportedKcal: true, hasOnDeviceKcal: false)
        XCTAssertEqual(health?.key, "active_kcal")
        XCTAssertEqual(health?.source, "apple-health")
    }
}
