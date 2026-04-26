import UIKit

/// In-memory cache of decoded dashboard background images, keyed by
/// `dashboardId`. Decoding a JPEG into a `UIImage` is expensive enough that
/// doing it on every layout pass during a carousel swipe creates visible
/// frame drops — this cache turns it into a one-time cost per image.
///
/// The cache invalidates by the file's modification date, so picking a new
/// photo busts the entry without manual invalidation calls.
final class BackgroundImageCache {
    static let shared = BackgroundImageCache()

    private let cache = NSCache<NSString, Entry>()
    private let queue = DispatchQueue(label: "BackgroundImageCache", attributes: .concurrent)

    private init() {
        cache.countLimit = 32
    }

    /// Returns the decoded image for the dashboard, decoding (and caching)
    /// only when there's no fresh cached copy. Reads file mtime cheaply via
    /// `URLResourceValues` to decide whether the cache is current.
    func image(forDashboardId dashboardId: String) -> UIImage? {
        let key = dashboardId as NSString
        let mtime = currentModificationDate(forDashboardId: dashboardId)

        if let entry = queue.sync(execute: { cache.object(forKey: key) }),
           entry.modificationDate == mtime {
            return entry.image
        }

        guard let data = SharedStore.shared.loadBackgroundImageData(dashboardId: dashboardId),
              let image = UIImage(data: data) else {
            queue.async(flags: .barrier) { [cache] in
                cache.removeObject(forKey: key)
            }
            return nil
        }

        let entry = Entry(image: image, modificationDate: mtime)
        queue.async(flags: .barrier) { [cache] in
            cache.setObject(entry, forKey: key)
        }
        return image
    }

    /// Force-evict a single entry. Called after the user picks a new photo
    /// or clears the background, so the next read decodes from disk.
    func invalidate(dashboardId: String) {
        let key = dashboardId as NSString
        queue.async(flags: .barrier) { [cache] in
            cache.removeObject(forKey: key)
        }
    }

    private func currentModificationDate(forDashboardId dashboardId: String) -> Date? {
        guard let url = imageURL(dashboardId: dashboardId) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    private func imageURL(dashboardId: String) -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Config.appGroupID
        ) else {
            return nil
        }
        return container
            .appendingPathComponent("backgrounds", isDirectory: true)
            .appendingPathComponent("\(dashboardId).jpg")
    }

    private final class Entry {
        let image: UIImage
        let modificationDate: Date?
        init(image: UIImage, modificationDate: Date?) {
            self.image = image
            self.modificationDate = modificationDate
        }
    }
}
