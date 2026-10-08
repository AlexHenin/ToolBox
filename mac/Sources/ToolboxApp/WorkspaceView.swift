import AppKit
import PDFKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @ObservedObject var store: ToolStore
    @State private var isDropTarget = false
    @State private var hoveredToolID: String?
    @State private var draggedFileURL: URL?
    @State private var fileThumbnailFrames: [URL: CGRect] = [:]
    @State private var fileDragLocation: CGPoint = .zero
    @State private var fileInsertionIndex: Int?
    @State private var previewedFileURL: URL?

    var body: some View {
        Group {
            if store.isLoading {
                Palette.window
            } else {
                workspace
            }
        }
        .background(Palette.window)
    }

    private var workspace: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Palette.stroke).frame(width: 1)
                mainArea
            }
            if isDropTarget {
                RoundedRectangle(cornerRadius: Layout.lg)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [Layout.sm, Layout.xs]))
                    .padding(.vertical, Layout.md)
                    .padding(.trailing, Layout.md)
                    .padding(.leading, Layout.sidebarWidth + Layout.md)
                    .overlay {
                        Text("Drop files to add")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, Layout.lg)
                            .padding(.vertical, Layout.md)
                            .background(Palette.panel, in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
            if let previewedFileURL {
                FullscreenFilePreview(url: previewedFileURL) {
                    self.previewedFileURL = nil
                }
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: importDroppedFiles)
    }

    private func importDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let droppedURL = item as? URL {
                    url = droppedURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in store.importDroppedFiles([url]) }
            }
        }
        return true
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ToolBox").font(.system(size: 17, weight: .semibold))
            .padding(.top, Layout.sidebarTopInset)
            .padding(.horizontal, Layout.sidebarInset)
            Text("TOOLS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, Layout.sidebarInset)
                .padding(.top, Layout.sectionTopGap)
                .padding(.bottom, Layout.sectionBottomGap)
            ForEach(store.tools) { tool in
                let isHighlighted = store.selected?.id == tool.id || hoveredToolID == tool.id
                Button { Task { await store.select(tool.id) } } label: {
                    HStack(spacing: Layout.md) {
                        toolIcon(for: tool.id)
                            .frame(width: tool.id == "convert-files" ? 48 : 18, height: 18)
                        Text(tool.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(isHighlighted ? Palette.text : Palette.muted)
                    .padding(.horizontal, Layout.navigationHorizontalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Layout.navigationRowHeight)
                    .background(isHighlighted ? Palette.panel : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(store.running)
                .onHover { isHovering in
                    hoveredToolID = isHovering ? tool.id : nil
                }
                .padding(.horizontal, Layout.sm)
                .padding(.bottom, 0)
            }
            Spacer()
        }
        .frame(width: Layout.sidebarWidth)
        .background(Palette.sidebar)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.selected?.title ?? "Tools")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, Layout.contentInset)
            .frame(height: Layout.headerHeight)
            Rectangle().fill(Palette.stroke).frame(height: 1)
            if let tool = store.selected {
                if tool.id == "convert-files" {
                    converterWorkspace(tool)
                } else {
                    genericWorkspace(tool)
                }
            } else {
                Spacer()
                Text(store.status).foregroundStyle(Palette.muted)
                Spacer()
            }
            if store.running || store.result != nil || store.status != "Ready" {
                resultBar
            }
        }
    }

    private func genericWorkspace(_ tool: ToolDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.contentSectionGap) {
                ForEach(visibleFields(for: tool)) { field in
                    fieldView(field)
                }
                if hasSelectedInputs(for: tool) {
                    Button { Task { await store.execute() } } label: {
                        HStack(spacing: Layout.sm) {
                            if store.running { ProgressView().controlSize(.small) }
                            else { Image(systemName: actionIcon(for: tool.id)).font(.system(size: 10)) }
                            Text(store.running ? "Working…" : actionTitle(for: tool.id))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minWidth: 140, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .disabled(store.running)
                }
            }
            .frame(maxWidth: tool.id == "crop" ? 1200 : 876, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Layout.xl)
            .padding(.horizontal, Layout.contentInset)
            .padding(.bottom, Layout.contentInset)
        }
    }

    private func converterWorkspace(_ tool: ToolDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.xl) {
                if let files = tool.fields.first(where: { $0.kind == "files" }) {
                    conversionFilesField(files)
                }

                if hasSelectedInputs(for: tool) {
                    VStack(alignment: .leading, spacing: Layout.sm) {
                        Text("Convert to").font(.system(size: 13, weight: .medium))
                        if store.conversionTargetsLoading {
                            HStack(spacing: Layout.sm) {
                                ProgressView().controlSize(.small)
                                Text("Finding compatible formats…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.muted)
                            }
                        } else if !store.conversionTargets.isEmpty {
                            Picker("Convert to", selection: valueBinding("target")) {
                                ForEach(store.conversionTargets, id: \.self) { target in
                                    Text(target.uppercased()).tag(target)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240, alignment: .leading)
                        } else {
                            Text("No common output format is available for these files.")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                    }

                    if !(store.values["target"] ?? "").isEmpty {
                        HStack(spacing: Layout.md) {
                            Button {
                                Task { await store.execute() }
                            } label: {
                                Label(store.running ? "Converting…" : "Convert", systemImage: "doc.badge.plus")
                                    .frame(minWidth: 150, minHeight: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                            .disabled(store.running)

                            if let result = store.result {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([result]) } label: {
                                    Label("Reveal Output", systemImage: "folder")
                                        .frame(minHeight: 40)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if let result = store.result {
                    Rectangle().fill(Palette.stroke).frame(height: 1)
                    HStack(spacing: Layout.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.success)
                        VStack(alignment: .leading, spacing: Layout.xs) {
                            Text("Completed")
                                .font(.system(size: 13, weight: .medium))
                            Text("Saved to \(result.path)")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: 876, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Layout.xl)
            .padding(.horizontal, Layout.contentInset)
            .padding(.bottom, Layout.contentInset)
        }
    }

    private func conversionFilesField(_ field: ToolField) -> some View {
        let selected = store.files[field.name] ?? []
        return VStack(alignment: .leading, spacing: Layout.sm) {
            if selected.isEmpty {
                HStack(spacing: Layout.md) {
                    Text("Upload file")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, Layout.md)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                    Button("Choose") { store.chooseFiles(field) }
                        .frame(minWidth: 108, minHeight: 40)
                        .buttonStyle(.bordered)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(selected.enumerated()), id: \.element.path) { index, url in
                                fileInsertionBar(for: index)

                                ConversionFileThumbnail(
                                    url: url,
                                    open: { previewedFileURL = url },
                                    remove: { store.removeFile(url, from: field.name) }
                                )
                                .frame(width: 88, height: 72)
                                .opacity(draggedFileURL == url ? 0.22 : 1)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: FileThumbnailFramePreferenceKey.self,
                                            value: [url: proxy.frame(in: .named("conversion-file-strip"))]
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
                                .gesture(fileReorderGesture(for: url, files: selected, fieldName: field.name))

                                if index < selected.count - 1 {
                                    Color.clear.frame(width: Layout.sm)
                                }
                            }
                            fileInsertionBar(for: selected.count)
                            Button { store.chooseFiles(field, appending: true) } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 88, height: 72)
                                    .background(Palette.window, in: RoundedRectangle(cornerRadius: Layout.sm))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Layout.sm)
                                            .stroke(Palette.stroke)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("Add more files")
                        }
                        .padding(Layout.sm)
                    }
                    .coordinateSpace(name: "conversion-file-strip")
                    .onPreferenceChange(FileThumbnailFramePreferenceKey.self) { fileThumbnailFrames = $0 }

                    if let draggedFileURL {
                        ConversionFileThumbnail(url: draggedFileURL, canRemove: false, open: {}, remove: {})
                            .frame(width: 88, height: 72)
                            .allowsHitTesting(false)
                            .shadow(radius: Layout.sm, y: Layout.xs)
                            .position(x: fileDragLocation.x, y: fileDragLocation.y)
                            .zIndex(100)
                    }
                }
                .frame(height: 88)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func fileInsertionBar(for index: Int) -> some View {
        Rectangle()
            .fill(fileInsertionIndex == index ? Palette.insertion : .clear)
            .frame(width: 3, height: 62)
            .clipShape(Capsule())
            .padding(.horizontal, Layout.xs)
    }

    private func fileReorderGesture(for url: URL, files: [URL], fieldName: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("conversion-file-strip"))
            .onChanged { value in
                if draggedFileURL == nil { draggedFileURL = url }
                fileDragLocation = value.location
                updateFileInsertionIndex(for: value.location.x, files: files)
            }
            .onEnded { _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { draggedFileURL = nil }

                if let rawDestination = fileInsertionIndex {
                    store.moveFile(url, toInsertionIndex: rawDestination, in: fieldName)
                }

                withTransaction(transaction) { fileInsertionIndex = nil }
            }
    }

    private func updateFileInsertionIndex(for x: CGFloat, files: [URL]) {
        let ordered = files.compactMap { url -> CGRect? in fileThumbnailFrames[url] }
        guard !ordered.isEmpty else { return }

        for (index, frame) in ordered.enumerated() {
            if x < frame.midX {
                fileInsertionIndex = index
                return
            }
            if x <= frame.maxX {
                fileInsertionIndex = index + 1
                return
            }
        }
        fileInsertionIndex = files.count
    }

    private func hasSelectedInputs(for tool: ToolDefinition) -> Bool {
        tool.fields
            .filter { $0.required && ($0.kind == "file" || $0.kind == "files") }
            .allSatisfy { !(store.files[$0.name] ?? []).isEmpty }
    }

    private func visibleFields(for tool: ToolDefinition) -> [ToolField] {
        tool.fields.filter { field in
            if field.kind == "output" { return false }
            if tool.id == "crop" && field.name == "dpi" { return false }
            if field.kind == "file" || field.kind == "files" { return true }
            return hasSelectedInputs(for: tool)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: ToolField) -> some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            if field.kind != "time_range" && field.kind != "file" && field.kind != "files" {
                Text(field.label)
                    .font(.system(size: 13, weight: .medium))
            }
            switch field.kind {
            case "file", "files": fileField(field)
            case "rectangle": cropField(field)
            case "time_range": timeRangeField(field)
            case "boolean":
                Toggle(field.label, isOn: Binding(
                    get: { store.values[field.name] == "true" },
                    set: { store.values[field.name] = $0 ? "true" : "false" }
                ))
            case "choice":
                Picker(field.label, selection: valueBinding(field.name)) {
                    ForEach(field.choices, id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            default:
                TextField(field.label, text: valueBinding(field.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileField(_ field: ToolField) -> some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            let selected = store.files[field.name] ?? []
            if selected.isEmpty {
                HStack(spacing: Layout.md) {
                    Text(["crop", "trim"].contains(store.selected?.id ?? "") ? "Upload file" : "Choose \(fileDescription(for: field))")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, Layout.md)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Layout.sm))
                    Button("Choose") { store.chooseFiles(field) }
                        .frame(minWidth: 108, minHeight: 40)
                        .buttonStyle(.bordered)
                }
            } else {
                ForEach(Array(selected.enumerated()), id: \.offset) { index, url in
                    HStack(spacing: Layout.md) {
                        Image(systemName: "doc.fill").foregroundStyle(Palette.accent)
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        if ["crop", "trim"].contains(store.selected?.id ?? "") {
                            FileRemovalButton(helpText: "Clear selected file") {
                                store.removeFile(url, from: field.name)
                            }
                        }
                        if field.kind == "files" {
                            Button { move(field.name, index, -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0)
                            Button { move(field.name, index, 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == selected.count - 1)
                        }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, Layout.md)
                    .frame(height: 36)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                }
                HStack {
                    Button { store.chooseFiles(field) } label: {
                        Text("Choose")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.text)
                            .frame(width: 108, height: 40)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: Layout.sm))
                            .overlay {
                                RoundedRectangle(cornerRadius: Layout.sm)
                                    .stroke(Palette.stroke)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: Layout.sm))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            if field.kind == "file", store.selected?.fields.contains(where: { $0.kind == "rectangle" }) == true,
               let url = selected.first {
                CropPreview(url: url, crop: $store.crop)
                    .frame(height: 560)
            }
        }
    }

    private func fileDescription(for field: ToolField) -> String {
        guard !field.extensions.isEmpty else { return field.kind == "files" ? "files" : "a file" }
        let names = field.extensions.map { $0.uppercased() }.joined(separator: " or ")
        return field.kind == "files" ? "one or more \(names) files" : "a \(names) file"
    }

    private func cropField(_ field: ToolField) -> some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            Text("Drag on the preview to select the area to keep. For multi-page or animated files, the same relative area applies to every frame.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private func timeRangeField(_ field: ToolField) -> some View {
        let startKey = field.name + "_start"
        let endKey = field.name + "_end"
        return VStack(alignment: .leading, spacing: Layout.md) {
            if let url = store.files.values.first?.first, store.duration > 0 {
                if store.mediaKind == "video" {
                    VideoTrimEditor(url: url, duration: store.duration, peaks: store.waveform,
                                    start: numericBinding(startKey), end: numericBinding(endKey))
                        .id(url.path)
                } else {
                    WaveformEditor(url: url, duration: store.duration, peaks: store.waveform,
                                   start: numericBinding(startKey), end: numericBinding(endKey))
                        .id(url.path)
                }
            } else {
                Text(store.waveformLoading ? "Loading waveform…" : "Waveform unavailable for this file")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .padding(Layout.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var resultBar: some View {
        HStack(spacing: Layout.md) {
            Image(systemName: store.result == nil ? "circle.dotted" : "checkmark.circle.fill")
                .foregroundStyle(store.result == nil ? Palette.muted : Palette.accent)
            Text(store.status).font(.system(size: 12)).lineLimit(2)
            Spacer()
            if let result = store.result {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                Button("Open") { NSWorkspace.shared.open(result) }
            }
        }
        .padding(.horizontal, Layout.xl)
        .frame(height: Layout.footerHeight)
        .background(Palette.sidebar)
    }

    private func valueBinding(_ key: String) -> Binding<String> {
        Binding(get: { store.values[key] ?? "" }, set: { store.values[key] = $0 })
    }

    private func numericBinding(_ key: String) -> Binding<Double> {
        Binding(get: {
            guard let number = Double(store.values[key] ?? ""), number.isFinite else { return 0 }
            return number
        }, set: { store.values[key] = String(format: "%.2f", $0) })
    }

    private func move(_ key: String, _ index: Int, _ direction: Int) {
        guard var values = store.files[key], values.indices.contains(index + direction) else { return }
        values.swapAt(index, index + direction)
        store.files[key] = values
    }

    private func icon(for id: String) -> String {
        if id.contains("pdf") { return "doc.richtext" }
        if id == "trim" { return "scissors" }
        if id.contains("image") { return "photo" }
        return "square.grid.2x2"
    }

    private func actionTitle(for id: String) -> String {
        if id == "crop" { return "Crop" }
        if id == "trim" { return "Trim" }
        return "Convert"
    }

    private func actionIcon(for id: String) -> String {
        if id == "crop" { return "crop" }
        if id == "trim" { return "scissors" }
        return "play.fill"
    }

    @ViewBuilder
    private func toolIcon(for id: String) -> some View {
        if id == "convert-files" {
            HStack(spacing: 2) {
                Image(systemName: "doc.richtext")
                Text("↔")
                Image(systemName: "doc.richtext")
            }
            .font(.system(size: 11))
        } else if id == "crop", let url = Bundle.module.url(forResource: "crop-selection", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .padding(1)
        } else {
            Image(systemName: icon(for: id))
                .font(.system(size: 14))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, remainder)
    }
}

private struct ConversionFileThumbnail: View {
    let url: URL
    var canRemove = true
    let open: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            preview
            if canRemove && isHovering {
                FileRemovalButton(
                    helpText: "Remove \(url.lastPathComponent)",
                    diameter: Layout.lg,
                    action: remove
                )
                .padding(Layout.xs)
            }
        }
        .onHover { isHovering = $0 }
        .simultaneousGesture(TapGesture().onEnded(open))
        .help("Open \(url.lastPathComponent) full screen")
    }

    @ViewBuilder
    private var preview: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Layout.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.sm)
                        .stroke(Palette.stroke)
                }
                .help(url.lastPathComponent)
        } else {
            Image(systemName: "doc.fill")
                .foregroundStyle(Palette.muted)
                .frame(width: 88, height: 72)
                .background(Palette.window, in: RoundedRectangle(cornerRadius: Layout.sm))
                .help(url.lastPathComponent)
        }
    }
}

private struct FullscreenFilePreview: View {
    let url: URL
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Layout.md) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.brightMuted)
                        .frame(width: 28, height: 28)
                        .background(Palette.overlayStrong, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close preview")
                .accessibilityLabel("Close preview")
            }
            .padding(.horizontal, Layout.lg)
            .frame(height: Layout.headerHeight)
            .background(Palette.sidebar)

            QuickLookPreview(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        .background(Palette.window)
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.previewItem = url as NSURL
        return view!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) != url as NSURL {
            view.previewItem = url as NSURL
            view.refreshPreviewItem()
        }
    }
}

private struct FileRemovalButton: View {
    let helpText: String
    var diameter: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: diameter * 0.375, weight: .semibold))
                .foregroundStyle(Palette.brightMuted)
                .frame(width: diameter, height: diameter)
                .background(Palette.overlayStrong, in: Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

private struct FileThumbnailFramePreferenceKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CropPreview: View {
    let url: URL
    @Binding var crop: CGRect
    @State private var resizeStartCrop: CGRect?
    @State private var moveStartCrop: CGRect?
    @State private var drawingStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            if let preview = preview(fitting: geometry.size) {
                let width = preview.size.width
                let height = preview.size.height
                ZStack(alignment: .topLeading) {
                    Image(nsImage: preview.image)
                        .resizable()
                        .frame(width: width, height: height)

                    Path { path in
                        path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                        path.addRect(CGRect(
                            x: crop.minX * width,
                            y: crop.minY * height,
                            width: crop.width * width,
                            height: crop.height * height
                        ))
                    }
                    .fill(Palette.selectionScrim, style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    Rectangle()
                        .fill(Palette.selectionScrim.opacity(0.001))
                        .overlay { Rectangle().stroke(Palette.accent, lineWidth: 2) }
                        .frame(width: crop.width * width, height: crop.height * height)
                        .offset(x: crop.minX * width, y: crop.minY * height)

                    ForEach(CropHandle.allCases, id: \.self) { handle in
                        resizeHandle(handle, width: width, height: height)
                    }
                }
                .contentShape(Rectangle())
                .gesture(cropCanvasGesture(width: width, height: height))
                .frame(width: width, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Could not preview this file").foregroundStyle(Palette.muted)
            }
        }
        .padding(Layout.sm)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
    }

    private func preview(fitting available: CGSize) -> (image: NSImage, size: CGSize)? {
        let sourceImage: NSImage
        let sourceSize: CGSize
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            sourceSize = bounds.size
            sourceImage = page.thumbnail(
                of: CGSize(width: max(available.width * 2, 1), height: max(available.height * 2, 1)),
                for: .cropBox
            )
        } else {
            guard let image = NSImage(contentsOf: url) else { return nil }
            sourceImage = image
            sourceSize = image.size
        }
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(available.width / sourceSize.width, available.height / sourceSize.height)
        return (sourceImage, CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale))
    }

    private func resizeHandle(_ handle: CropHandle, width: CGFloat, height: CGFloat) -> some View {
        Circle()
            .fill(Palette.text)
            .frame(width: Layout.sm, height: Layout.sm)
            .overlay { Circle().stroke(Palette.accent, lineWidth: 2) }
            .frame(width: Layout.xl, height: Layout.xl)
            .contentShape(Circle())
            .position(handle.position(in: crop, width: width, height: height))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if resizeStartCrop == nil { resizeStartCrop = crop }
                        guard let resizeStartCrop else { return }
                        crop = resizedCrop(
                            resizeStartCrop,
                            using: handle,
                            deltaX: gesture.translation.width / width,
                            deltaY: gesture.translation.height / height
                        )
                    }
                    .onEnded { _ in resizeStartCrop = nil }
            )
    }

    private func cropCanvasGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                if moveStartCrop == nil && drawingStart == nil {
                    let start = normalizedPoint(gesture.startLocation, width: width, height: height)
                    if crop.contains(start) {
                        moveStartCrop = crop
                    } else {
                        drawingStart = start
                    }
                }

                if let moveStartCrop {
                    crop = movedCrop(
                        moveStartCrop,
                        deltaX: gesture.translation.width / width,
                        deltaY: gesture.translation.height / height
                    )
                } else if let drawingStart {
                    let current = normalizedPoint(gesture.location, width: width, height: height)
                    crop = CGRect(
                        x: min(drawingStart.x, current.x),
                        y: min(drawingStart.y, current.y),
                        width: max(abs(current.x - drawingStart.x), 0.01),
                        height: max(abs(current.y - drawingStart.y), 0.01)
                    )
                }
            }
            .onEnded { _ in
                moveStartCrop = nil
                drawingStart = nil
            }
    }

    private func normalizedPoint(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(point.x / width, 0), 1),
            y: min(max(point.y / height, 0), 1)
        )
    }

    private func resizedCrop(_ original: CGRect, using handle: CropHandle, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let minimumSize: CGFloat = 0.01
        var left = original.minX
        var top = original.minY
        var right = original.maxX
        var bottom = original.maxY

        if handle.movesLeft { left = min(max(original.minX + deltaX, 0), right - minimumSize) }
        if handle.movesRight { right = max(min(original.maxX + deltaX, 1), left + minimumSize) }
        if handle.movesTop { top = min(max(original.minY + deltaY, 0), bottom - minimumSize) }
        if handle.movesBottom { bottom = max(min(original.maxY + deltaY, 1), top + minimumSize) }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func movedCrop(_ original: CGRect, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        let x = min(max(original.minX + deltaX, 0), 1 - original.width)
        let y = min(max(original.minY + deltaY, 0), 1 - original.height)
        return CGRect(x: x, y: y, width: original.width, height: original.height)
    }
}

private enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    func position(in crop: CGRect, width: CGFloat, height: CGFloat) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .topLeft: x = crop.minX; y = crop.minY
        case .top: x = crop.midX; y = crop.minY
        case .topRight: x = crop.maxX; y = crop.minY
        case .right: x = crop.maxX; y = crop.midY
        case .bottomRight: x = crop.maxX; y = crop.maxY
        case .bottom: x = crop.midX; y = crop.maxY
        case .bottomLeft: x = crop.minX; y = crop.maxY
        case .left: x = crop.minX; y = crop.midY
        }
        return CGPoint(x: x * width, y: y * height)
    }
}
