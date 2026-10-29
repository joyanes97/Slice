//
//  PoseSpring.swift
//  Slice
//
//  Created by rit3zh CX on 10/29/26.
//

import Foundation
import SliceCore

/// Eases the preview's 3D device towards the pose it's given, so turning, moving and resizing it glide at the display's
/// rate instead of stepping with each mouse event. Critically damped, so it never swings past the pose.
struct PoseSpring {
    private var value: [Double] = []
    private var velocity: [Double] = []
    private let omega = 2 * Double.pi / 0.2

    /// Yaw, pitch, rotation, position, scale (in ratio) and lid, each with how close counts as there.
    private static func values(_ p: Device3DPlacement) -> [Double] {
        [p.yaw, p.pitch, p.rotation, p.position.x, p.position.y, Foundation.log(max(p.scale, 1e-3)), p.lid]
    }

    private static let tolerance = [0.005, 0.005, 0.005, 1e-5, 1e-5, 1e-5, 0.005]
    private static let angles = 0 ..< 3

    /// The pose to draw, and whether it's still on its way to `target`.
    mutating func step(toward target: Device3DPlacement?, snap: Bool, dt: Double) -> (Device3DPlacement?, Bool) {
        guard let target else {
            value = []
            velocity = []
            return (nil, false)
        }
        var goal = Self.values(target)
        guard !snap, value.count == goal.count else {
            value = goal
            velocity = goal.map { _ in 0 }
            return (target, false)
        }
        // Angles wrap at ±180°: the spring heads for the nearest turn of the goal, the short way round.
        for i in Self.angles {
            var d = (goal[i] - value[i]).truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 } else if d < -180 { d += 360 }
            goal[i] = value[i] + d
        }
        let n = max(Int((dt * 480).rounded(.up)), 1), h = dt / Double(n)
        var moving = false
        for i in value.indices {
            for _ in 0 ..< n {
                velocity[i] += (-omega * omega * (value[i] - goal[i]) - 2 * omega * velocity[i]) * h
                value[i] += velocity[i] * h
            }
            if abs(value[i] - goal[i]) < Self.tolerance[i], abs(velocity[i]) < Self.tolerance[i] * 10 {
                value[i] = goal[i]
                velocity[i] = 0
            } else {
                moving = true
            }
        }
        guard moving else {
            value = Self.values(target)
            return (target, false)
        }
        return (Device3DPlacement(yaw: value[0], pitch: value[1], rotation: value[2], position: CGPoint(x: value[3], y: value[4]),
                                  scale: exp(value[5]), lid: value[6]), true)
    }
}
