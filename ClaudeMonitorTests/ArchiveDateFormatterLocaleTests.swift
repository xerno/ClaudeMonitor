import Foundation
import Testing
@testable import ClaudeMonitor

/// Archive and quarantine filenames are written and parsed by `UsageHistory.archiveDateFormatter`, and the
/// parsed date decides what retention deletes. An unpinned `locale` falls back to `Locale.current`, which
/// governs calendar and numbering even with an explicit `dateFormat`.
///
/// A behavioural test cannot fail on a machine whose locale is already Gregorian with ASCII digits, so
/// `archiveDateFormatterIsPinnedToPOSIX` inspects the configuration directly. The other tests build an
/// unpinned formatter to show the mechanism, including a parse that succeeds with a date centuries off.
@Suite struct ArchiveDateFormatterLocaleTests {
    private static let knownInstant: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 17, hour: 21, minute: 40)
        )!
    }()

    /// Hardcoded, not recomputed: the on-disk name for `knownInstant` must not track the formatter under test.
    private static let knownFilenameComponent = "2026-08-17T2140Z"

    private func unpinnedFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    @Test func archiveDateFormatterIsPinnedToPOSIX() {
        let formatter = UsageHistory.archiveDateFormatter
        #expect(formatter.locale.identifier == "en_US_POSIX")
        #expect(formatter.calendar.identifier == .gregorian)
        #expect(formatter.timeZone.secondsFromGMT() == 0)
    }

    @Test func archiveDateFormatterRoundTripsKnownInstantExactly() throws {
        let formatter = UsageHistory.archiveDateFormatter
        #expect(formatter.string(from: Self.knownInstant) == Self.knownFilenameComponent)

        let parsed = try #require(formatter.date(from: Self.knownFilenameComponent))
        #expect(parsed == Self.knownInstant)
    }

    @Test(arguments: ["th_TH", "ar_SA", "hi_IN", "ja_JP", "en_CA"])
    func archiveDateFormatterOutputIsIndependentOfAmbientLocale(localeID: String) {
        let hostile = unpinnedFormatter(locale: Locale(identifier: localeID))
        _ = hostile.string(from: Self.knownInstant)

        #expect(UsageHistory.archiveDateFormatter.string(from: Self.knownInstant)
                == Self.knownFilenameComponent)
    }

    /// `ar_SA` defaults to the Islamic calendar: the unpinned formatter writes `1448-03-04T2140Z` in ASCII
    /// digits, which the pinned parser reads back without error as Gregorian 1448.
    @Test(arguments: ["ar_SA", "th_TH", "ar_SA@numbers=arab", "fa_IR", "ja_JP@calendar=japanese"])
    func unpinnedFormatterEitherWritesUnparseableOrWildlyMisdatedNames(localeID: String) {
        let hostile = unpinnedFormatter(locale: Locale(identifier: localeID))
        let written = hostile.string(from: Self.knownInstant)

        guard written != Self.knownFilenameComponent else { return }

        // Unparseable names are invisible to retention forever; misdated ones are pruned as ancient.
        let reparsed = UsageHistory.archiveDateFormatter.date(from: written)
        #expect(reparsed != Self.knownInstant,
                "A hostile-locale name must never round-trip to the correct instant.")

        if let reparsed {
            let yearsApart = abs(reparsed.timeIntervalSince(Self.knownInstant)) / (365.25 * 24 * 3600)
            #expect(yearsApart > 100,
                    "The name parses without error but lands centuries away, so pruneArchives deletes a current archive.")
        }
    }

    /// `th_TH` defaults to the Buddhist calendar: the same digits parse without error, centuries early.
    @Test func unpinnedBuddhistCalendarParsesSameDigitsToAWildlyDifferentDate() throws {
        let buddhist = unpinnedFormatter(locale: Locale(identifier: "th_TH"))
        let misparsed = try #require(buddhist.date(from: Self.knownFilenameComponent))

        let correct = try #require(
            UsageHistory.archiveDateFormatter.date(from: Self.knownFilenameComponent)
        )

        #expect(misparsed != correct)

        let yearsApart = abs(misparsed.timeIntervalSince(correct)) / (365.25 * 24 * 3600)
        #expect(yearsApart > 500,
                "Buddhist year 2026 is Gregorian 1483 — the misparse is centuries, not minutes.")
        #expect(misparsed < correct)
    }
}
