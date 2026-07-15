import Foundation
import Testing
@testable import VividUpscaler

@Test func scaleOutputNameKeepsInputFormat() throws {
    let input = URL(fileURLWithPath: "/tmp/portrait.JPG")
    let options = UpscaleOptions(mode: .normal, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .same, quality: 90)
    #expect(options.outputURL(for: input).path == "/tmp/portrait-vivid-upscale-normal-2x.jpg")
}

@Test func resolutionOutputNameUsesChosenFormat() throws {
    let input = URL(fileURLWithPath: "/tmp/portrait.png")
    let options = UpscaleOptions(mode: .normalHQ, sizingKind: .resolution, scale: 2, resolution: 2048, maxResolution: 4096, format: .webp, quality: 90)
    #expect(options.outputURL(for: input).path == "/tmp/portrait-vivid-upscale-normal-hq-2048px.webp")
}

@Test func qualitySupportMatchesOutputEncoding() {
    #expect(OutputFormat.jpg.supportsQuality(for: nil))
    #expect(OutputFormat.jxl.supportsQuality(for: nil))
    #expect(OutputFormat.webp.supportsQuality(for: nil))
    #expect(!OutputFormat.png.supportsQuality(for: nil))
    #expect(OutputFormat.same.supportsQuality(for: URL(fileURLWithPath: "/tmp/photo.jpeg")))
    #expect(!OutputFormat.same.supportsQuality(for: URL(fileURLWithPath: "/tmp/photo.png")))
}

@Test func qualityPresetsSnapToTheNearestStop() {
    #expect(OutputQualityPreset.allCases.map(\.rawValue) == [60, 75, 85, 90])
    #expect(OutputQualityPreset.nearest(to: 65) == .low)
    #expect(OutputQualityPreset.nearest(to: 70) == .medium)
    #expect(OutputQualityPreset.nearest(to: 84) == .high)
    #expect(OutputQualityPreset.nearest(to: 89) == .extraHigh)
}
