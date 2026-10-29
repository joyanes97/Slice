//
//  Device3DPoseControls.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

struct PosePresets: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var clock: PlaybackClock

    init(editor: EditorModel) {
        self.editor = editor
        clock = editor.clock
    }

    static func presets(_ kind: Device3DKind) -> [(name: String, placement: Device3DPlacement)] {
        kind == .laptop ? laptopPresets : phonePresets
    }

    static let laptopPresets: [(name: String, placement: Device3DPlacement)] = [
        ("Front", Device3DPlacement(yaw: 0, pitch: -12)),
        ("Turned", Device3DPlacement(yaw: -16, pitch: -14)),
        ("Angled", Device3DPlacement(yaw: 28, pitch: -20)),
        ("Side", Device3DPlacement(yaw: 70, pitch: -6)),
        ("Above", Device3DPlacement(yaw: 0, pitch: -46)),
        ("Low", Device3DPlacement(yaw: -14, pitch: 4)),
    ]

    static let phonePresets: [(name: String, placement: Device3DPlacement)] = [
        ("Front", Device3DPlacement(yaw: 0, pitch: 0)),
        ("Turned", Device3DPlacement(yaw: 24, pitch: 4)),
        ("Tilted", Device3DPlacement(yaw: -24, pitch: 12, rotation: 6)),
        ("Side", Device3DPlacement(yaw: 68, pitch: 2)),
        ("Lean back", Device3DPlacement(yaw: 0, pitch: 38)),
        ("Flat", Device3DPlacement(yaw: -10, pitch: 62, rotation: -16)),
    ]

    var body: some View {
        let presets = Self.presets(editor.project.device3D.model.kind)
        let current = editor.editedPlacement
        let chosen = presets.first { p in
            abs(current.yaw - p.placement.yaw) < 0.5 && abs(current.pitch - p.placement.pitch) < 0.5
                && abs(current.rotation - p.placement.rotation) < 0.5
        }
        HStack {
            Text("Angle").font(.system(size: 13))
            Spacer()
            Menu {
                ForEach(presets, id: \.name) { preset in
                    Toggle(preset.name, isOn: Binding(get: { chosen?.name == preset.name }, set: { _ in apply(preset.placement) }))
                }
            } label: {
                HStack(spacing: 5) {
                    Text(chosen?.name ?? "Custom").lineLimit(1).contentTransition(.opacity)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.control))
                .contentShape(Rectangle())
                .animation(Theme.hover, value: chosen?.name)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Turns the device to a ready-made angle, keeping its place and size")
        }
    }

    private func apply(_ placement: Device3DPlacement) {
        withAnimation(Theme.slide) {
            editor.updatePlacement {
                $0.yaw = placement.yaw
                $0.pitch = placement.pitch
                $0.rotation = placement.rotation
            }
        }
    }
}

struct LidControl: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var clock: PlaybackClock
    
    let animates: Bool

    init(editor: EditorModel, animates: Bool = true) {
        self.editor = editor
        self.animates = animates
        clock = editor.clock
    }

    var body: some View {
        PanelSlider("Lid", value: Binding(get: { editor.editedPlacement.lid }, set: { v in editor.updatePlacement { $0.lid = v } }),
                    in: Device3DSettings.lidRange, default: Device3DPlacement.openLid) { $0 < 0.5 ? "Closed" : "\(Int($0.rounded()))°" }
            .help("How far the lid stands open, from closed to leaning back")
        if animates {
            HStack(spacing: 6) {
                Text("Animate the lid").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Open") { withAnimation(Theme.hover) { editor.animateLid(open: true) } }
                    .help("Keys the lid opening from the playhead, over \(String(format: "%.1f", EditorModel.lidMove)) seconds")
                Button("Close") { withAnimation(Theme.hover) { editor.animateLid(open: false) } }
                    .help("Keys the lid closing from the playhead, over \(String(format: "%.1f", EditorModel.lidMove)) seconds")
            }
            .buttonStyle(SmallButtonStyle())
        }
    }
}

/// Whether the device is animated by keyframes, and the way to start or add to them.
struct KeyframeBar: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let keys = editor.project.device3D.keyframes
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyframes").font(.system(size: 13))
                Text(summary(keys))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(Theme.hover) { editor.addKeyframe(at: editor.time) }
            } label: {
                Label("Add", systemImage: "plus").labelStyle(.titleAndIcon)
            }
            .buttonStyle(SmallButtonStyle())
            .help("Add a keyframe at the playhead, with the device's pose there. Two or more move it from pose to pose.")
        }
        .animation(Theme.swap, value: keys.count)
    }

    private func summary(_ keys: [Device3DKeyframe]) -> String {
        switch keys.count {
        case 0: "None, one pose throughout"
        case 1: "1, add another to move"
        default: "\(keys.count) on the 3D track"
        }
    }
}

