import AppKit
import SwiftUI
import ClimateCore

@MainActor final class ClimateStore: ObservableObject {
    @Published var readings: [ClimateReading] = []
    @Published var selectedID: String {
        didSet { if !isDemo { UserDefaults.standard.set(selectedID, forKey: "selectedSensor") } }
    }
    @Published var isRefreshing = false
    @Published var isConnecting = false
    @Published var hasToken = false
    @Published var error: String?
    @Published var lastSync: Date?
    @Published var partialWarning: String?
    @Published var now = Date()
    let isDemo: Bool
    private let api = YandexAPI()
    private var token: String?
    private var timer: Timer?
    private var generation = 0

    init(isDemo: Bool = false) {
        self.isDemo = isDemo
        self.selectedID = isDemo ? "demo-bedroom" : UserDefaults.standard.string(forKey: "selectedSensor") ?? ""
        if isDemo {
            let date = Date()
            readings = [
                ClimateReading(id: "demo-bedroom", name: "Датчик у кровати", room: "Спальня", online: true, temperature: Metric(value: 23.4, updated: date.addingTimeInterval(-180)), humidity: Metric(value: 42, updated: date.addingTimeInterval(-180))),
                ClimateReading(id: "demo-living", name: "Климат в гостиной", room: "Гостиная", online: true, temperature: Metric(value: 22.1, updated: date.addingTimeInterval(-420)), humidity: Metric(value: 46, updated: date.addingTimeInterval(-420))),
                ClimateReading(id: "demo-balcony", name: "Датчик на балконе", room: "Балкон", online: false, temperature: Metric(value: 8.5, updated: date.addingTimeInterval(-7200)), humidity: Metric(value: 61, updated: date.addingTimeInterval(-7200)))
            ]
            lastSync = date
        } else {
            do { token = try TokenKeychain.load(); hasToken = token != nil }
            catch { self.error = error.localizedDescription }
        }
    }

    var selected: ClimateReading? { selectedReading(in: readings, selectedID: selectedID) }
    var title: String {
        if isDemo {
            guard let selected else { return "ДЕМО · Климат" }
            return "ДЕМО · \(selected.temperature?.formatted(suffix: "°") ?? "—") · \(selected.humidity?.formatted(suffix: "%") ?? "—")"
        }
        if !hasToken { return "🌡 Подключить" }
        if let selected { return selected.menuTitle(at: now, connectionFailed: error != nil || partialWarning != nil) }
        if isRefreshing && lastSync == nil { return "🌡 Загрузка…" }
        return error != nil ? "🌡 Нет связи ⚠︎" : "🌡 Выбрать датчик"
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                await self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if hasToken { Task { await refresh() } }
    }

    private func fetch(token: String) async throws -> ([ClimateReading], String?) {
        let home = try await api.home(token: token)
        var result = home.climateReadings
        // user/info returns cached properties; query sensor details to obtain their online state.
        // Query one device at a time: completing concurrent child tasks has caused
        // crashes in the Swift concurrency runtime on some systems.
        let candidates = home.devices.filter { $0.isClimateCandidate }
        var failedIDs = Set<String>()
        for candidate in candidates {
            do {
                let device = try await api.device(id: candidate.id, token: token)
                let room = home.rooms?.first { $0.id == device.room }?.name ?? home.rooms?.first { $0.id == candidate.room }?.name ?? ""
                if let reading = device.climateReading(room: room, previous: result.first { $0.id == candidate.id }) {
                    result.removeAll { $0.id == candidate.id }
                    result.append(reading)
                }
            } catch {
                if let failure = error as? APIError, failure == .unauthorized || failure == .rateLimited { throw failure }
                failedIDs.insert(candidate.id)
            }
        }
        let warning = failedIDs.isEmpty ? nil : "Не все устройства ответили (\(failedIDs.count)). Часть значений — из последнего состояния в облаке."
        return (result.sorted { ($0.room + $0.name + $0.id).localizedStandardCompare($1.room + $1.name + $1.id) == .orderedAscending }, warning)
    }

    func refresh() async {
        guard !isDemo, let token, !isRefreshing, !isConnecting else { return }
        let requestGeneration = generation
        isRefreshing = true
        defer { if generation == requestGeneration { isRefreshing = false; now = Date() } }
        do {
            let (newReadings, warning) = try await fetch(token: token)
            guard generation == requestGeneration else { return }
            readings = newReadings
            partialWarning = warning
            error = nil
            lastSync = Date()
            if selectedID.isEmpty, let first = readings.first { selectedID = first.id }
        } catch {
            guard generation == requestGeneration else { return }
            self.error = Self.message(for: error)
        }
    }

    func connect(input: String) async -> String? {
        guard !isRefreshing, !isConnecting else { return "Дождитесь окончания текущего обновления." }
        guard let candidate = TokenInput.parse(input) else { return "Вставьте OAuth-токен или полный адрес страницы выдачи токена Яндекса." }
        isConnecting = true
        generation += 1
        let requestGeneration = generation
        defer { if generation == requestGeneration { isConnecting = false } }
        do {
            let (newReadings, warning) = try await fetch(token: candidate)
            guard generation == requestGeneration else { return "Подключение отменено." }
            try TokenKeychain.save(candidate)
            token = candidate
            hasToken = true
            error = nil
            partialWarning = warning
            readings = newReadings
            lastSync = Date()
            now = Date()
            if !readings.contains(where: { $0.id == selectedID }) { selectedID = readings.first?.id ?? "" }
            return nil
        } catch { return Self.message(for: error) }
    }

    func disconnect() -> String? {
        do { try TokenKeychain.delete() }
        catch { return error.localizedDescription }
        generation += 1
        token = nil
        hasToken = false
        isRefreshing = false
        isConnecting = false
        readings = []
        selectedID = ""
        lastSync = nil
        error = nil
        partialWarning = nil
        return nil
    }

    private static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut:
                return "Нет связи с Яндексом. Проверьте интернет; повторим через минуту. Показаны последние полученные данные."
            default: return "Не удалось связаться с Яндексом. Повторим через минуту."
            }
        }
        return error.localizedDescription
    }
}
