import Core
import Energy
import Foundation
import Testing

@testable import Tally

private func complete() -> UserSettings {
    var settings = UserSettings()
    settings.heightCm = 175
    settings.weightKg = 70
    settings.ageYears = 30
    settings.sex = .male
    return settings
}

@Suite struct SettingsTests {
    @Test func aNewSettingsHasNoProfileTheLightFactorThirtyCallsAndChinese() {
        let settings = UserSettings()
        #expect(settings.profile == nil)
        #expect(settings.activity == .light)
        #expect(settings.dailyCallLimit == 30)
        #expect(settings.language == .chinese)
    }

    @Test func theLanguagesAreChineseAndEnglishWithTheirLocales() {
        #expect(Language.allCases == [.chinese, .english])
        #expect(Language.chinese.locale.identifier == "zh-Hans")
        #expect(Language.english.locale.identifier == "en")
    }

    @Test func fourValuesMakeTheProfileOfTheEnergyTestVector() throws {
        let profile = try #require(complete().profile)
        #expect(try Energy.expenditure(profile) == 2555.5625)
    }

    @Test func theProfileFollowsTheActivityChoice() throws {
        var settings = complete()
        settings.activity = .heavy
        #expect(try #require(settings.profile).activity == .heavy)
    }

    @Test(arguments: ["height", "weight"])
    func aMissingOrZeroNumberLeavesNoProfile(field: String) {
        func profile(_ value: Double?) -> Profile? {
            var settings = complete()
            if field == "height" { settings.heightCm = value } else { settings.weightKg = value }
            return settings.profile
        }
        #expect(profile(nil) == nil)
        #expect(profile(0) == nil)
    }

    @Test func aMissingAgeOrSexLeavesNoProfile() {
        var noAge = complete()
        noAge.ageYears = nil
        var zeroAge = complete()
        zeroAge.ageYears = 0
        var noSex = complete()
        noSex.sex = nil
        #expect(noAge.profile == nil && zeroAge.profile == nil && noSex.profile == nil)
    }

    @Test func theFileRoundTripsWithEveryField() throws {
        var settings = complete()
        settings.activity = .atHome
        settings.dailyCallLimit = 12
        settings.language = .english
        #expect(try UserSettings(decoding: settings.encoded()) == settings)
    }

    @Test func anEmptySettingsRoundTripsToo() throws {
        #expect(try UserSettings(decoding: UserSettings().encoded()) == UserSettings())
    }

    @Test func theFileHoldsTheVersionAndTheSettings() throws {
        let text = String(decoding: try UserSettings().encoded(), as: UTF8.self)
        #expect(text == #"{"settings":{"activity":"light","dailyCallLimit":30,"language":"zh-Hans"},"version":1}"#)
    }

    @Test(arguments: [0, 101, -3])
    func aLimitOutOfRangeIsRefusedWhenWritingAndWhenReading(limit: Int) {
        var settings = UserSettings()
        settings.dailyCallLimit = limit
        let written = #expect(throws: FormatError.self) { try settings.encoded() }
        #expect(written?.what == "the daily call limit is out of range")
        #expect(written?.saw == "\(limit)")
        let file = Data(#"{"settings":{"activity":"light","dailyCallLimit":\#(limit),"language":"en"},"version":1}"#.utf8)
        let read = #expect(throws: FormatError.self) { try UserSettings(decoding: file) }
        #expect(read?.expected == "1 to 100")
    }

    @Test func theBoundsOfTheLimitAreAccepted() throws {
        for limit in [1, 100] {
            var settings = UserSettings()
            settings.dailyCallLimit = limit
            #expect(try UserSettings(decoding: settings.encoded()).dailyCallLimit == limit)
        }
    }

    @Test func anotherVersionIsRefused() {
        let error = #expect(throws: FormatError.self) {
            try UserSettings(decoding: Data(#"{"settings":{},"version":2}"#.utf8))
        }
        #expect(error?.what == "the file has another version")
    }
}
