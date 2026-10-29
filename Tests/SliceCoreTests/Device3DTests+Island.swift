//
//  Device3DTests+Island.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/29/26.
//

import CoreImage
@testable import SliceCore
import XCTest

extension Device3DTests {
    func testEveryPhonesDynamicIslandSwitchesOff() throws {
        XCTAssertTrue(try JSONDecoder().decode(Device3DSettings.self, from: Data("{}".utf8)).dynamicIsland, "on unless switched off")
        var off = Device3DSettings()
        off.dynamicIsland = false
        XCTAssertFalse(try JSONDecoder().decode(Device3DSettings.self, from: JSONEncoder().encode(off)).dynamicIsland)

        let size = CGSize(width: 450, height: 750), whole = CGRect(origin: .zero, size: size)
        let ctx = CIContext()
        for model in Device3DModel.models(.phone) {
            let aspect = try XCTUnwrap(Device3DRenderer.shared.displayAspect(for: model), model.label)
            let light = CIImage(color: CIColor(red: 0.85, green: 0.88, blue: 0.95)).cropped(to: CGRect(x: 0, y: 0, width: 1000 * aspect, height: 1000))
            func dark(_ island: Bool) throws -> Set<Int> {
                var s = Device3DSettings()
                s.model = model
                s.placement = Device3DPlacement(yaw: 0, pitch: 0)
                s.dynamicIsland = island
                let request = Device3DRequest(output: size, view: whole, fit: whole.insetBy(dx: 30, dy: 30), pose: s.pose(at: 0),
                                              settings: s, landscape: false, display: light)
                let image = try XCTUnwrap(Device3DRenderer.shared.render(request))
                let cg = try XCTUnwrap(ctx.createCGImage(image.composited(over: CIImage(color: .white).cropped(to: whole)), from: whole))
                let px = try XCTUnwrap(DeviceImportTests.pixels(cg))
                // The top middle of the phone, where an island is.
                var found = Set<Int>()
                for y in 20 ..< 160 { for x in 150 ..< 300 where px(x, y).x < 0.25 { found.insert(y * 1000 + x) } }
                return found
            }
            let on = try dark(true), gone = try dark(false)
            XCTAssertGreaterThan(on.subtracting(gone).count, 150, "\(model.label): switched off, the island's place shows the recording")
            XCTAssertLessThan(gone.subtracting(on).count, 20, "\(model.label): and nothing dark turns up in its place")
        }
    }
}
