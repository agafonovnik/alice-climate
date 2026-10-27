import Foundation

public enum APIError: Error, LocalizedError, Equatable {
    case unauthorized, rateLimited, server, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Яндекс отклонил токен. Проверьте доступ iot:view или получите новый токен в настройках."
        case .rateLimited: return "Яндекс ограничил частоту запросов. Следующая попытка — через минуту."
        case .server: return "Сервис Яндекса временно недоступен. Повторим через минуту."
        case .invalidResponse: return "Не удалось прочитать ответ Яндекса. Попробуйте обновить данные позже."
        }
    }
}

public struct YandexAPI {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config)
    }
    public static func checkHTTP(statusCode: Int) throws {
        switch statusCode {
        case 200..<300: return
        case 401, 403: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        case 500...599: throw APIError.server
        default: throw APIError.invalidResponse
        }
    }
    private func request<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: "https://api.iot.yandex.net/v1.0/" + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        try Self.checkHTTP(statusCode: http.statusCode)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }
    public func home(token: String) async throws -> HomeResponse {
        let home: HomeResponse = try await request("user/info", token: token)
        guard home.status == "ok" else { throw APIError.invalidResponse }
        return home
    }
    public func device(id: String, token: String) async throws -> Device {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { throw APIError.invalidResponse }
        return try await request("devices/" + encoded, token: token)
    }
}
