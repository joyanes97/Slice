//
//  Device3DSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

/// The 3D tab: shows a recording on a 3D device, an iPhone take on a phone and a screen recording on a Mac. The
/// recording itself never changes, so it can be switched off again at any time.
struct Device3DSection: View {
    @ObservedObject var editor: EditorModel

    private var s: Device3DSettings { editor.project.device3D }

    var body: some View {
        Group {
            PanelSection("3D device", trailing: AnyView(header)) {
                if let warning { warning }
                if s.enabled { ModelPicker(editor: editor) } else { offState }
            }
            if s.enabled {
                PanelDivider()
                PanelSection("Pose", trailing: AnyView(resetPose)) {
                    PosePresets(editor: editor)
                    if s.model.kind == .laptop { LidControl(editor: editor) }
                    KeyframeBar(editor: editor)
                    MoreOptions("Fine-tune", id: "device3D.adjust") {
                        Device3DPoseFields(editor: editor)
                    }
                }
                PanelDivider()
                motion
                PanelDivider()
                look
                footer
            }
        }
        .animation(Theme.swap, value: s.enabled)
        .animation(Theme.swap, value: s.animation.motion)
        .animation(Theme.swap, value: s.background)
    }

    private func bind<T>(_ keyPath: WritableKeyPath<Device3DSettings, T>) -> Binding<T> {
        Binding(get: { editor.project.device3D[keyPath: keyPath] }, set: { editor.project.device3D[keyPath: keyPath] = $0 })
    }

    /// The device the switched-off tab shows: one for the takes there are.
    private var offPreview: Device3DModel {
        if editor.project.hasTakes(for: s.model.kind) { return s.model }
        return editor.available3DKinds.first.map { Device3DModel.models($0)[0] } ?? s.model
    }

