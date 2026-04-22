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
