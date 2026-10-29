//
//  Device3DTemplate+Island.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/29/26.
//

import SceneKit
import simd

extension Device3DTemplate {
    /// The Dynamic Island's parts are in their own category, so each copy of the phone can find and hide them.
    static let islandCategory = 4
    static let islandPatchName = "Slice island patch"

    /// Readies a phone's Dynamic Island to be switched off. Its parts (the pill, the front camera and sensor in it, the
    /// glass over them: the small parts on the face, centred at the top of the display) go in `islandCategory`; many
    /// models instead cut the island out of the display, so a hidden patch of the display covers where it sits, mapped
    /// as the display is, for the recording to carry on through it. A model whose island was only in its wallpaper
    /// (`draws`) gets a plain black one.
    static func rigIsland(_ meshes: [SCNNode], in root: SCNNode, draws: Bool) {
        guard let display = root.childNode(withName: displayName, recursively: true) else { return }
        let d = bounds(of: [display], in: root)
        let w = d.max.x - d.min.x, h = d.max.y - d.min.y, mid = (d.min.x + d.max.x) / 2
        guard w > 0, h > 0 else { return }
        // Where an island sits on every iPhone that has one, give or take.
        var lo = SIMD2(mid - w * 0.17, d.max.y - h * 0.07), hi = SIMD2(mid + w * 0.17, d.max.y - h * 0.012)
        for mesh in meshes where mesh !== display {
            let b = bounds(of: [mesh], in: root)
            let centre = (b.min + b.max) / 2, size = b.max - b.min
            let atTop = centre.y > d.max.y - h * 0.07 && centre.y < d.max.y
            let small = size.x < w * 0.45 && size.y < h * 0.05
            // Its face level with the display, or just behind it.
            guard abs(centre.x - mid) < w * 0.2, atTop, small, b.max.z >= d.min.z - h * 0.01 else { continue }
            mesh.categoryBitMask |= islandCategory
            lo = simd_min(lo, SIMD2(b.min.x, b.min.y) - w * 0.006)
            hi = simd_max(hi, SIMD2(b.max.x, b.max.y) + w * 0.006)
        }
        hi.y = min(hi.y, d.max.y - h * 0.004)
        // In front of the island and the display (and a black rim drawn around the island, as some models have it).
        var top = d.max.z
        for mesh in meshes where mesh !== display && mesh.categoryBitMask & glassCategory == 0 {
            let b = bounds(of: [mesh], in: root)
            guard b.min.x < hi.x, b.max.x > lo.x, b.min.y < hi.y, b.max.y > lo.y, b.max.z < d.max.z + h * 0.01 else { continue }
            top = max(top, b.max.z)
        }
        let z = top + displayLift
        let corners = [SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y)]
        let positions = corners.flatMap { [$0.x, $0.y, z] }
        let uv = corners.flatMap { [($0.x - d.min.x) / w, (d.max.y - $0.y) / h] }
        let element = SCNGeometryElement(indices: [UInt16(0), 1, 2, 0, 2, 3], primitiveType: .triangles)
        let patch = SCNNode(geometry: SCNGeometry(sources: [source(positions, semantic: .vertex, components: 3),
                                                            source(uv, semantic: .texcoord, components: 2)],
                                                  elements: [element]))
        patch.name = islandPatchName
        patch.isHidden = true
        root.addChildNode(patch)

        guard draws else { return }
        // An iPhone 14 Pro Max's island, a 6.7-inch screen's: as wide as 29% of the display, 3.9% as tall.
        let pw = w * 0.29, ph = h * 0.039
        let pill = SCNNode(geometry: roundedRect(width: pw, height: ph, radius: ph / 2 * 0.999))
        let black = SCNMaterial()
        black.lightingModel = .blinn
        black.diffuse.contents = NSColor.black
        black.specular.contents = NSColor(white: 0.16, alpha: 1)
        black.shininess = 0.5
        pill.geometry?.materials = [black]
        pill.simdPosition = SIMD3(mid, d.max.y - h * 0.032, z)
        pill.categoryBitMask |= islandCategory
        root.addChildNode(pill)
    }
}
