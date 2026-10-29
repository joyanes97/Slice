//
//  EditorModel+DeviceImport.swift
//  Slice
//
//  Created by rit3zh CX on 10/29/26.
//

import Foundation
import SliceCore

extension EditorModel {
    /// A video taken in as a take. An iPhone's screen recording (the Simulator's, or the phone's own) goes into a
    /// device frame, so it shows in the flat mockup and on the 3D phone like a take recorded through Slice.
    func importTake(_ url: URL) async throws -> Clip {
        guard let size = try? await ClipImporter.videoSize(of: url), let phone = DeviceVideoImporter.phone(forVideo: size) else {
            return try await ClipImporter.importVideo(url, into: bundle)
        }
        deviceImportProgress = 0
        defer { deviceImportProgress = nil }
        let frame = await importFrame(for: phone)
        return try await DeviceVideoImporter.importVideo(url, into: bundle, phone: phone, frame: frame) { p in
            Task { @MainActor [weak self] in
                guard let self, self.deviceImportProgress != nil else { return }
                self.deviceImportProgress = p
            }
        }
    }

    /// A recording added from the 3D tab, shown on the device it's of (an iPhone's screen recording on the 3D iPhone,
    /// anything else on the Mac), with the playhead on it.
    func importOnto3D(_ url: URL) async {
        let before = Set(project.clips.map(\.id))
        await importClips([url])
        guard let i = project.clips.lastIndex(where: { !before.contains($0.id) }) else { return }
        let kind: Device3DKind = project.clips[i].device == nil ? .laptop : .phone
        if project.device3D.model.kind != kind { select3DModel(Device3DModel.models(kind)[0]) }
        project.device3D.enabled = true
        selection = nil
        seek(to: project.clipStarts[i])
    }

    /// The frame an imported phone recording goes in: none when the project's phone takes have none, else that
    /// iPhone's, in the colour the project's takes in it have (or the one last chosen for it).
    private func importFrame(for phone: DeviceModel) async -> DeviceFrameDefinition? {
        let taken = project.clips.compactMap(\.device)
        if let last = taken.last, last.frame == nil { return nil }
        let catalog = DeviceManager.shared.catalog
        guard let pick = catalog.frame(for: phone) else { return nil }
        let colors = catalog.colors(for: pick.model)
        let own = taken.last { $0.frame == pick.model }?.color.map { DeviceColor($0) }
        let chosen = UserDefaults.standard.string(forKey: "deviceFrame.color.\(pick.model)").map { DeviceColor($0) }
        guard let color = [own, chosen].compactMap({ $0 }).first(where: colors.contains) ?? colors.first else { return nil }
        return await Task.detached { try? catalog.definition(model: pick.model, color: color) }.value
    }
}
