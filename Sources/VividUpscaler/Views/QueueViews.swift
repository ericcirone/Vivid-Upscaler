import AppKit
import SwiftUI

/// Loads a downsampled thumbnail off the main thread.
struct ThumbnailImage: View {
    let url: URL
    let maxPixelSize: Int
    var cornerRadius: CGFloat = 6

    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .overlay {
                        if didFail {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .task(id: url) {
            let url = url
            let maxPixelSize = maxPixelSize
            let loaded = await Task.detached(priority: .utility) {
                ImageInfo.thumbnail(for: url, maxPixelSize: maxPixelSize)
            }.value
            image = loaded
            didFail = loaded == nil
        }
    }
}

/// Compact status indicator shared by the queue row and single-photo view.
struct ItemStatusBadge: View {
    let status: BatchItem.Status
    let progress: Double?

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .help("Waiting")
        case .processing:
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Upscaled")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(message)
        case .skipped:
            Image(systemName: "arrow.uturn.forward.circle")
                .foregroundStyle(.secondary)
                .help("Skipped because the result already exists")
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .help("Cancelled")
        }
    }
}

struct QueueListView: View {
    @Bindable var store: UpscaleStore
    let compare: (BatchItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: $store.selectedItemID) {
                ForEach(store.items) { item in
                    QueueRow(store: store, item: item, compare: compare)
                        .tag(item.id)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: BatchItem.ID.self) { ids in
                if let id = ids.first, let item = store.items.first(where: { $0.id == id }) {
                    itemMenu(for: item)
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = store.items.first(where: { $0.id == id }), item.outputURL != nil {
                    compare(item)
                }
            }
            .onDeleteCommand {
                if let id = store.selectedItemID { store.removeItems([id]) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(store.items.count) Photos")
                .font(.headline)
            if let size = totalSourceMegapixels {
                Text(size)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.chooseInputs()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add photos or folders")
            Menu {
                Button("Remove Finished") { store.removeFinishedItems() }
                    .disabled(store.completedOutputs.isEmpty)
                Button("Remove All", role: .destructive) { store.removeAllItems() }
                    .disabled(store.isRunning)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var totalSourceMegapixels: String? {
        let sizes = store.items.compactMap(\.pixelSize)
        guard sizes.count == store.items.count, !sizes.isEmpty else { return nil }
        let megapixels = sizes.reduce(0) { $0 + $1.width * $1.height } / 1_000_000
        return String(format: "%.0f MP total", megapixels)
    }

    @ViewBuilder
    private func itemMenu(for item: BatchItem) -> some View {
        Button("Compare Original and Result") { compare(item) }
            .disabled(item.outputURL == nil)
        Button("Show Result in Finder") {
            if let output = item.outputURL { store.revealOutputs([output]) }
        }
        .disabled(item.outputURL == nil)
        Button("Show Original in Finder") { store.revealOutputs([item.url]) }
        Divider()
        Button("Remove from List", role: .destructive) { store.removeItems([item.id]) }
            .disabled(item.id == store.currentItemID)
    }
}

private struct QueueRow: View {
    let store: UpscaleStore
    let item: BatchItem
    let compare: (BatchItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailImage(url: item.url, maxPixelSize: 96, cornerRadius: 4)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
                    .font(.caption)
                    .foregroundStyle(item.errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if item.outputURL != nil {
                Button("Compare") { compare(item) }
                    .controlSize(.small)
            }
            ItemStatusBadge(status: item.status, progress: item.id == store.currentItemID ? store.progress : nil)
                .frame(width: 20)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let error = item.errorMessage {
            Text(error.components(separatedBy: .newlines).last(where: { !$0.isEmpty }) ?? error)
        } else if item.id == store.currentItemID {
            Text(store.status)
        } else if let pixelSize = item.pixelSize {
            if let output = store.outputPixelSize(for: item) {
                Text("\(ImageInfo.formatted(pixelSize)) → \(ImageInfo.formatted(output)) px")
            } else {
                Text("\(ImageInfo.formatted(pixelSize)) px")
            }
        } else {
            Text(item.url.deletingLastPathComponent().path)
                .truncationMode(.head)
        }
    }
}

/// Large preview used when the queue holds a single photo.
struct SinglePhotoView: View {
    @Bindable var store: UpscaleStore
    let item: BatchItem
    let compare: (BatchItem) -> Void

    var body: some View {
        VStack(spacing: 18) {
            ThumbnailImage(url: item.url, maxPixelSize: 1_400, cornerRadius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)

            VStack(spacing: 6) {
                Text(item.url.lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let pixelSize = item.pixelSize {
                    HStack(spacing: 6) {
                        Text("\(ImageInfo.formatted(pixelSize)) px")
                        if let output = store.outputPixelSize(for: item) {
                            Image(systemName: "arrow.right")
                            Text("\(ImageInfo.formatted(output)) px")
                                .foregroundStyle(.primary)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                if let output = store.outputURL(for: item), item.outputURL == nil {
                    Text("Saves as \(output.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if item.outputURL != nil {
                    HStack {
                        Button("Compare") { compare(item) }
                            .buttonStyle(.borderedProminent)
                        Button("Show in Finder") { store.revealOutput() }
                        Button("Open") {
                            if let output = item.outputURL { NSWorkspace.shared.open(output) }
                        }
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 4) {
                        Text("Drop more photos or a folder to upscale them together.")
                            .foregroundStyle(.tertiary)
                        if !store.isRunning {
                            Text("·").foregroundStyle(.tertiary)
                            Button("Remove") { store.removeItems([item.id]) }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(24)
    }
}

/// Progress, results, and stop controls under the photo area.
struct StatusBarView: View {
    @Bindable var store: UpscaleStore
    let showLog: () -> Void

    var body: some View {
        Group {
            if store.isRunning {
                running
            } else if let summary = store.lastRunSummary {
                finished(summary)
            } else {
                idle
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(.bar)
    }

    private var running: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if let overall = store.overallProgress {
                    ProgressView(value: overall)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = store.formattedRunningElapsedTime(at: context.date)
                    Text(elapsed)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed time \(elapsed)")
                }
            }
            HStack(spacing: 8) {
                Text(runningDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Log", action: showLog)
                Button("Stop", role: .destructive) { store.cancel() }
                    .disabled(store.isCancelling)
            }
            .controlSize(.small)
        }
    }

    private var runningDescription: String {
        guard !store.isCancelling else { return "Stopping…" }
        guard let position = store.currentRunPosition else { return store.status }
        if store.runItemIDs.count == 1 { return store.status }
        let name = store.currentItem?.url.lastPathComponent ?? ""
        return "\(position) of \(store.runItemIDs.count) · \(name) — \(store.status)"
    }

    private func finished(_ summary: UpscaleStore.RunSummary) -> some View {
        HStack(spacing: 8) {
            Label {
                Text("\(UpscaleStore.describe(summary)) in \(UpscaleStore.formatElapsedTime(summary.elapsed))")
            } icon: {
                if summary.failed > 0 {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if summary.completed == 0 {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .font(.callout)
            Spacer()
            Button("Log", action: showLog)
            if !store.completedOutputs.isEmpty {
                Button("Show in Finder") { store.revealOutputs(store.completedOutputs) }
            }
        }
        .controlSize(.small)
    }

    private var idle: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text("Saving to \(store.outputLocationDescription)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}
