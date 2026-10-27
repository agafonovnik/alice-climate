import Foundation

public struct Metric: Equatable, Sendable {
    public let value: Double
    public let updated: Date?
    public init(value: Double, updated: Date?) { self.value = value; self.updated = updated }

    public func formatted(suffix: String) -> String {
        let number = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        let compact = number.hasSuffix(".0") ? String(number.dropLast(2)) : number
        return compact.replacingOccurrences(of: ".", with: ",") + suffix
    }

    public func ageDescription(at now: Date) -> String {
        guard let updated, updated <= now.addingTimeInterval(300) else { return "время неизвестно" }
        let seconds = max(0, Int(now.timeIntervalSince(updated)))
        if seconds < 60 { return "только что" }
        if seconds < 3600 { return "\(seconds / 60) мин назад" }
        if seconds < 86400 { return "\(seconds / 3600) ч назад" }
        return "\(seconds / 86400) дн назад"
    }
}

public struct ClimateReading: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let room: String
    public var online: Bool
    public let temperature: Metric?
    public let humidity: Metric?
    public init(id: String, name: String, room: String, online: Bool, temperature: Metric?, humidity: Metric?) {
        self.id = id; self.name = name; self.room = room; self.online = online
        self.temperature = temperature; self.humidity = humidity
    }
    public var oldestMeasurement: Date? {
        [temperature?.updated, humidity?.updated].compactMap { $0 }.min()
    }
    public func isOld(at now: Date) -> Bool {
        let metrics = [temperature, humidity].compactMap { $0 }
        return metrics.contains { metric in
            guard let updated = metric.updated else { return true }
            return now.timeIntervalSince(updated) > 1800 || updated > now.addingTimeInterval(300)
        }
    }
    public func menuTitle(at now: Date, connectionFailed: Bool = false) -> String {
        guard online else { return "🌡 — · 💧 — ⚠︎" }
        let prefix = isOld(at: now) ? "≈ " : ""
        return prefix + "🌡 \(temperature?.formatted(suffix: "°") ?? "—") · 💧 \(humidity?.formatted(suffix: "%") ?? "—")" + (connectionFailed ? " ⚠︎" : "")
    }
    public func measurementDescription(at now: Date) -> String {
        guard let oldestMeasurement else { return "Время измерения неизвестно" }
        return "Измерено: " + Metric(value: 0, updated: oldestMeasurement).ageDescription(at: now)
    }
}

public func selectedReading(in readings: [ClimateReading], selectedID: String) -> ClimateReading? {
    selectedID.isEmpty ? readings.first : readings.first { $0.id == selectedID }
}

public struct HomeResponse: Decodable, Sendable {
    public let status: String
    public let rooms: [Room]?
    public let devices: [Device]
    public var climateReadings: [ClimateReading] {
        devices.compactMap { device in
            device.climateReading(room: rooms?.first { $0.id == device.room }?.name ?? "")
        }.sorted {
            let left = $0.room + $0.name + $0.id
            let right = $1.room + $1.name + $1.id
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}
public struct Room: Decodable, Sendable {
    public let id: String
    public let name: String
}
public struct Device: Decodable, Sendable {
    public let id: String
    public let name: String
    public let type: String?
    public let room: String?
    public let state: String?
    public let properties: [Property]?
    public var isClimateCandidate: Bool {
        (type?.hasPrefix("devices.types.sensor") ?? false) || (properties ?? []).contains { $0.isClimate }
    }
    public func climateReading(room: String, previous: ClimateReading? = nil) -> ClimateReading? {
        guard (properties ?? []).contains(where: { $0.isClimate }) || previous != nil else { return nil }
        func metric(_ instance: String) -> Metric? {
            let property = properties?.first { $0.instance == instance && $0.state?.value != nil }
            guard let value = property?.state?.value, value.isFinite else { return nil }
            if instance == "humidity" && !(0...100).contains(value) { return nil }
            let updated = property?.last_updated.flatMap { $0 > 0 && $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
            return Metric(value: value, updated: updated)
        }
        return ClimateReading(id: id, name: name, room: room, online: state != "offline", temperature: metric("temperature"), humidity: metric("humidity"))
    }
}
public struct Property: Decodable, Sendable {
    public let type: String?
    public let state: PropertyState?
    public let parameters: PropertyParameters?
    public let last_updated: Double?
    public var instance: String? { state?.instance ?? parameters?.instance }
    public var isClimate: Bool { instance == "temperature" || instance == "humidity" }
}
public struct PropertyParameters: Decodable, Sendable { public let instance: String? }
public struct PropertyState: Decodable, Sendable {
    public let instance: String?
    public let value: Double?
    enum CodingKeys: String, CodingKey { case instance, value }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instance = try container.decodeIfPresent(String.self, forKey: .instance)
        // Event properties contain strings; they are valid API data, not numeric readings.
        value = try? container.decode(Double.self, forKey: .value)
    }
}

public enum TokenInput {
    public static func parse(_ input: String) -> String? {
        var token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") { token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
        if token.contains("://") {
            guard let url = URLComponents(string: token), url.scheme == "https",
                  ["oauth.yandex.ru", "oauth.yandex.com"].contains(url.host ?? ""),
                  url.path == "/verification_code", let fragment = url.fragment,
                  let parameters = URLComponents(string: "https://local/?" + fragment),
                  let found = parameters.queryItems?.first(where: { $0.name == "access_token" })?.value
            else { return nil }
            token = found
        }
        let permitted = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        guard !token.isEmpty, token.unicodeScalars.allSatisfy({ permitted.contains($0) }) else { return nil }
        return token
    }
}
