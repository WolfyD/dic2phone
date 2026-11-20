import XCTest
@testable import Dic2Phone

final class TapeMetaTests: XCTestCase {
    private static var full: TapeMeta {
        var meta = TapeMeta()
        meta.title = "Standup"
        meta.notes = "Who does what"
        meta.tags = ["work", "daily"]
        meta.startedAtMs = 1_795_000_000_000
        meta.endedAtMs = 1_795_000_060_000
        meta.durationMs = 60_000
        meta.sizeBytes = 720_000
        meta.format = TapeFormat.label
        meta.peakDb = -3.5
        meta.averageDb = -21.25
        meta.source = "rec-key"
        meta.device = "iPhone"
        meta.latched = true
        meta.vox = true
        meta.cuts = 2
        meta.skippedMs = 4_000
        meta.part = 1
        meta.flags = [1_000, 30_000]
        meta.flagNotes = [30_000: "the decision"]
        meta.location = LocationFix(latitude: 47.5, longitude: 19.04, accuracyM: 12)
        meta.place = "Budapest, HU"
        return meta
    }

    func testAnEmptyMetaWritesOnlyItsVersion() throws {
        let json = try Self.jsonObject(TapeMeta())
        XCTAssertEqual(json.keys.sorted(), ["v"])
        XCTAssertEqual(json["v"] as? Int, 1)
    }

    func testWritesTheAndroidAppsKeys() throws {
        let keys = try Self.jsonObject(Self.full).keys.sorted()
        XCTAssertEqual(keys, [
            "acc", "avg", "cuts", "device", "dur", "end", "flagNotes", "flags", "format", "lat", "latched",
            "lon", "notes", "part", "peak", "place", "size", "skipped", "source", "start", "tags", "title",
            "v", "vox",
        ])
    }

    func testReadsBackWhatItWrote() throws {
        let data = try JSONEncoder().encode(Self.full)
        XCTAssertEqual(try JSONDecoder().decode(TapeMeta.self, from: data), Self.full)
    }

    func testReadsFlagsInOrder() throws {
        let meta = try Self.decode(#"{"v":1,"flags":[30000,1000,5000]}"#)
        XCTAssertEqual(meta.flags, [1_000, 5_000, 30_000])
    }

    func testSkipsUnknownKeysAndFlagNotesWithoutATime() throws {
        let meta = try Self.decode(#"{"v":2,"title":"Hi","later":true,"flags":[1000],"flagNotes":{"1000":"kept","soon":"dropped"}}"#)
        XCTAssertEqual(meta.title, "Hi")
        XCTAssertEqual(meta.flagNotes, [1_000: "kept"])
    }

    func testRejectsAFieldOfTheWrongType() {
        XCTAssertThrowsError(try Self.decode(#"{"v":1,"title":5}"#))
    }

    func testDropsNotesOfRemovedOrBlankFlags() throws {
        var meta = TapeMeta()
        meta.flags = [1_000]
        meta.flagNotes = [1_000: "  ", 2_000: "orphan"]
        XCTAssertNil(try Self.jsonObject(meta)["flagNotes"])
    }

    func testDropsCoordinatesThatAreNowhereOnEarth() throws {
        let meta = try Self.decode(#"{"v":1,"lat":91.5,"lon":19.04,"place":"Budapest"}"#)
        XCTAssertNil(meta.location)
        XCTAssertEqual(meta.place, "Budapest")
    }

    func testKeepsAPlaceWithoutAccuracy() throws {
        let meta = try Self.decode(#"{"v":1,"lat":-33.86,"lon":151.2,"acc":-1}"#)
        XCTAssertEqual(meta.location, LocationFix(latitude: -33.86, longitude: 151.2, accuracyM: nil))
    }

    private static func jsonObject(_ meta: TapeMeta) throws -> [String: Any] {
        let data = try JSONEncoder().encode(meta)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func decode(_ json: String) throws -> TapeMeta {
        try JSONDecoder().decode(TapeMeta.self, from: Data(json.utf8))
    }
}
