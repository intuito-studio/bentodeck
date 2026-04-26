import Foundation

/// Fetches snapshots from the BentoDeck backend. Used by the app target
/// (via RefreshManager) and by the widget extension's timeline provider.
struct APIClient {
    let baseURL: URL

    init(baseURL: URL = Config.baseURL) { self.baseURL = baseURL }

    func fetchDashboards() async throws -> [DashboardSummary] {
        let url = baseURL.appendingPathComponent("dashboards")
        let data = try await fetch(url: url)
        let decoded = try JSONDecoder().decode(DashboardListResponse.self, from: data)
        return decoded.dashboards
    }

    func fetchSnapshot(dashboardId: String) async throws -> SnapshotResponse {
        let url = baseURL.appendingPathComponent("dashboards/\(dashboardId)/snapshot")
        let data = try await fetch(url: url)
        return try JSONDecoder().decode(SnapshotResponse.self, from: data)
    }

    func fetchInvestigation(id: String) async throws -> Investigation {
        let url = baseURL.appendingPathComponent("investigations/\(id)")
        let data = try await fetch(url: url)
        return try JSONDecoder().decode(InvestigationResponse.self, from: data).investigation
    }

    func fetchInvestigations(widgetId: String) async throws -> [Investigation] {
        let url = baseURL.appendingPathComponent("widgets/\(widgetId)/investigations")
        let data = try await fetch(url: url)
        return try JSONDecoder().decode(InvestigationListResponse.self, from: data).investigations
    }

    /// Submit an API key for a data source the user discovered without auth.
    /// Returns the parsed result: `.ok` on a successful verify, `.failed`
    /// when the backend's verification call returned a non-2xx (the source
    /// stays in needsKey state so the user can retry).
    func setDataSourceKey(sourceId: String, apiKey: String) async throws -> SetKeyResult {
        let url = baseURL.appendingPathComponent("data-sources/\(sourceId)/key")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpBody = try JSONEncoder().encode(["apiKey": apiKey])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(SetKeyResponse.self, from: data)
        if decoded.ok {
            return .ok
        }
        return .failed(status: decoded.status ?? 0, bodyPreview: decoded.bodyPreview)
    }

    private func fetch(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

struct Investigation: Codable, Identifiable, Hashable {
    let id: String
    let widgetId: String
    let snapshotId: Int?
    let sessionId: String?
    let status: String          // pending | running | done | failed
    let title: String?
    let report: String?
    let error: String?
    let createdAt: String
    let completedAt: String?

    var isTerminal: Bool { status == "done" || status == "failed" }
}

struct InvestigationResponse: Codable {
    let investigation: Investigation
}

struct InvestigationListResponse: Codable {
    let investigations: [Investigation]
}

enum APIError: LocalizedError {
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case let .http(status): return "Backend returned HTTP \(status)"
        }
    }
}

/// Result of POST /data-sources/:id/key. The backend always returns 200
/// when the source exists; the `ok` body field tells us whether the key
/// passed verification.
enum SetKeyResult: Equatable {
    case ok
    case failed(status: Int, bodyPreview: String?)
}

private struct SetKeyResponse: Codable {
    let ok: Bool
    let status: Int?
    let bodyPreview: String?
}
