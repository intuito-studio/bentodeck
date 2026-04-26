import Foundation

/// Runtime configuration shared between the app target and the widget extension.
///
/// The backend URL is read from the BENTODECK_BASE_URL Info.plist key when
/// present (handy for demo rigs), otherwise it falls back to the hardcoded
/// default. For iPhone simulator pointing at your Mac, `http://localhost:3737`
/// works; for a physical iPhone on the same Wi-Fi, replace localhost with your
/// Mac's LAN IP (e.g. `http://192.168.1.42:3737`) and re-build.
enum Config {
    static let appGroupID = "group.com.intuitostudio.bentodeck"
    static let refreshTaskID = "com.intuitostudio.bentodeck.refresh"

    static let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "BENTODECK_BASE_URL") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3737")!
    }()
}

/// URL scheme used by widgets and Live Activities to deep-link into the
/// app. The host names the destination, query parameters carry the IDs.
///
/// Examples:
///   bentodeck://dashboard?id=<dashboardId>
///   bentodeck://investigation?id=<investigationId>&widgetTitle=<title>
enum BentoDeckLink {
    static let scheme = "bentodeck"

    static func dashboard(id: String) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "dashboard"
        c.queryItems = [URLQueryItem(name: "id", value: id)]
        return c.url!
    }

    static func investigation(id: String, widgetTitle: String) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "investigation"
        c.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "widgetTitle", value: widgetTitle),
        ]
        return c.url!
    }

    /// Parse an incoming deep link into a typed destination. Returns nil
    /// for malformed URLs or unknown hosts.
    static func parse(_ url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }
        let queryItems =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
        let dict = Dictionary(
            uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
                guard let v = item.value else { return nil }
                return (item.name, v)
            }
        )

        switch url.host {
        case "dashboard":
            guard let id = dict["id"] else { return nil }
            return .dashboard(id: id)
        case "investigation":
            guard let id = dict["id"] else { return nil }
            return .investigation(id: id, widgetTitle: dict["widgetTitle"] ?? "Widget")
        default:
            return nil
        }
    }

    enum Destination: Hashable {
        case dashboard(id: String)
        case investigation(id: String, widgetTitle: String)
    }
}
