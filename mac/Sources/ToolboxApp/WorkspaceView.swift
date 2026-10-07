import AppKit
import PDFKit
import SwiftUI

private enum Palette {
    static let window = Color(red: 0.105, green: 0.111, blue: 0.122)
    static let sidebar = Color(red: 0.125, green: 0.132, blue: 0.145)
    static let panel = Color(red: 0.16, green: 0.17, blue: 0.185)
    static let stroke = Color.white.opacity(0.09)
    static let muted = Color.white.opacity(0.58)
    static let accent = Color(red: 0.52, green: 0.75, blue: 0.94)
}

struct WorkspaceView: View {
    @ObservedObject var store: ToolStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.stroke).frame(width: 1)
            mainArea
        }
        .background(Palette.window)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(Palette.accent)
                Text("Toolbox").font(.system(size: 17, weight: .semibold))
            }
            .padding(.top, 54)
            .padding(.horizontal, 20)
            Text("YOUR TOOLS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 12)
            ForEach(store.tools) { tool in
                Button { Task { await store.select(tool.id) } } label: {
                    HStack(spacing: 11) {
                        Image(systemName: icon(for: tool.id))
                            .font(.system(size: 14))
                            .frame(width: 18)
                        Text(tool.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(store.selected?.id == tool.id ? Color.white : Palette.muted)
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38)
                    .background(store.selected?.id == tool.id ? Palette.panel : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(Palette.accent).frame(width: 6, height: 6)
                Text("Local tools").font(.system(size: 11))
            }
            .foregroundStyle(Palette.muted)
            .padding(20)
        }
        .frame(width: 224)
        .background(Palette.sidebar)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
                Text(store.selected?.title ?? "Tools")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 30)
            .frame(height: 54)
            Rectangle().fill(Palette.stroke).frame(height: 1)
            if let tool = store.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tool.title).font(.system(size: 28, weight: .semibold))
                            Text(tool.description).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                        .padding(.top, 18)
                        ForEach(visibleFields(for: tool)) { field in
                            fieldView(field)
                        }
                        HStack {
                            Spacer()
                            Button { Task { await store.execute() } } label: {
                                HStack(spacing: 8) {
                                    if store.running { ProgressView().controlSize(.small) }
                                    else { Image(systemName: "play.fill").font(.system(size: 10)) }
                                    Text(store.running ? "Working…" : (tool.id == "trim-audio" ? "Trim audio" : "Run tool"))
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(minWidth: 116, minHeight: 32)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                            .disabled(store.running || !hasSelectedInputs(for: tool))
                        }
                    }
                    .frame(maxWidth: 710, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Spacer()
                Text(store.status).foregroundStyle(Palette.muted)
                Spacer()
            }
            resultBar
        }
    }

    private func hasSelectedInputs(for tool: ToolDefinition) -> Bool {
        tool.fields
            .filter { $0.required && ($0.kind == "file" || $0.kind == "files") }
            .allSatisfy { !(store.files[$0.name] ?? []).isEmpty }
    }

    private func visibleFields(for tool: ToolDefinition) -> [ToolField] {
        tool.fields.filter { field in
            if field.kind == "output" { return false }
            if field.kind == "file" || field.kind == "files" { return true }
            return hasSelectedInputs(for: tool)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: ToolField) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(field.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(Palette.muted)
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
        VStack(alignment: .leading, spacing: 8) {
            let selected = store.files[field.name] ?? []
            if selected.isEmpty {
                Text("No file selected")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            } else {
                ForEach(Array(selected.enumerated()), id: \.offset) { index, url in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill").foregroundStyle(Palette.accent)
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        if field.kind == "files" {
                            Button { move(field.name, index, -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0)
                            Button { move(field.name, index, 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == selected.count - 1)
                        }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            Button(field.kind == "files" ? "Choose images…" : "Choose file…") { store.chooseFiles(field) }
                .font(.system(size: 12))
            if field.kind == "file", selected.first?.pathExtension.lowercased() == "pdf",
               let url = selected.first {
                PDFCropPreview(url: url, crop: $store.crop)
                    .frame(height: 330)
            }
        }
    }

    private func cropField(_ field: ToolField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag on the PDF preview to select the area to keep. The same relative area applies to every page.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text(String(format: "x %.2f · y %.2f · width %.2f · height %.2f", store.crop.minX, store.crop.minY, store.crop.width, store.crop.height))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.muted)
        }
    }

    private func timeRangeField(_ field: ToolField) -> some View {
        let startKey = field.name + "_start"
        let endKey = field.name + "_end"
        return VStack(alignment: .leading, spacing: 12) {
            if let url = store.files.values.first?.first, store.duration > 0 {
                WaveformEditor(url: url, duration: store.duration, peaks: store.waveform,
                               start: numericBinding(startKey), end: numericBinding(endKey))
                    .id(url.path)
            } else {
                Text(store.waveformLoading ? "Loading waveform…" : "Waveform unavailable for this file")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var resultBar: some View {
        HStack(spacing: 10) {
            Image(systemName: store.result == nil ? "circle.dotted" : "checkmark.circle.fill")
                .foregroundStyle(store.result == nil ? Palette.muted : Palette.accent)
            Text(store.status).font(.system(size: 12)).lineLimit(2)
            Spacer()
            if let result = store.result {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                Button("Open") { NSWorkspace.shared.open(result) }
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 56)
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
        if id.contains("audio") { return "waveform" }
        if id.contains("image") { return "photo" }
        return "square.grid.2x2"
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, remainder)
    }
}

private struct PDFCropPreview: View {
    let url: URL
    @Binding var crop: CGRect

    private var page: PDFPage? { PDFDocument(url: url)?.page(at: 0) }

    var body: some View {
        GeometryReader { geometry in
            if let page {
                let bounds = page.bounds(for: .cropBox)
                let scale = min(geometry.size.width / max(bounds.width, 1), geometry.size.height / max(bounds.height, 1))
                let width = bounds.width * scale
                let height = bounds.height * scale
                let thumbnail = page.thumbnail(of: CGSize(width: max(width * 2, 1), height: max(height * 2, 1)), for: .cropBox)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .frame(width: width, height: height)
                    Rectangle()
                        .fill(Palette.accent.opacity(0.12))
                        .stroke(Palette.accent, lineWidth: 2)
                        .frame(width: crop.width * width, height: crop.height * height)
                        .offset(x: crop.minX * width, y: crop.minY * height)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1).onChanged { gesture in
                            let x1 = min(max(gesture.startLocation.x / width, 0), 1)
                            let y1 = min(max(gesture.startLocation.y / height, 0), 1)
                            let x2 = min(max(gesture.location.x / width, 0), 1)
                            let y2 = min(max(gesture.location.y / height, 0), 1)
                            crop = CGRect(x: min(x1, x2), y: min(y1, y2),
                                          width: max(abs(x2 - x1), 0.01), height: max(abs(y2 - y1), 0.01))
                        })
                }
                .frame(width: width, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Could not preview this PDF").foregroundStyle(Palette.muted)
            }
        }
        .padding(10)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
    }
}
