import AppKit
import SwiftUI

struct DropZoneView: View {
    let inputURL: URL?
    let isTargeted: Bool
    let chooseAction: () -> Void

    var body: some View {
        Button(action: chooseAction) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8]))

                if let inputURL {
                    HStack(spacing: 22) {
                        if let image = NSImage(contentsOf: inputURL) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(inputURL.lastPathComponent).font(.title3.bold()).lineLimit(2)
                            Text("Click or drop another photo to replace it").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("Drop a photo here").font(.title2.bold())
                        Text("or click to choose a file").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 250)
        .accessibilityLabel(inputURL == nil ? "Choose an image to upscale" : "Change input image")
    }
}
