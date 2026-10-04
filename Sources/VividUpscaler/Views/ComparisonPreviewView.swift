import AppKit
import SwiftUI

struct ComparisonPreviewView: View {
    private struct LoadedImages {
        let original: NSImage
        let upscaled: NSImage
    }

    private let originalURL: URL
    private let upscaledURL: URL
    private var originalName: String { originalURL.lastPathComponent }
    private var upscaledName: String { upscaledURL.lastPathComponent }

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.displayScale) private var displayScale
    @State private var dividerPosition = 0.5
    @State private var isActualSize = false
    @State private var images: LoadedImages?
    @State private var didFailToLoad = false

    init(originalURL: URL, upscaledURL: URL) {
        self.originalURL = originalURL
        self.upscaledURL = upscaledURL
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let images {
                comparisonViewer(originalImage: images.original, upscaledImage: images.upscaled)
            } else if didFailToLoad {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("The original or upscaled image could not be opened.")
                )
            } else {
                ProgressView("Loading images…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: [originalURL, upscaledURL]) {
            images = nil
            didFailToLoad = false
            // Decode once, here, rather than in init: the window's content is
            // rebuilt on every store change while a batch is running.
            if let original = NSImage(contentsOf: originalURL),
               let upscaled = NSImage(contentsOf: upscaledURL) {
                images = LoadedImages(original: original, upscaled: upscaled)
            } else {
                didFailToLoad = true
            }
        }
        .frame(
            minWidth: 760,
            idealWidth: 1_000,
            maxWidth: .infinity,
            minHeight: 560,
            idealHeight: 720,
            maxHeight: .infinity
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(originalName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Drag the divider or slider to compare. Use 1:1 to inspect pixels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isActualSize.toggle()
            } label: {
                Label(isActualSize ? "Fit" : "1:1", systemImage: isActualSize ? "arrow.down.right.and.arrow.up.left" : "magnifyingglass")
            }
            .help(isActualSize ? "Fit the image in the viewer" : "Show the upscaled image at one image pixel per screen pixel")

            Button("Done") { dismissWindow(id: "comparison-preview") }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private func comparisonViewer(originalImage: NSImage, upscaledImage: NSImage) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if isActualSize {
                    ScrollView([.horizontal, .vertical]) {
                        comparisonCanvas(originalImage: originalImage, upscaledImage: upscaledImage)
                            .frame(
                                width: upscaledImage.pixelSize.width / displayScale,
                                height: upscaledImage.pixelSize.height / displayScale
                            )
                    }
                } else {
                    GeometryReader { geometry in
                        let canvasSize = fittedSize(
                            aspectRatio: upscaledImage.pixelSize.aspectRatio,
                            inside: geometry.size
                        )

                        comparisonCanvas(originalImage: originalImage, upscaledImage: upscaledImage)
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(20)
                }
            }

            HStack(spacing: 12) {
                Text("Original")
                    .frame(width: 64, alignment: .leading)

                Slider(value: $dividerPosition, in: 0...1)
                    .accessibilityLabel("Image comparison position")
                    .accessibilityValue("\(Int(dividerPosition * 100)) percent original")

                Text("Upscaled")
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func comparisonCanvas(originalImage: NSImage, upscaledImage: NSImage) -> some View {
        GeometryReader { geometry in
            let dividerX = dividerPosition * geometry.size.width

            ZStack(alignment: .leading) {
                Image(nsImage: upscaledImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                Image(nsImage: originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: dividerX)
                    }

                comparisonLabels

                Rectangle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .frame(width: 2)
                    .offset(x: dividerX - 1)

                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
                    .shadow(radius: 2)
                    .position(x: dividerX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard geometry.size.width > 0 else { return }
                        dividerPosition = min(max(value.location.x / geometry.size.width, 0), 1)
                    }
            )
            .accessibilityElement(children: .contain)
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private var comparisonLabels: some View {
        HStack {
            imageLabel("Original", fileName: originalName)
            Spacer()
            imageLabel("Upscaled", fileName: upscaledName)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func imageLabel(_ title: String, fileName: String) -> some View {
        VStack(alignment: title == "Original" ? .leading : .trailing, spacing: 2) {
            Text(title).font(.headline)
            Text(fileName).font(.caption).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private func fittedSize(aspectRatio: CGFloat, inside availableSize: CGSize) -> CGSize {
        guard aspectRatio > 0, availableSize.width > 0, availableSize.height > 0 else {
            return .zero
        }

        if availableSize.width / availableSize.height > aspectRatio {
            return CGSize(width: availableSize.height * aspectRatio, height: availableSize.height)
        }

        return CGSize(width: availableSize.width, height: availableSize.width / aspectRatio)
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        let representationSize = representations.reduce(CGSize.zero) { current, representation in
            CGSize(
                width: max(current.width, CGFloat(representation.pixelsWide)),
                height: max(current.height, CGFloat(representation.pixelsHigh))
            )
        }

        return representationSize.width > 0 && representationSize.height > 0 ? representationSize : size
    }
}

private extension CGSize {
    var aspectRatio: CGFloat {
        height > 0 ? width / height : 1
    }
}
