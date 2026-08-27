import AppKit
import Combine
import ImageIO
import OSLog

/// A short-lived lease for the decoded full-screen background shared by all
/// overlay windows. The image is released after the last overlay using it goes
/// away, instead of remaining in CoreUI's process-wide named-image cache.
final class RestBackgroundImageLease: ObservableObject, @unchecked Sendable {
    @Published private(set) var image: CGImage?

    private let releaseHandler: @Sendable () -> Void

    init(image: CGImage?, releaseHandler: @escaping @Sendable () -> Void) {
        self.image = image
        self.releaseHandler = releaseHandler
    }

    @MainActor
    fileprivate func receive(_ image: CGImage) {
        self.image = image
    }

    deinit {
        releaseHandler()
    }
}

final class RestBackgroundImageLoader: @unchecked Sendable {
    typealias Decoder = @Sendable (ReminderTheme, Int, Bundle) -> CGImage?

    static let shared = RestBackgroundImageLoader()

    private static let logger = Logger(
        subsystem: "com.local.EyeProtection",
        category: "RestBackgroundImageLoader"
    )
    private static let sourceSize = CGSize(width: 1536, height: 960)
    private static let maximumSourcePixelDimension = 3072
    private static let sharedDecodeQueue = DispatchQueue(
        label: "com.local.EyeProtection.rest-background-decode",
        qos: .userInitiated,
        attributes: .concurrent,
        autoreleaseFrequency: .workItem
    )

    private struct CacheKey: Hashable, Sendable {
        let theme: ReminderTheme
        let maximumPixelDimension: Int
    }

    private struct CacheEntry {
        let id: UUID
        var image: CGImage?
        var leaseIDs: Set<UUID>
        var deliveries: [UUID: @Sendable (CGImage) -> Void]
        var operation: DecodeOperation?
    }

    private final class DecodeOperation: @unchecked Sendable {
        let id = UUID()

        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.performWhileLocked { cancelled }
        }

