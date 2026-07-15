import Foundation
import Testing
@testable import VividUpscaler

@Test func scaleOutputNameKeepsInputFormat() throws {
    let input = URL(fileURLWithPath: "/tmp/portrait.JPG")
    let options = UpscaleOptions(mode: .normal, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .same)
    #expect(options.outputURL(for: input).path == "/tmp/portrait-vivid-upscale-2x.jpg")
}

@Test func resolutionOutputNameUsesChosenFormat() throws {
    let input = URL(fileURLWithPath: "/tmp/portrait.png")
    let options = UpscaleOptions(mode: .normal, sizingKind: .resolution, scale: 2, resolution: 2048, maxResolution: 4096, format: .webp)
    #expect(options.outputURL(for: input).path == "/tmp/portrait-vivid-upscale-2048px.webp")
}
