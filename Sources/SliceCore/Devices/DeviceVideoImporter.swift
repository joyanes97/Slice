//
//  DeviceVideoImporter.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/29/26.
//

import AVFoundation
import CoreVideo
import Foundation
import VideoToolbox

/// Screen recordings made outside Slice (the Simulator's, an iPhone's own) taken in as device takes: the frame drawn
/// around every frame of the video just as recording a device does, so the flat mockup, the 3D phone and export treat
/// them like any take recorded through Slice.
public enum DeviceVideoImporter {
    public enum Failure: LocalizedError {
        case unreadable(String)
        case noFrame

        public var errorDescription: String? {
            switch self {
            case let .unreadable(name): "\(name) couldn't be read."
            case .noFrame: "The device frame couldn't be drawn."
            }
        }
    }

    /// How far a video's shape can be from a screen's and still be taken for it: iPhones save their own screen
    /// recordings a little smaller than the screen, rounded to even pixels.
    static let aspectTolerance: CGFloat = 0.012

    /// The iPhone a video is a screen recording of, going by its shape: its exact screen size, or else the newest
    /// iPhone whose screen has the same shape. Nil for anything else (a Mac recording, a camera video).
    public static func phone(forVideo size: CGSize) -> DeviceModel? {
        guard size.width > 0, size.height > 0 else { return nil }
        let portrait = CGSize(width: min(size.width, size.height), height: max(size.width, size.height))
        if let exact = DeviceRegistry.known.last(where: { $0.screenPixels == portrait }) { return exact }
        let aspect = portrait.width / portrait.height
        // A 16:9 iPhone SE screen is every portrait phone video's shape: it counts only at its exact size.
        let shaped = DeviceRegistry.known.filter { $0.pointScale > 2 }.map { m -> (DeviceModel, CGFloat) in
            (m, abs(log(m.screenPixels.width / m.screenPixels.height / aspect)))
        }
        guard let best = shaped.filter({ $0.1 < aspectTolerance }).min(by: { $0.1 < $1.1 })?.1 else { return nil }
        return shaped.last { abs($0.1 - best) < 1e-4 }?.0
    }

    /// Takes in `source` as a recording of `phone`: drawn in `frame`, or as it is without one.
    public static func importVideo(_ source: URL, into bundle: ProjectBundle, phone: DeviceModel, frame: DeviceFrameDefinition?,
                                   progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Clip {
        guard let frame, !frame.isFrameless else {
            var clip = try await ClipImporter.importVideo(source, into: bundle)
            clip.device = RecordedDevice(name: phone.name, identifier: phone.identifier, frame: nil, color: nil,
                                         screen: CGRect(x: 0, y: 0, width: 1, height: 1))
            return clip
        }
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipImporter.Failure.noVideo(source.lastPathComponent)
        }
        let duration = try await asset.load(.duration).seconds
        let size = try await ClipImporter.videoSize(of: source)
        guard let compositor = DeviceCompositor.shared, let textures = try? compositor.textures(for: frame) else { throw Failure.noFrame }
        let layout = DeviceLayout(frame: frame, streamSize: size)
        guard let renderer = DeviceSurfaceRenderer(compositor: compositor, size: layout.canvas) else { throw Failure.noFrame }

        let id = UUID()
        let (dir, rel) = try bundle.makeClipFolder(id: id)
        do {
            try await bake(asset, track: track, duration: duration, into: dir.appendingPathComponent("screen.mov"),
                           draw: { renderer.renderNow(screen: $0, frame: textures, layout: layout) }, size: renderer.size,
                           progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error is CancellationError ? error : Failure.unreadable(source.lastPathComponent)
        }
        var clip = Clip(id: id, screenFile: "\(rel)/screen.mov", micFile: nil, duration: duration, screenPixelSize: renderer.size,
                        captureRect: .zero)
            .withScreenAudio(try await ClipImporter.audio(of: asset, into: dir, relative: rel))
        clip.device = RecordedDevice(name: phone.name, identifier: phone.identifier, frame: frame.model, color: frame.color.rawValue,
                                     screen: layout.screenRect, cutout: layout.cutoutRect)
        return clip
    }

    /// Reads every frame of `track`, draws it, and writes the result with its see-through surround, at the times the
    /// frames had (a Simulator recording only has frames where the screen changed).
    private static func bake(_ asset: AVURLAsset, track: AVAssetTrack, duration: Double, into url: URL,
                             draw: @escaping (CVPixelBuffer) -> CVPixelBuffer?, size: CGSize,
                             progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader = try AVAssetReader(asset: asset)
        let pixels: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let output: AVAssetReaderOutput
        if try await track.load(.preferredTransform).isIdentity {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: pixels)
        } else {
            // Turned as it plays: read through a composition, which stands it the way it shows.
            let composed = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: pixels)
            composed.videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
            output = composed
        }
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let fps = try await track.load(.nominalFrameRate)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: 0.9,
                kVTCompressionPropertyKey_TargetQualityForAlpha as String: 0.9,
                AVVideoExpectedSourceFrameRateKey: fps > 0 ? Int(fps.rounded()) : 60,
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard reader.startReading(), writer.startWriting() else { throw reader.error ?? writer.error ?? Failure.noFrame }
        writer.startSession(atSourceTime: .zero)

        let pump = Pump(input: input, output: output, adaptor: adaptor, draw: draw)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "Slice.deviceImport")) {
                pump.run(duration: duration, progress: progress) { done.resume() }
            }
        }
        if pump.failed || reader.status == .failed {
            reader.cancelReading()
            writer.cancelWriting()
            throw reader.error ?? writer.error ?? Failure.noFrame
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.noFrame }
    }
}

/// Moves frames from the reader, through the frame, to the writer, on the writer's queue only.
private final class Pump: @unchecked Sendable {
    let input: AVAssetWriterInput
    let output: AVAssetReaderOutput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let draw: (CVPixelBuffer) -> CVPixelBuffer?
    private(set) var failed = false
    private var finished = false

    init(input: AVAssetWriterInput, output: AVAssetReaderOutput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
         draw: @escaping (CVPixelBuffer) -> CVPixelBuffer?) {
        self.input = input
        self.output = output
        self.adaptor = adaptor
        self.draw = draw
    }

    func run(duration: Double, progress: (Double) -> Void, done: () -> Void) {
        while !finished, input.isReadyForMoreMediaData {
            guard !failed, let sample = output.copyNextSampleBuffer() else {
                finished = true
                input.markAsFinished()
                done()
                return
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard let framed = draw(buffer), adaptor.append(framed, withPresentationTime: pts) else {
                failed = true
                continue
            }
            if duration > 0 { progress(min(max(pts.seconds / duration, 0), 1)) }
        }
    }
}
