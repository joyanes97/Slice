//
//  DeviceImportTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/29/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

final class DeviceImportTests: XCTestCase {
    func testPhoneRecordingsAreKnownByTheirShape() throws {
        XCTAssertEqual(DeviceVideoImporter.phone(forVideo: CGSize(width: 1320, height: 2868))?.name, "iPhone 17 Pro Max",
                       "a Simulator recording is the screen's exact size")
        XCTAssertEqual(DeviceVideoImporter.phone(forVideo: CGSize(width: 2868, height: 1320))?.name, "iPhone 17 Pro Max",
                       "on its side too")
        // An iPhone's own screen recording of a 6.7-inch screen is saved at 888 × 1920.
        let shrunk = try XCTUnwrap(DeviceVideoImporter.phone(forVideo: CGSize(width: 888, height: 1920)))
        XCTAssertEqual(shrunk.screenPixels.width / shrunk.screenPixels.height, 888.0 / 1920, accuracy: 0.006)
        XCTAssertEqual(DeviceVideoImporter.phone(forVideo: CGSize(width: 750, height: 1334))?.name, "iPhone SE (3rd generation)")
        XCTAssertNil(DeviceVideoImporter.phone(forVideo: CGSize(width: 1080, height: 1920)), "a 9:16 camera video isn't a phone screen")
        XCTAssertNil(DeviceVideoImporter.phone(forVideo: CGSize(width: 3024, height: 1964)), "nor is a Mac recording")
    }

    func testImportedRecordingIsFramedLikeARecordedTake() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("device-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, _) = try ProjectBundle.create(name: "Import", in: dir)
        let size = CGSize(width: 660, height: 1434)
        let source = dir.appendingPathComponent("Simulator Screen Recording.mov")
        try await ExportTests.makeMovie(url: source, image: Device3DTests.display(size), duration: 0.5)

        let phone = try XCTUnwrap(DeviceVideoImporter.phone(forVideo: size))
        let pick = try XCTUnwrap(DeviceTests.catalog.frame(for: phone))
        let frame = try XCTUnwrap(try DeviceTests.catalog.definition(model: pick.model, color: DeviceTests.catalog.colors(for: pick.model)[0]))
        let clip = try await DeviceVideoImporter.importVideo(source, into: bundle, phone: phone, frame: frame)

        let layout = DeviceLayout(frame: frame, streamSize: size)
        let device = try XCTUnwrap(clip.device)
        XCTAssertEqual(device.frame, frame.model)
        XCTAssertEqual(device.screen, layout.screenRect, "the 3D phone lifts the screen back out from here")
        XCTAssertEqual(device.cutout, layout.cutoutRect)
        XCTAssertEqual(clip.screenPixelSize.width, (layout.canvas.width / 2).rounded(.up) * 2)
        XCTAssertEqual(clip.duration, 0.5, accuracy: 0.05)

        let asset = AVURLAsset(url: bundle.url.appendingPathComponent(clip.screenFile))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        let (image, _) = try await generator.image(at: CMTime(value: 1, timescale: 10))
        let px = try XCTUnwrap(Self.pixels(image))
        let display = try XCTUnwrap(clip.deviceDisplayRect)
        // Core Image's bottom-left origin, as the display rect has it: green on top, magenta below.
        func at(_ x: CGFloat, _ y: CGFloat) -> SIMD4<Float> { px(Int(x), image.height - 1 - Int(y)) }
        let top = at(display.midX, display.midY + display.height * 0.3), bottom = at(display.midX, display.midY - display.height * 0.3)
        XCTAssertGreaterThan(top.y, 0.6, "the recording fills the frame's opening, upright")
        XCTAssertLessThan(top.x, 0.3)
        XCTAssertGreaterThan(bottom.x, 0.6)
        XCTAssertLessThan(bottom.y, 0.3)
        XCTAssertLessThan(at(2, 2).w, 0.05, "outside the frame stays see-through")
    }

    static func pixels(_ image: CGImage) -> ((Int, Int) -> SIMD4<Float>)? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return { x, y in
            let i = (min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)) * 4
            return SIMD4(Float(data[i]), Float(data[i + 1]), Float(data[i + 2]), Float(data[i + 3])) / 255
        }
    }
}