    private var header: some View {
        HStack(spacing: 6) {
            if s.enabled {
                Button(action: addRecording) { Image(systemName: "plus") }
                    .buttonStyle(IconButtonStyle(size: 24, iconSize: 11))
                    .disabled(editor.deviceImportProgress != nil)
                    .help(Self.addHelp)
                    .transition(.opacity)
            }
            Toggle("3D device", isOn: Binding(get: { s.enabled }, set: { on in withAnimation(Theme.swap) { editor.enable3D(on) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
        }
    }

    private var offState: some View {
        let laptop = offPreview.kind == .laptop
        return VStack(spacing: 6) {
            Image(systemName: laptop ? "laptopcomputer" : "iphone")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("Off").font(.system(size: 13, weight: .medium))
            Text(laptop ? "Turn on to show this recording on a MacBook." : "Turn on to show this recording on an iPhone or Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a recording…", action: addRecording)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .disabled(editor.deviceImportProgress != nil)
                .help(Self.addHelp)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private static let addHelp = "Add a screen recording from your iPhone or Mac. An iPhone's is framed and goes on the 3D iPhone."

    private func addRecording() {
        guard let url = chooseVideos(message: "Choose a screen recording from your iPhone or Mac.", multiple: false)?.first else { return }
        Task { await editor.importOnto3D(url) }
    }

    private var warning: AnyView? {
        switch editor.device3DStatus {
        case let .failed(error):
            AnyView(Label {
                Text("\(error.localizedDescription) The recording is shown flat instead.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true))
        case .ready(hasDisplayMesh: false) where s.enabled:
            AnyView(PanelNote("This model has no screen of its own, so the recording is laid on the front of the device."))
        default:
            nil
        }
    }

    /// The models' licences ask that their makers are credited.
    private var footer: some View {
        HStack(spacing: 4) {
            Text("Model by")
            Link(s.model.credit.author, destination: s.model.credit.url)
            Text("·")
            Link(s.model.license.name, destination: s.model.license.url)
            Spacer(minLength: 8)
            Button("Reset all") {
                withAnimation(Theme.slide) {
                    var fresh = Device3DSettings()
                    fresh.enabled = true
                    fresh.model = s.model
                    fresh.finish = s.model.finishes[0]
                    fresh.placement = s.model.defaultPlacement
                    editor.removeAllKeyframes()
                    editor.project.device3D = fresh
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Put every 3D setting back as it started, and remove the keyframes")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .padding(.top, 4)
    }

    private var resetPose: some View {
        Button {
            withAnimation(Theme.slide) { editor.setPlacement(s.model.defaultPlacement) }
        } label: { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(IconButtonStyle(size: 24, iconSize: 11))
            .help("Put the device back in the middle, as it started")
    }

    // MARK: - Motion

    private var motion: some View {
        PanelSection("Motion") {
            SegmentedControl(selection: bind(\.animation.motion), options: Device3DMotion.allCases, title: \.label)
            if s.animation.motion != .none {
                PanelSlider("Duration", value: bind(\.animation.duration), in: Device3DAnimation.durationRange,
                            default: Device3DAnimation().duration) { String(format: "%.1fs", $0) }
                if s.animation.motion == .sway {
                    PanelSlider("Swing", value: bind(\.animation.swing), in: Device3DAnimation.swingRange,
                                default: Device3DAnimation().swing) { "\(Int($0.rounded()))°" }
                    MoreOptions(id: "device3D.motion") {
                        MotionPicker(easing: bind(\.animation.easing), curve: bind(\.animation.curve), duration: s.animation.duration,
                                     id: "device3D.swayMotion")
                        HStack {
                            Text("Starts towards").font(.system(size: 13))
                            Spacer()
                            SegmentedControl(selection: bind(\.animation.startSide), options: TiltDirection.allCases, title: \.label)
                                .frame(width: 140)
                        }
                        PanelSlider("Pause at each side", value: bind(\.animation.hold), in: 0 ... 0.8, default: Device3DAnimation().hold) {
                            $0 < 0.01 ? "None" : percent($0, of: 0 ... 1)
                        }
                    }
                } else {
                    PanelSlider("Amount", value: bind(\.animation.amount), in: 0 ... 1, default: Device3DAnimation().amount) {
                        percent($0, of: 0 ... 1)
                    }
                }
            }
        }
    }

    // MARK: - Look

    private var look: some View {
        PanelSection("Look") {
            HStack(spacing: 10) {
                SegmentedControl(selection: bind(\.background), options: Device3DBackground.allCases, title: \.label)
                if s.background != .frame {
                    ColorPicker("Background colour", selection: Binding(
                        get: { Color(.sRGB, red: s.backgroundColor.r, green: s.backgroundColor.g, blue: s.backgroundColor.b) },
                        set: { new in
                            guard let ns = NSColor(new).usingColorSpace(.sRGB) else { return }
                            editor.project.device3D.backgroundColor = RGBA(ns.redComponent, ns.greenComponent, ns.blueComponent)
                        }), supportsOpacity: false)
                        .labelsHidden()
                        .transition(.opacity)
                }
            }
            MoreOptions("Light and shadow", id: "device3D.look") {
                PanelSlider("Brightness", value: bind(\.brightness), in: 0.2 ... 2, default: 1) { "\(Int(($0 * 100).rounded()))%" }
                PanelSlider("Light from", value: bind(\.lightAngle), in: -1 ... 1, default: Device3DSettings().lightAngle) { side($0) }
                PanelSlider("Reflections", value: bind(\.reflections), in: 0 ... 1, default: Device3DSettings().reflections) {
                    percent($0, of: 0 ... 1)
                }
                PanelSlider("Shadow", value: bind(\.shadowOpacity), in: 0 ... 1, default: Device3DSettings().shadowOpacity) {
                    $0 < 0.01 ? "None" : percent($0, of: 0 ... 1)
                }
                PanelSlider("Shadow softness", value: bind(\.shadowSoftness), in: 0 ... 1, default: Device3DSettings().shadowSoftness) {
                    percent($0, of: 0 ... 1)
                }
                PanelSlider("Shadow distance", value: bind(\.shadowDistance), in: 0 ... 1, default: Device3DSettings().shadowDistance) {
                    percent($0, of: 0 ... 1)
                }
            }
        }
    }

    private func side(_ v: Double) -> String {
        if abs(v) < 0.05 { return "Front" }
        return "\(v < 0 ? "Left" : "Right") \(Int((abs(v) * 100).rounded()))%"
    }
}
