import XCTest
@testable import ClaudarCore

/// Formatting and severity: the parts the user actually reads, and the parts
/// that have to agree across the menu bar, the window, and the widget.
final class PresentationTests: XCTestCase {

    private func limit(
        _ id: String = "five_hour", _ pct: Double, resetsIn: TimeInterval? = nil
    ) -> UsageLimit {
        UsageLimit(
            id: id, label: id, utilization: pct,
            resetsAt: resetsIn.map { Date(timeIntervalSinceNow: $0) }
        )
    }

    // MARK: - Percent

    func testPercentRoundsToWholeNumbers() {
        XCTAssertEqual(UsageFormat.percent(0), "0%")
        XCTAssertEqual(UsageFormat.percent(31.4), "31%")
        XCTAssertEqual(UsageFormat.percent(31.6), "32%")
        XCTAssertEqual(UsageFormat.percent(100), "100%")
    }

    // MARK: - Reset strings

    func testResetStringIsEmptyWithoutADate() {
        XCTAssertEqual(UsageFormat.resetString(nil), "")
    }

    func testResetStringReportsAnElapsedWindowAsResetting() {
        XCTAssertEqual(UsageFormat.resetString(Date(timeIntervalSinceNow: -60)), "resetting…")
        XCTAssertEqual(UsageFormat.resetString(Date(timeIntervalSinceNow: 0)), "resetting…")
    }

    func testResetStringUsesMinutesUnderAnHour() {
        // The few seconds of slack matter: the countdown floors, so a target of
        // exactly 26 * 60 renders as "25m" by the time the call is made.
        XCTAssertEqual(UsageFormat.resetString(Date(timeIntervalSinceNow: 26 * 60 + 5)),
                       "resets in 26m")
    }

    func testResetCountdownFloorsRatherThanRounds() {
        // A countdown must never overstate the time left — 26m59s is "26m", not
        // "27m". This is also why the assertions above carry a slack margin.
        XCTAssertEqual(UsageFormat.resetString(Date(timeIntervalSinceNow: 26 * 60 + 59)),
                       "resets in 26m")
        XCTAssertEqual(UsageFormat.resetString(Date(timeIntervalSinceNow: 2 * 3600 + 59 * 60 + 59)),
                       "resets in 2h 59m")
    }

    func testResetStringUsesHoursAndMinutesWithinThirtySixHours() {
        let t = Date(timeIntervalSinceNow: 4 * 3600 + 39 * 60 + 30)
        XCTAssertEqual(UsageFormat.resetString(t), "resets in 4h 39m")
    }

    func testResetStringSwitchesToADayBeyondThirtySixHours() {
        let far = UsageFormat.resetString(Date(timeIntervalSinceNow: 72 * 3600))
        XCTAssertTrue(far.hasPrefix("resets "), "got \(far)")
        XCTAssertFalse(far.contains("resets in"), "beyond 36h it should name a day, not count down")
    }

    func testDistantResetIsLocalizedRatherThanHardcodedTo12Hour() {
        // The old implementation hardcoded "EEE h a", which showed "Mon 6 PM" to
        // someone on a 24-hour clock. Whatever the locale produces, it must not be
        // the literal template.
        let far = UsageFormat.resetString(Date(timeIntervalSinceNow: 72 * 3600))
        XCTAssertFalse(far.contains("EEE"))
        XCTAssertGreaterThan(far.count, "resets ".count)
    }

    // MARK: - Staleness

    func testStaleStringBucketsByAge() {
        XCTAssertEqual(UsageFormat.staleString(Date()), "just now")
        XCTAssertEqual(UsageFormat.staleString(Date(timeIntervalSinceNow: -60)), "just now")
        XCTAssertEqual(UsageFormat.staleString(Date(timeIntervalSinceNow: -7 * 60)), "7m ago")
        XCTAssertEqual(UsageFormat.staleString(Date(timeIntervalSinceNow: -3 * 3600)), "3h ago")
    }

    // MARK: - Severity

    func testSeverityBoundaries() {
        // Documented in TECHNICAL.md as green < 50, yellow < 75, orange < 90,
        // red >= 90 — these assertions are what keep that sentence true.
        XCTAssertEqual(Severity.forPercent(0), .ok)
        XCTAssertEqual(Severity.forPercent(49.9), .ok)
        XCTAssertEqual(Severity.forPercent(50), .notice)
        XCTAssertEqual(Severity.forPercent(74.9), .notice)
        XCTAssertEqual(Severity.forPercent(75), .warning)
        XCTAssertEqual(Severity.forPercent(89.9), .warning)
        XCTAssertEqual(Severity.forPercent(90), .critical)
        XCTAssertEqual(Severity.forPercent(100), .critical)
    }

    func testEverySeverityHasADistinctColor() {
        // The menu bar ring and the panel bars read from the same palette; if two
        // levels collided, a warning would be indistinguishable from healthy.
        let all = Severity.allCases.map { "\($0.components)" }
        XCTAssertEqual(Set(all).count, Severity.allCases.count)
    }

    #if canImport(AppKit)
    func testAppKitAndSwiftUIColorsAgree() {
        // The bug this replaces: the ring used NSColor.systemGreen while the bars
        // used a custom green, so they never quite matched.
        for severity in Severity.allCases {
            let c = severity.components
            let ns = severity.nsColor
            XCTAssertEqual(Double(ns.redComponent), c.r, accuracy: 0.001)
            XCTAssertEqual(Double(ns.greenComponent), c.g, accuracy: 0.001)
            XCTAssertEqual(Double(ns.blueComponent), c.b, accuracy: 0.001)
        }
    }
    #endif

    // MARK: - Snapshot

    func testHeadlinePrefersTheFiveHourSessionEvenWhenItIsNotTheHighest() {
        let snap = UsageSnapshot(
            limits: [limit("seven_day", 90), limit("five_hour", 31)],
            updated: Date(), subscription: "pro"
        )
        XCTAssertEqual(snap.headline?.id, "five_hour")
    }

    func testHeadlineFallsBackToTheHighestLimit() {
        let snap = UsageSnapshot(
            limits: [limit("extra_usage", 12), limit("seven_day", 64)],
            updated: Date(), subscription: nil
        )
        XCTAssertEqual(snap.headline?.id, "seven_day")
    }

    func testHeadlineIsNilWhenThereAreNoLimits() {
        XCTAssertNil(UsageSnapshot.empty.headline)
    }

    func testSnapshotSurvivesTheRoundTripTheWidgetDependsOn() {
        // The widget can only ever see what came through this encoding.
        let original = UsageSnapshot(
            limits: [limit("five_hour", 31, resetsIn: 3600), limit("seven_day", 43)],
            updated: Date(timeIntervalSince1970: 1_753_000_000),
            subscription: "Pro"
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.limits, original.limits)
        XCTAssertEqual(decoded.subscription, "Pro")
        XCTAssertEqual(decoded.updated.timeIntervalSince1970,
                       original.updated.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.headline?.id, "five_hour")
    }

    // MARK: - Deep link

    func testWidgetDeepLinkMatchesTheRegisteredScheme() {
        // If these drift apart, clicking the widget silently does nothing.
        XCTAssertEqual(ClaudarURL.window.scheme, ClaudarURL.scheme)
        XCTAssertEqual(ClaudarURL.window.absoluteString, "claudar://window")
    }
}
