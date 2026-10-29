//
//  ScrubField.swift
//  Slice
//
//  Created by rit3zh CX on 10/29/26.
//

import SwiftUI

/// A number changed by dragging across it, as in Keynote's inspector, or typed in after a click.
struct ScrubField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// How far the value moves for each point dragged.
    let step: Double
    let format: (Double) -> String
    /// The number typed as a value: a percentage typed as 50 is 0.5.
    let parse: (Double) -> Double

    @State private var hovering = false
    @State private var start: Double?
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         parse: @escaping (Double) -> Double = { $0 }, format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.parse = parse
        self.format = format
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        VStack(spacing: 5) {
            ZStack {
                if editing {
                    TextField(title, text: $text)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { editing = false }
                        .onChange(of: focused) { _, on in if !on { commit() } }
                } else {
                    Text(format(value))
                        .contentTransition(.numericText(value: value))
                        .animation(.snappy(duration: 0.2), value: format(value))
                }
            }
            .font(.rounded(12).monospacedDigit())
            .foregroundStyle(start != nil || editing ? Color.primary : Color.primary.opacity(0.85))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(shape.fill(start != nil || editing || hovering ? Theme.controlHover : Theme.control))
            .overlay(shape.strokeBorder(editing ? Theme.accent.opacity(0.9) : Theme.stroke, lineWidth: editing ? 1.5 : 1))
            .contentShape(shape)
            .pointerStyle(editing ? .default : .columnResize)
            .onTapGesture { beginEditing() }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    if start == nil { start = value }
                    value = min(max((start ?? value) + g.translation.width * step, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in start = nil })
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: editing)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let nudge = (range.upperBound - range.lowerBound) / 40
            switch direction {
            case .increment: value = min(value + nudge, range.upperBound)
            case .decrement: value = max(value - nudge, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func beginEditing() {
        text = format(value).filter { "-0123456789.".contains($0) }
        editing = true
        focused = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        guard let typed = Double(text.filter { "-0123456789.".contains($0) }) else { return }
        withAnimation(Theme.slide) { value = min(max(parse(typed), range.lowerBound), range.upperBound) }
    }
}
