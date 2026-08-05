import Foundation
import XCTest
@testable import Riff

final class ClipboardSectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 6, hour: 12
        ))!
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 8
        ))!
    }

    func testBucketAssignment() {
        XCTAssertEqual(
            ClipboardTimeBucket.bucket(for: date(2026, 8, 6), calendar: calendar, now: now),
            .today
        )
        XCTAssertEqual(
            ClipboardTimeBucket.bucket(for: date(2026, 8, 5), calendar: calendar, now: now),
            .yesterday
        )
        XCTAssertEqual(
            ClipboardTimeBucket.bucket(for: date(2026, 8, 3), calendar: calendar, now: now),
            .thisWeek
        )
        XCTAssertEqual(
            ClipboardTimeBucket.bucket(for: date(2026, 8, 1), calendar: calendar, now: now),
            .thisMonth
        )
        XCTAssertEqual(
            ClipboardTimeBucket.bucket(for: date(2026, 3, 15), calendar: calendar, now: now),
            .thisYear
        )
        XCTAssertEqual(
            ClipboardTimeBucket.bucket(for: date(2025, 12, 31), calendar: calendar, now: now),
            .older
        )
    }

    func testSectionsAreOrderedAndGrouped() {
        let items = [
            ClipboardItem(kind: .text, text: "去年", createdAt: date(2025, 12, 31)),
            ClipboardItem(kind: .text, text: "今天", createdAt: date(2026, 8, 6)),
            ClipboardItem(kind: .text, text: "本月", createdAt: date(2026, 8, 1)),
            ClipboardItem(kind: .text, text: "昨天", createdAt: date(2026, 8, 5)),
            ClipboardItem(kind: .text, text: "今年", createdAt: date(2026, 3, 15))
        ]

        let sections = ClipboardSection.sections(for: items)

        XCTAssertEqual(
            sections.map(\.bucket),
            [.today, .yesterday, .thisMonth, .thisYear, .older]
        )
        XCTAssertEqual(sections[0].items.map(\.text), ["今天"])
        XCTAssertEqual(sections[1].items.map(\.text), ["昨天"])
        XCTAssertEqual(sections[2].items.map(\.text), ["本月"])
        XCTAssertEqual(sections[3].items.map(\.text), ["今年"])
        XCTAssertEqual(sections[4].items.map(\.text), ["去年"])
    }
}
