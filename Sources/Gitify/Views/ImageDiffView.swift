import SwiftUI
import GitKit

/// Image comparison view with side-by-side and swipe scrubber modes.
struct ImageDiffView: View {
    let data: ImageDiffData
    let isNew: Bool
    let isDeleted: Bool

    private enum Mode: String, CaseIterable {
        case sideBySide = "Side by Side"
        case swipe = "Swipe"
        case before = "Before"
        case after = "After"
    }
    @State private var mode: Mode = .sideBySide
    @State private var scrubberFraction: CGFloat = 0.5

    /// Whether both images are available (scrubbing only makes sense with two images).
    private var hasBothImages: Bool {
        data.oldImage != nil && data.newImage != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasBothImages {
                header
            }
            switch mode {
            case .swipe where hasBothImages:
                swipeBody
            case .before:
                singlePanel(label: "Before", imageData: data.oldImage,
                            placeholder: isNew ? "New File" : nil)
            case .after:
                singlePanel(label: "After", imageData: data.newImage,
                            placeholder: isDeleted ? "Deleted" : nil)
            default:
                sideBySideBody
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)
    }

    // MARK: - Side by Side

    private var sideBySideBody: some View {
        GeometryReader { geo in
            let panelWidth = (geo.size.width - 1) / 2
            let panelContentHeight = geo.size.height - 30 // label bar height
            let sharedSize: CGSize? = {
                guard let oldData = data.oldImage, let oldImg = NSImage(data: oldData),
                      let newData = data.newImage, let newImg = NSImage(data: newData) else { return nil }
                let padding: CGFloat = 16
                let available = CGSize(width: panelWidth - padding * 2,
                                       height: panelContentHeight - padding * 2 - 24)
                return fittedSize(old: oldImg, new: newImg, within: available)
            }()

            HStack(spacing: 1) {
                panel(label: "Before", imageData: data.oldImage,
                      placeholder: isNew ? "New File" : nil, sharedSize: sharedSize)
                panel(label: "After", imageData: data.newImage,
                      placeholder: isDeleted ? "Deleted" : nil, sharedSize: sharedSize)
            }
        }
    }

    private func panel(label: String, imageData: Data?, placeholder: String?,
                       sharedSize: CGSize?) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)

            if let placeholder {
                ContentUnavailableView(placeholder, systemImage: "photo",
                                       description: Text("No image to display."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let imageData, let nsImage = NSImage(data: imageData) {
                imageContent(nsImage, data: imageData, sharedSize: sharedSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle",
                                       description: Text("The image could not be loaded."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func imageContent(_ nsImage: NSImage, data: Data, sharedSize: CGSize?) -> some View {
        VStack(spacing: 4) {
            Spacer()
            if let sharedSize {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: sharedSize.width, maxHeight: sharedSize.height)
                    .padding(16)
                    .background {
                        checkerboard
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
            } else {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
                    .background {
                        checkerboard
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
            }
            Spacer()
            imageMetadata(nsImage, data: data)
        }
    }

    // MARK: - Single Image (Before / After)

    private func singlePanel(label: String, imageData: Data?, placeholder: String?) -> some View {
        panel(label: label, imageData: imageData, placeholder: placeholder, sharedSize: nil)
    }

    // MARK: - Swipe / Scrubber

    private var swipeBody: some View {
        GeometryReader { geo in
            let padding: CGFloat = 16
            let available = CGSize(width: geo.size.width - padding * 2,
                                   height: geo.size.height - padding * 2 - 28)
            // Both images must exist (checked by hasBothImages).
            let oldImage = NSImage(data: data.oldImage!)!
            let newImage = NSImage(data: data.newImage!)!
            let imageSize = fittedSize(old: oldImage, new: newImage, within: available)
            let originX = (geo.size.width - imageSize.width) / 2
            let originY = padding
            let dividerX = originX + imageSize.width * scrubberFraction

            ZStack(alignment: .topLeading) {
                checkerboard

                // Old image (full, behind)
                Image(nsImage: oldImage)
                    .resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .position(x: originX + imageSize.width / 2, y: originY + imageSize.height / 2)

                // New image (clipped from the scrubber rightward)
                Image(nsImage: newImage)
                    .resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .clipShape(
                        ClipFromLeft(fraction: scrubberFraction)
                    )
                    .position(x: originX + imageSize.width / 2, y: originY + imageSize.height / 2)

                // Scrubber divider line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: imageSize.height)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 0)
                    .overlay(scrubberHandle, alignment: .center)
                    .position(x: dividerX, y: originY + imageSize.height / 2)

                // Labels
                Text("Before")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .position(x: originX + 36, y: originY + 14)

                Text("After")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .position(x: originX + imageSize.width - 30, y: originY + 14)

                // Metadata bar
                swipeMetadata(old: oldImage, new: newImage)
                    .position(x: geo.size.width / 2,
                              y: originY + imageSize.height + 18)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = (value.location.x - originX) / imageSize.width
                        scrubberFraction = min(max(fraction, 0), 1)
                    }
            )
        }
    }

    private var scrubberHandle: some View {
        Capsule()
            .fill(Color.white)
            .shadow(color: .black.opacity(0.3), radius: 3)
            .frame(width: 8, height: 36)
            .overlay {
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color.gray)
                            .frame(width: 1, height: 12)
                    }
                }
            }
    }

    private func swipeMetadata(old: NSImage, new: NSImage) -> some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 6, height: 6)
                if let rep = old.representations.first {
                    Text("\(rep.pixelsWide) \u{00d7} \(rep.pixelsHigh)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(byteCountDescription(data.oldImage!.count))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                if let rep = new.representations.first {
                    Text("\(rep.pixelsWide) \u{00d7} \(rep.pixelsHigh)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(byteCountDescription(data.newImage!.count))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Computes the largest size that fits both images at the same scale within `bounds`.
    private func fittedSize(old: NSImage, new: NSImage, within bounds: CGSize) -> CGSize {
        let maxW = max(old.size.width, new.size.width)
        let maxH = max(old.size.height, new.size.height)
        guard maxW > 0, maxH > 0 else { return .zero }
        let scale = min(bounds.width / maxW, bounds.height / maxH, 1)
        return CGSize(width: maxW * scale, height: maxH * scale)
    }

    // MARK: - Shared

    private func imageMetadata(_ nsImage: NSImage, data: Data) -> some View {
        HStack(spacing: 12) {
            if let rep = nsImage.representations.first {
                Text("\(rep.pixelsWide) \u{00d7} \(rep.pixelsHigh)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(byteCountDescription(data.count))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let step: CGFloat = 8
            let light = Color(white: 0.9)
            let dark = Color(white: 0.75)
            for row in 0..<Int(ceil(size.height / step)) {
                for col in 0..<Int(ceil(size.width / step)) {
                    let color = (row + col).isMultiple(of: 2) ? light : dark
                    let rect = CGRect(x: CGFloat(col) * step, y: CGFloat(row) * step,
                                      width: step, height: step)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private func byteCountDescription(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// Clips to the right portion of the view, starting at `fraction` of the width.
private struct ClipFromLeft: Shape {
    var fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX + rect.width * fraction, y: rect.minY,
                    width: rect.width * (1 - fraction), height: rect.height))
    }
}