        func cancel() {
            lock.performWhileLocked {
                cancelled = true
            }
        }
    }

    private let bundle: Bundle
    private let decodeQueue: DispatchQueue
    private let decoder: Decoder
    private let lock = NSLock()
    private var cachedTheme: ReminderTheme?
    private var entries: [CacheKey: CacheEntry] = [:]

    init(
        bundle: Bundle = Bundle(for: RestBackgroundBundleToken.self),
        decodeQueue: DispatchQueue = RestBackgroundImageLoader.sharedDecodeQueue,
        decoder: @escaping Decoder = { theme, maximumPixelDimension, bundle in
            RestBackgroundImageLoader.decode(
                theme: theme,
                maximumPixelDimension: maximumPixelDimension,
                bundle: bundle
            )
        }
    ) {
        self.bundle = bundle
        self.decodeQueue = decodeQueue
        self.decoder = decoder
    }

    @MainActor
    static func recommendedMaximumPixelDimension(
        screens: [NSScreen] = NSScreen.screens
    ) -> Int {
        let requiredDimension = screens.map { screen -> CGFloat in
            let pixelWidth = screen.frame.width * screen.backingScaleFactor
            let pixelHeight = screen.frame.height * screen.backingScaleFactor
            return max(
                pixelWidth,
                pixelHeight * (sourceSize.width / sourceSize.height)
            )
        }.max() ?? CGFloat(maximumSourcePixelDimension)

        return min(
            maximumSourcePixelDimension,
            max(1, Int(ceil(requiredDimension)))
        )
    }

    /// Returns immediately. PNG file access and decoding always happen on the
    /// dedicated background queue, while the resulting image is published on
    /// the main actor for SwiftUI.
    @MainActor
    func lease(
        for theme: ReminderTheme,
        maximumPixelDimension: Int
    ) -> RestBackgroundImageLease {
        let normalizedDimension = min(
            Self.maximumSourcePixelDimension,
            max(1, maximumPixelDimension)
        )
        let key = CacheKey(
            theme: theme,
            maximumPixelDimension: normalizedDimension
        )
        let leaseID = UUID()
        var resolvedEntryID: UUID?
        var cachedImage: CGImage?
        var operationToStart: DecodeOperation?
        var operationsToCancel: [DecodeOperation] = []

        lock.performWhileLocked {
            if cachedTheme != theme {
                // Existing leases continue to own the outgoing image during a
                // window fade. Pending outgoing decodes are discarded.
                operationsToCancel = entries.values.compactMap(\.operation)
                entries.removeAll()
                cachedTheme = theme
            }

            if var entry = entries[key] {
                entry.leaseIDs.insert(leaseID)
                resolvedEntryID = entry.id
                cachedImage = entry.image
                entries[key] = entry
            } else {
                let operation = DecodeOperation()
                let entry = CacheEntry(
                    id: UUID(),
                    image: nil,
                    leaseIDs: [leaseID],
                    deliveries: [:],
                    operation: operation
                )
                resolvedEntryID = entry.id
                entries[key] = entry
                operationToStart = operation
            }
        }
        operationsToCancel.forEach { $0.cancel() }
        let entryID = resolvedEntryID!

        let lease = RestBackgroundImageLease(image: cachedImage) { [weak self] in
            self?.release(key: key, entryID: entryID, leaseID: leaseID)
        }

        if cachedImage == nil {
            let delivery: @Sendable (CGImage) -> Void = { [weak self, weak lease] image in
                DispatchQueue.main.async {
                    guard self?.shouldDeliver(
                        image,
                        key: key,
                        entryID: entryID,
                        leaseID: leaseID
                    ) == true else {
                        return
                    }
                    lease?.receive(image)
                }
            }

            if let completedImage = registerDelivery(
                delivery,
                key: key,
                entryID: entryID,
                leaseID: leaseID
            ) {
                lease.receive(completedImage)
            }
        }

        if let operationToStart {
            startDecode(
                operationToStart,
                key: key,
                entryID: entryID,
                maximumPixelDimension: normalizedDimension
            )
        }

        return lease
    }

    static func resourceURL(
        for theme: ReminderTheme,
        pixelScale: Int,
        bundle: Bundle = Bundle(for: RestBackgroundBundleToken.self)
    ) -> URL? {
        let resourceName = "\(theme.backgroundAssetName)-\(pixelScale)x"
        return bundle.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "RestBackgrounds"
        ) ?? bundle.url(forResource: resourceName, withExtension: "png")
    }

    static func decode(
        theme: ReminderTheme,
        maximumPixelDimension: Int,
        bundle: Bundle = Bundle(for: RestBackgroundBundleToken.self)
    ) -> CGImage? {
        let normalizedDimension = min(
            maximumSourcePixelDimension,
            max(1, maximumPixelDimension)
        )
        let pixelScale = normalizedDimension <= Int(sourceSize.width) ? 1 : 2
        guard let url = resourceURL(
            for: theme,
            pixelScale: pixelScale,
            bundle: bundle
        ) else {
            return nil
        }

        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: normalizedDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    var cachedEntryCountForTesting: Int {
        lock.performWhileLocked { entries.count }
    }

    var cachedThemeForTesting: ReminderTheme? {
        lock.performWhileLocked { cachedTheme }
    }

    var pendingDecodeCountForTesting: Int {
        lock.performWhileLocked {
            entries.values.filter { $0.operation != nil }.count
        }
    }

    private func registerDelivery(
        _ delivery: @escaping @Sendable (CGImage) -> Void,
        key: CacheKey,
        entryID: UUID,
        leaseID: UUID
    ) -> CGImage? {
        lock.performWhileLocked {
            guard
                var entry = entries[key],
                entry.id == entryID,
                entry.leaseIDs.contains(leaseID)
            else {
                return nil
            }
            if let image = entry.image {
                return image
            }
            entry.deliveries[leaseID] = delivery
            entries[key] = entry
            return nil
        }
    }

    private func shouldDeliver(
        _ image: CGImage,
        key: CacheKey,
        entryID: UUID,
        leaseID: UUID
    ) -> Bool {
        lock.performWhileLocked {
            guard
                cachedTheme == key.theme,
                let entry = entries[key],
                entry.id == entryID,
                entry.leaseIDs.contains(leaseID),
                entry.image === image
            else {
                return false
            }
            return true
        }
    }

    private func startDecode(
        _ operation: DecodeOperation,
        key: CacheKey,
        entryID: UUID,
        maximumPixelDimension: Int
    ) {
        let bundle = bundle
        let decoder = decoder
        decodeQueue.async { [weak self] in
            guard !operation.isCancelled else { return }
            let image = decoder(key.theme, maximumPixelDimension, bundle)
            guard !operation.isCancelled else { return }
            self?.finishDecode(
                image,
                operation: operation,
                key: key,
                entryID: entryID
            )
        }
    }

    private func finishDecode(
        _ image: CGImage?,
        operation: DecodeOperation,
        key: CacheKey,
        entryID: UUID
    ) {
        var deliveries: [@Sendable (CGImage) -> Void] = []
        var acceptedImage: CGImage?

        lock.performWhileLocked {
            guard
                !operation.isCancelled,
                cachedTheme == key.theme,
                var entry = entries[key],
                entry.id == entryID,
                entry.operation?.id == operation.id
            else {
                return
            }

            entry.operation = nil
            if let image {
                entry.image = image
                acceptedImage = image
                deliveries = Array(entry.deliveries.values)
                entry.deliveries.removeAll()
            }
            entries[key] = entry
        }

        if let acceptedImage {
            deliveries.forEach { $0(acceptedImage) }
        } else if !operation.isCancelled {
            Self.logger.error(
                "Unable to load rest background for \(key.theme.rawValue, privacy: .public)"
            )
        }
    }

    private func release(key: CacheKey, entryID: UUID, leaseID: UUID) {
        var operationToCancel: DecodeOperation?

        lock.performWhileLocked {
            guard var entry = entries[key], entry.id == entryID else { return }
            entry.leaseIDs.remove(leaseID)
            entry.deliveries.removeValue(forKey: leaseID)
            if !entry.leaseIDs.isEmpty {
                entries[key] = entry
            } else {
                operationToCancel = entry.operation
                entries.removeValue(forKey: key)
                if entries.isEmpty {
                    cachedTheme = nil
                }
            }
        }
        operationToCancel?.cancel()
    }
}

final class RestBackgroundBundleToken {}

private extension NSLock {
    func performWhileLocked<T>(_ action: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try action()
    }
}
