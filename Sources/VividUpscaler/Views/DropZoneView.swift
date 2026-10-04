import SwiftUI

/// Empty state: invites the user to drop or choose photos and folders.
struct DropZoneView: View {
    let isTargeted: Bool
    let chooseAction: () -> Void

    var body: some View {
        Button(action: chooseAction) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )

                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 46))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    Text("Drop photos or folders here")
                        .font(.title2.bold())
                    Text("or click to choose files")
                        .foregroundStyle(.secondary)
                    Text("PNG · JPEG · HEIC · WebP · AVIF · JPEG XL · TIFF · BMP · GIF")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
                .padding(24)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Choose photos or folders to upscale")
    }
}
