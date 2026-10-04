import CoreGraphics
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

@Test func deblurOutputNameIdentifiesPreprocessing() throws {
    let input = URL(fileURLWithPath: "/tmp/portrait.jpg")
    let options = UpscaleOptions(mode: .normal, deblurMode: .motion, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .same, quality: 90)
    #expect(options.outputURL(for: input).path == "/tmp/portrait-vivid-upscale-normal-deblur-motion-2x.jpg")
}

@Test func faceRestoreOutputNameIdentifiesPreprocessing() throws {
    let input = URL(fileURLWithPath: "/tmp/portrait.jpg")
    let options = UpscaleOptions(mode: .normal, codeFormerOptions: .init(isEnabled: true), sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .same, quality: 90)
    #expect(options.outputURL(for: input).path == "/tmp/portrait-vivid-upscale-normal-face-restore-2x.jpg")
}

@Test func customOutputDirectoryReplacesTheInputFolder() {
    let input = URL(fileURLWithPath: "/photos/portrait.jpg")
    let options = UpscaleOptions(mode: .normal, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .png, quality: 90)
    let directory = URL(fileURLWithPath: "/exports", isDirectory: true)
    #expect(options.outputURL(for: input, in: directory).path == "/exports/portrait-vivid-upscale-normal-2x.png")
}

@Test func unwritableInputFormatsFallBackToSensibleOutputs() throws {
    let options = UpscaleOptions(mode: .fast, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .same, quality: 90)
    #expect(try OutputNaming.validatedOutputURL(input: URL(fileURLWithPath: "/tmp/IMG_0001.HEIC"), options: options).pathExtension == "jpg")
    #expect(try OutputNaming.validatedOutputURL(input: URL(fileURLWithPath: "/tmp/scan.bmp"), options: options).pathExtension == "png")
    #expect(try OutputNaming.validatedOutputURL(input: URL(fileURLWithPath: "/tmp/scan.tif"), options: options).pathExtension == "tif")
    #expect(OutputFormat.same.supportsQuality(for: URL(fileURLWithPath: "/tmp/IMG_0001.heic")))
}

@Test func batchOutputsNeverCollide() throws {
    let options = UpscaleOptions(mode: .fast, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .png, quality: 90)
    let inputs = ["/a/photo.jpg", "/a/photo.png", "/b/photo.jpg"].map { URL(fileURLWithPath: $0) }
    let directory = URL(fileURLWithPath: "/out", isDirectory: true)
    let outputs = try OutputNaming.uniqueOutputURLs(inputs: inputs, options: options, directory: directory)
    #expect(outputs.map(\.lastPathComponent) == [
        "photo-vivid-upscale-fast-2x.png",
        "photo-vivid-upscale-fast-2x-2.png",
        "photo-vivid-upscale-fast-2x-3.png"
    ])
    let besideOriginals = try OutputNaming.uniqueOutputURLs(inputs: inputs, options: options, directory: nil)
    #expect(besideOriginals.map(\.path) == [
        "/a/photo-vivid-upscale-fast-2x.png",
        "/a/photo-vivid-upscale-fast-2x-2.png",
        "/b/photo-vivid-upscale-fast-2x.png"
    ])
}

@Test func outputSizePreviewMatchesTheCLI() {
    var options = UpscaleOptions(mode: .normal, sizingKind: .scale, scale: 2, resolution: 2048, maxResolution: 4096, format: .same, quality: 90)
    #expect(options.outputPixelSize(for: CGSize(width: 1200, height: 800)) == CGSize(width: 2400, height: 1600))
    options.scale = 1.5
    #expect(options.outputPixelSize(for: CGSize(width: 333, height: 500)) == CGSize(width: 500, height: 750))
    options.sizingKind = .resolution
    #expect(options.outputPixelSize(for: CGSize(width: 1000, height: 500)) == CGSize(width: 4096, height: 2048))
    options.resolution = 1000
    #expect(options.outputPixelSize(for: CGSize(width: 3000, height: 2000)) == CGSize(width: 1500, height: 1000))
}

@Test func qualitySupportMatchesOutputEncoding() {
    #expect(OutputFormat.jpg.supportsQuality(for: nil))
    #expect(OutputFormat.jxl.supportsQuality(for: nil))
    #expect(OutputFormat.webp.supportsQuality(for: nil))
    #expect(OutputFormat.avif.supportsQuality(for: nil))
    #expect(!OutputFormat.png.supportsQuality(for: nil))
    #expect(!OutputFormat.tiff.supportsQuality(for: nil))
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