/// The exact pose, for the selected keyframe, the keyframe at the playhead, or the device's one pose.
struct Device3DPoseFields: View {
    @ObservedObject var editor: EditorModel
    /// Keyframed, the pose changes along the timeline: follow the playhead.
    @ObservedObject private var clock: PlaybackClock

    init(editor: EditorModel) {
        self.editor = editor
        clock = editor.clock
    }

    var body: some View {
        group("Rotation") {
            ScrubField("Turn", value: bind(\.yaw), in: -180 ... 180, step: 0.5, format: degrees)
                .help("Turns the device left or right. Drag across, or click to type.")
            ScrubField("Tilt", value: bind(\.pitch), in: -180 ... 180, step: 0.5, format: degrees)
                .help("Tips the device's top away from you or towards you. Drag across, or click to type.")
            ScrubField("Spin", value: bind(\.rotation), in: -180 ... 180, step: 0.5, format: degrees)
                .help("Spins the device in the picture. Drag across, or click to type.")
        }
        group("Position") {
            ScrubField("Across", value: position(\.x), in: Device3DSettings.positionRange, step: 0.004, parse: { $0 / 100 },
                       format: offset)
            ScrubField("Up", value: position(\.y), in: Device3DSettings.positionRange, step: 0.004, parse: { $0 / 100 },
                       format: offset)
            ScrubField("Size", value: bind(\.scale), in: Device3DSettings.scaleRange, step: 0.005, parse: { $0 / 100 }) {
                "\(Int(($0 * 100).rounded()))%"
            }
        }
        PanelSlider("Perspective", value: Binding(get: { editor.project.device3D.perspective },
                                                  set: { editor.project.device3D.perspective = $0 }),
                    in: 0 ... 1, default: Device3DSettings().perspective) { $0 < 0.05 ? "Flat" : percent($0, of: 0 ... 1) }
            .help("Low is a long lens, nearly flat; high is a wide one, with strong depth")
    }

    private func group(_ title: String, @ViewBuilder fields: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13))
            HStack(spacing: 6) { fields() }
        }
    }

    private func bind(_ keyPath: WritableKeyPath<Device3DPlacement, Double>) -> Binding<Double> {
        Binding(get: { editor.editedPlacement[keyPath: keyPath] }, set: { v in editor.updatePlacement { $0[keyPath: keyPath] = v } })
    }

    private func position(_ keyPath: WritableKeyPath<CGPoint, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(editor.editedPlacement.position[keyPath: keyPath]) },
                set: { v in editor.updatePlacement { $0.position[keyPath: keyPath] = v } })
    }

    private func degrees(_ v: Double) -> String { "\(Int(v.rounded()))°" }

    private func offset(_ v: Double) -> String { abs(v) < 0.005 ? "0%" : String(format: "%+d%%", Int((v * 100).rounded())) }
}

struct KeyframeInspector: View {
    @ObservedObject var editor: EditorModel
    let key: Device3DKeyframe

    private var previous: Device3DKeyframe? {
        editor.project.device3D.keyframes.filter { $0.time < key.time - 1e-6 }.max { $0.time < $1.time }
    }

    private var lead: Double { previous.map { max(key.time - $0.time, 0.1) } ?? 1 }

    var body: some View {
        InfoRow(title: "Time", value: CutPin.label(key.time, precise: true))
        PanelSection("Pose") {
            PosePresets(editor: editor)
            if editor.project.device3D.model.kind == .laptop { LidControl(editor: editor, animates: false) }
            Device3DPoseFields(editor: editor)
        }
        PanelDivider()
        PanelSection("Move into it") {
            MotionPicker(easing: Binding(get: { key.easing }, set: { e in editor.updateKeyframe(key.id) { $0.easing = e } }),
                         curve: Binding(get: { key.curve }, set: { c in editor.updateKeyframe(key.id) { $0.curve = c } }),
                         duration: lead, id: "device3D.keyframeMotion")
            PanelNote(previous == nil
                ? "This is the first keyframe: the device holds its pose until here."
                : "How the device moves from the keyframe before to this one, over \(String(format: "%.1fs", lead)).")
        }
        Button("Delete keyframe") { editor.deleteSelection() }
            .buttonStyle(DestructiveButtonStyle())
    }
}
