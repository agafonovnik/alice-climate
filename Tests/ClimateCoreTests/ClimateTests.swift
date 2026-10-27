import Foundation
import Darwin
import ClimateCore

final class ClimateTests {
    func testMixedPropertiesPreserveZeroNegativeAndIgnoreEvents() throws {
        let json = #"{"status":"ok","rooms":[{"id":"r","name":"Спальня"}],"devices":[{"id":"s","name":"Датчик","type":"devices.types.sensor.climate","state":"online","room":"r","properties":[{"type":"devices.properties.float","state":{"instance":"temperature","value":-2.5},"last_updated":1000},{"type":"devices.properties.float","state":{"instance":"humidity","value":0},"last_updated":900},{"type":"devices.properties.event","state":{"instance":"open","value":"opened"}},{"type":"devices.properties.float","state":null}]}]}"#
        let home = try JSONDecoder().decode(HomeResponse.self, from: Data(json.utf8))
        let readings = home.climateReadings
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings[0].temperature?.value, -2.5)
        XCTAssertEqual(readings[0].humidity?.value, 0)
        XCTAssertEqual(readings[0].room, "Спальня")
        XCTAssertEqual(readings[0].oldestMeasurement, Date(timeIntervalSince1970: 900))
    }

    func testMissingAndOutOfRangeValuesAreNotFabricated() throws {
        let json = #"{"status":"ok","devices":[{"id":"s","name":"Sensor","properties":[{"state":{"instance":"temperature","value":null}},{"state":{"instance":"humidity","value":110}},{"state":{"instance":"temperature","value":"23"}}]},{"id":"lamp","name":"Lamp","properties":[]}]}"#
        let home = try JSONDecoder().decode(HomeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(home.climateReadings.count, 1)
        XCTAssertNil(home.climateReadings[0].temperature)
        XCTAssertNil(home.climateReadings[0].humidity)
        XCTAssertEqual(home.climateReadings[0].menuTitle(at: Date()), "🌡 — · 💧 —")
    }

    func testStaleAndOfflineMenuCannotLookLive() {
        let metric = Metric(value: 23.4, updated: Date(timeIntervalSince1970: 1000))
        let live = ClimateReading(id: "s", name: "Датчик", room: "", online: true, temperature: metric, humidity: nil)
        XCTAssertEqual(live.menuTitle(at: Date(timeIntervalSince1970: 1100)), "🌡 23,4° · 💧 —")
        XCTAssertTrue(live.menuTitle(at: Date(timeIntervalSince1970: 5000)).hasPrefix("≈ "))
        var offline = live
        offline.online = false
        XCTAssertEqual(offline.menuTitle(at: Date()), "🌡 — · 💧 — ⚠︎")
        XCTAssertTrue(live.menuTitle(at: Date(timeIntervalSince1970: 1100), connectionFailed: true).hasSuffix(" ⚠︎"))
    }

    func testSelectionUsesIDAndNeverSilentlySwitchesMissingSensor() {
        let a = ClimateReading(id: "a", name: "A", room: "", online: true, temperature: nil, humidity: nil)
        let b = ClimateReading(id: "b", name: "B", room: "", online: true, temperature: nil, humidity: nil)
        XCTAssertEqual(selectedReading(in: [b,a], selectedID: "a")?.id, "a")
        XCTAssertNil(selectedReading(in: [b], selectedID: "a"))
        XCTAssertEqual(selectedReading(in: [b,a], selectedID: "")?.id, "b")
    }

    func testTokenInputAcceptsRawBearerOrRedirectAndRejectsGarbage() {
        XCTAssertEqual(TokenInput.parse("  abc_123-XYZ  "), "abc_123-XYZ")
        XCTAssertEqual(TokenInput.parse("Bearer abc_123-XYZ"), "abc_123-XYZ")
        XCTAssertEqual(TokenInput.parse("https://oauth.yandex.ru/verification_code#access_token=abc_123-XYZ&expires_in=100"), "abc_123-XYZ")
        XCTAssertNil(TokenInput.parse(""))
        XCTAssertNil(TokenInput.parse("not a token"))
        XCTAssertNil(TokenInput.parse("https://example.com/#access_token=secret"))
    }

    func testHTTPErrorsAreActionableAndDoNotExposeResponseBody() {
        for (code, expected) in [(401, APIError.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .server)] {
            do {
                try YandexAPI.checkHTTP(statusCode: code)
                failures += 1
                print("FAIL: HTTP \(code) was accepted")
            } catch let error as APIError {
                XCTAssertEqual(error, expected)
                XCTAssertTrue(!error.localizedDescription.isEmpty)
            } catch { failures += 1 }
        }
        do { try YandexAPI.checkHTTP(statusCode: 200) } catch { failures += 1 }
    }

    func testOfflineDetailWithNoPropertiesCannotLeaveCachedReadingOnline() throws {
        let cached = ClimateReading(id: "s", name: "Датчик", room: "Спальня", online: true, temperature: Metric(value: 23, updated: Date()), humidity: nil)
        let device = try JSONDecoder().decode(Device.self, from: Data(#"{"id":"s","name":"Датчик","state":"offline","properties":[]}"#.utf8))
        let refreshed = device.climateReading(room: "Спальня", previous: cached)
        XCTAssertEqual(refreshed?.online, false)
        XCTAssertEqual(refreshed?.menuTitle(at: Date()), "🌡 — · 💧 — ⚠︎")
        XCTAssertNil(refreshed?.temperature)
    }

    func testSingleInstanceExcludesOtherProcessesAndRecoversAfterExit() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("climate-lock-test-" + UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var first: SingleInstanceGate? = try SingleInstanceGate(path: path)
        XCTAssertEqual(first?.isPrimary, true)
        try first?.markReady()
        let second = try SingleInstanceGate(path: path)
        XCTAssertEqual(second.isPrimary, false)
        XCTAssertEqual(second.ownerIsReady, true)
        XCTAssertEqual(second.ownerPID, ProcessInfo.processInfo.processIdentifier)
        var children: [Process] = []
        for _ in 0..<5 {
            let child = Process()
            var pathSize: UInt32 = 0
            _NSGetExecutablePath(nil, &pathSize)
            var executablePath = [CChar](repeating: 0, count: Int(pathSize))
            guard _NSGetExecutablePath(&executablePath, &pathSize) == 0 else { throw POSIXError(.ENOENT) }
            child.executableURL = URL(fileURLWithPath: String(cString: executablePath))
            child.arguments = ["--probe-lock", path]
            child.standardOutput = FileHandle.nullDevice
            try child.run()
            children.append(child)
        }
        for child in children { child.waitUntilExit(); XCTAssertEqual(child.terminationStatus, 17) }
        first = nil
        let afterExit = try SingleInstanceGate(path: path)
        XCTAssertEqual(afterExit.isPrimary, true)
        XCTAssertEqual(afterExit.ownerIsReady, false)
    }

    func testSingleInstanceRefusesSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("climate-link-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        try Data("unchanged".utf8).write(to: target)
        let link = root.appendingPathComponent("lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do { _ = try SingleInstanceGate(path: link.path); failures += 1; print("FAIL: lock followed a symbolic link") }
        catch { XCTAssertEqual(try String(contentsOf: target), "unchanged") }
    }

    func testUnknownTimestampIsExplicit() {
        let item = ClimateReading(id: "s", name: "Датчик", room: "", online: true, temperature: Metric(value: 0, updated: nil), humidity: nil)
        XCTAssertEqual(item.measurementDescription(at: Date()), "Время измерения неизвестно")
        XCTAssertTrue(item.menuTitle(at: Date()).hasPrefix("≈ "))
    }
}

var failures = 0
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #fileID, line: Int = #line) {
    if a != b { failures += 1; print("FAIL \(file):\(line): \(a) != \(b)") }
}
func XCTAssertTrue(_ value: Bool, file: String = #fileID, line: Int = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line): expected true") }
}
func XCTAssertNil<T>(_ value: T?, file: String = #fileID, line: Int = #line) {
    if value != nil { failures += 1; print("FAIL \(file):\(line): expected nil") }
}
@main struct TestRunner {
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--probe-lock" {
            let gate = try SingleInstanceGate(path: CommandLine.arguments[2])
            exit(gate.isPrimary ? 0 : 17)
        }
        let tests = ClimateTests()
        try tests.testMixedPropertiesPreserveZeroNegativeAndIgnoreEvents()
        try tests.testMissingAndOutOfRangeValuesAreNotFabricated()
        tests.testStaleAndOfflineMenuCannotLookLive()
        tests.testSelectionUsesIDAndNeverSilentlySwitchesMissingSensor()
        tests.testTokenInputAcceptsRawBearerOrRedirectAndRejectsGarbage()
        tests.testUnknownTimestampIsExplicit()
        try tests.testOfflineDetailWithNoPropertiesCannotLeaveCachedReadingOnline()
        tests.testHTTPErrorsAreActionableAndDoNotExposeResponseBody()
        try tests.testSingleInstanceExcludesOtherProcessesAndRecoversAfterExit()
        try tests.testSingleInstanceRefusesSymlink()
        print("10 tests, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
