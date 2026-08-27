import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import EyeProtection

@MainActor
final class RestBackgroundImageLoaderTests: XCTestCase {
    func testEveryThemeHasRawOneAndTwoScaleBackgrounds() throws {
        for theme in ReminderTheme.allCases {
            for (scale, expectedSize) in [
                (1, CGSize(width: 1536, height: 960)),
                (2, CGSize(width: 3072, height: 1920)),
            ] {
                let url = try XCTUnwrap(RestBackgroundImageLoader.resourceURL(
                    for: theme,
                    pixelScale: scale
                ))
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(
                    url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                ))
                let properties = try XCTUnwrap(
                    CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                        as? [CFString: Any]
                )
                XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, Int(expectedSize.width))
                XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, Int(expectedSize.height))
            }
        }
    }

    func testDefaultDecoderDownsamplesWithoutChangingAspectRatio() async throws {
        let loader = RestBackgroundImageLoader()
        var lease: RestBackgroundImageLease? = loader.lease(
            for: .quietHorizon,
            maximumPixelDimension: 1200
        )

        let image = try await waitForImage(try XCTUnwrap(lease))
        XCTAssertEqual(image.width, 1200)
        XCTAssertEqual(Double(image.width) / Double(image.height), 1.6, accuracy: 0.002)

        lease = nil
        XCTAssertEqual(loader.cachedEntryCountForTesting, 0)
        XCTAssertNil(loader.cachedThemeForTesting)
    }

    func testLeaseReturnsImmediatelyAndDecoderRunsOffMainThread() async throws {
        let image = try makeImage()
        let gate = DispatchSemaphore(value: 0)
        let probe = DecodeProbe()
        let loader = RestBackgroundImageLoader(
            decodeQueue: DispatchQueue(
                label: "RestBackgroundImageLoaderTests.off-main",
                qos: .userInitiated
            )
        ) { theme, _, _ in
            probe.recordStart(theme: theme, isMainThread: Thread.isMainThread)
            gate.wait()
            probe.recordFinish(theme: theme)
            return image
        }
        defer { gate.signal() }

        let lease = loader.lease(for: .quietHorizon, maximumPixelDimension: 1200)

        XCTAssertNil(lease.image)
        try await waitUntil { probe.startCount(for: .quietHorizon) == 1 }
        XCTAssertFalse(probe.hasMainThreadInvocation)
        XCTAssertNil(lease.image)

        gate.signal()
        let decoded = try await waitForImage(lease)
        XCTAssertTrue(decoded === image)
    }

    func testConcurrentSameThemeLeasesUseOneDecodeAndShareImage() async throws {
        let image = try makeImage()
        let gate = DispatchSemaphore(value: 0)
        let probe = DecodeProbe()
        let loader = RestBackgroundImageLoader(
            decodeQueue: DispatchQueue(
                label: "RestBackgroundImageLoaderTests.single-flight",
                qos: .userInitiated,
                attributes: .concurrent
            )
        ) { theme, _, _ in
            probe.recordStart(theme: theme, isMainThread: Thread.isMainThread)
            gate.wait()
            probe.recordFinish(theme: theme)
            return image
        }
        defer { gate.signal() }

        var leases = await withTaskGroup(
            of: RestBackgroundImageLease.self,
            returning: [RestBackgroundImageLease].self
        ) { group in
            for _ in 0..<6 {
                group.addTask {
                    await MainActor.run {
                        loader.lease(for: .quietHorizon, maximumPixelDimension: 1200)
                    }
                }
            }

            var result: [RestBackgroundImageLease] = []
            for await lease in group {
                result.append(lease)
            }
            return result
        }

        try await waitUntil { probe.startCount(for: .quietHorizon) == 1 }
        XCTAssertEqual(loader.cachedEntryCountForTesting, 1)
        XCTAssertEqual(loader.pendingDecodeCountForTesting, 1)
        XCTAssertTrue(leases.allSatisfy { $0.image == nil })

        gate.signal()
        try await waitUntil { leases.allSatisfy { $0.image != nil } }

        XCTAssertEqual(probe.startCount(for: .quietHorizon), 1)
        XCTAssertFalse(probe.hasMainThreadInvocation)
        let firstImage = try XCTUnwrap(leases.first?.image)
        XCTAssertTrue(leases.allSatisfy { $0.image === firstImage })
        XCTAssertEqual(loader.pendingDecodeCountForTesting, 0)

        leases.removeAll()
        XCTAssertEqual(loader.cachedEntryCountForTesting, 0)
        XCTAssertNil(loader.cachedThemeForTesting)
    }

    func testChangingThemeCancelsOutgoingDeliveryAndKeepsOnlyCurrentTheme() async throws {
        let outgoingImage = try makeImage(width: 16, height: 10)
        let incomingImage = try makeImage(width: 32, height: 20)
        let outgoingGate = DispatchSemaphore(value: 0)
        let probe = DecodeProbe()
        let loader = RestBackgroundImageLoader(
            decodeQueue: DispatchQueue(
                label: "RestBackgroundImageLoaderTests.theme-cancellation",
                qos: .userInitiated,
                attributes: .concurrent
            )
        ) { theme, _, _ in
            probe.recordStart(theme: theme, isMainThread: Thread.isMainThread)
            if theme == .quietHorizon {
                outgoingGate.wait()
                probe.recordFinish(theme: theme)
                return outgoingImage
            }
            probe.recordFinish(theme: theme)
            return incomingImage
        }
        defer { outgoingGate.signal() }

        var outgoing: RestBackgroundImageLease? = loader.lease(
            for: .quietHorizon,
            maximumPixelDimension: 1200
        )
        try await waitUntil { probe.startCount(for: .quietHorizon) == 1 }

        var incoming: RestBackgroundImageLease? = loader.lease(
            for: .forestLight,
            maximumPixelDimension: 1200
        )
        let deliveredIncoming = try await waitForImage(try XCTUnwrap(incoming))

        XCTAssertTrue(deliveredIncoming === incomingImage)
        XCTAssertNil(outgoing?.image)
        XCTAssertEqual(loader.cachedThemeForTesting, .forestLight)
        XCTAssertEqual(loader.cachedEntryCountForTesting, 1)

        outgoingGate.signal()
        try await waitUntil { probe.finishCount(for: .quietHorizon) == 1 }
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertNil(outgoing?.image)
        XCTAssertEqual(loader.cachedThemeForTesting, .forestLight)
        XCTAssertEqual(loader.cachedEntryCountForTesting, 1)

        outgoing = nil
        XCTAssertEqual(loader.cachedThemeForTesting, .forestLight)
        incoming = nil
        XCTAssertNil(loader.cachedThemeForTesting)
        XCTAssertEqual(loader.cachedEntryCountForTesting, 0)
    }

    func testReleasingLastLeaseCancelsPendingDecodeAndClearsCache() async throws {
        let image = try makeImage()
        let gate = DispatchSemaphore(value: 0)
        let probe = DecodeProbe()
        let loader = RestBackgroundImageLoader(
            decodeQueue: DispatchQueue(
                label: "RestBackgroundImageLoaderTests.lease-cancellation",
                qos: .userInitiated
            )
        ) { theme, _, _ in
            probe.recordStart(theme: theme, isMainThread: Thread.isMainThread)
            gate.wait()
            probe.recordFinish(theme: theme)
            return image
        }
        defer { gate.signal() }

        var lease: RestBackgroundImageLease? = loader.lease(
            for: .quietHorizon,
            maximumPixelDimension: 1200
        )
        try await waitUntil { probe.startCount(for: .quietHorizon) == 1 }
        XCTAssertEqual(loader.pendingDecodeCountForTesting, 1)

        lease = nil
        XCTAssertEqual(loader.pendingDecodeCountForTesting, 0)
        XCTAssertEqual(loader.cachedEntryCountForTesting, 0)
        XCTAssertNil(loader.cachedThemeForTesting)

        gate.signal()
        try await waitUntil { probe.finishCount(for: .quietHorizon) == 1 }
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(loader.cachedEntryCountForTesting, 0)
        XCTAssertNil(loader.cachedThemeForTesting)
        XCTAssertNil(lease)
    }

    private func waitForImage(
        _ lease: RestBackgroundImageLease,
        timeout: TimeInterval = 3
    ) async throws -> CGImage {
        try await waitUntil(timeout: timeout) { lease.image != nil }
        return try XCTUnwrap(lease.image)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                throw WaitError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeImage(width: Int = 16, height: Int = 10) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}

private enum WaitError: Error {
    case timedOut
}

private final class DecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [ReminderTheme: Int] = [:]
    private var finishes: [ReminderTheme: Int] = [:]
    private var mainThreadInvocation = false

    var hasMainThreadInvocation: Bool {
        lock.withLock { mainThreadInvocation }
    }

    func startCount(for theme: ReminderTheme) -> Int {
        lock.withLock { starts[theme, default: 0] }
    }

    func finishCount(for theme: ReminderTheme) -> Int {
        lock.withLock { finishes[theme, default: 0] }
    }

    func recordStart(theme: ReminderTheme, isMainThread: Bool) {
        lock.withLock {
            starts[theme, default: 0] += 1
            mainThreadInvocation = mainThreadInvocation || isMainThread
        }
    }

    func recordFinish(theme: ReminderTheme) {
        lock.withLock {
            finishes[theme, default: 0] += 1
        }
    }
}
