import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct ToolSummary: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
}

struct ToolField: Identifiable {
    let name: String
    let label: String
    let kind: String
    let required: Bool
    let extensions: [String]
    let choices: [String]
    let defaultValue: String?
    var id: String { name }

    init(_ object: [String: Any]) {
        name = object["name"] as? String ?? ""
        label = object["label"] as? String ?? name
        kind = object["kind"] as? String ?? "text"
        required = object["required"] as? Bool ?? true
        extensions = object["extensions"] as? [String] ?? []
        choices = object["choices"] as? [String] ?? []
        if let value = object["default"] { defaultValue = String(describing: value) }
        else { defaultValue = nil }
    }
}

struct ToolDefinition {
    let id: String
    let title: String
    let description: String
    let fields: [ToolField]

    init(_ object: [String: Any]) {
        id = object["id"] as? String ?? ""
        title = object["title"] as? String ?? ""
        description = object["description"] as? String ?? ""
        fields = (object["fields"] as? [[String: Any]] ?? []).map(ToolField.init)
    }
}

enum CLIError: LocalizedError {
    case missing
    case failed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missing: "Python tools are not installed. Run ./setup.sh in the Toolbox folder."
        case .failed(let message): message
        case .invalidResponse: "The Python tool returned an unreadable response."
        }
    }
}

enum CLI {
    static func executable() -> URL? {
        if let path = ProcessInfo.processInfo.environment["TOOLBOX_CLI"],
           FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        var folder = Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = folder.appendingPathComponent(".venv/bin/toolbox")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".venv/bin/toolbox")
        return FileManager.default.isExecutableFile(atPath: local.path) ? local : nil
    }

    static func run(_ arguments: [String]) async throws -> Any {
        guard let executable = executable() else { throw CLIError.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments + ["--json"]
                var environment = ProcessInfo.processInfo.environment
                environment.removeValue(forKey: "PYTHONHOME")
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
                environment["PYTHONPATH"] = executable.deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("python").path
                process.environment = environment
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    guard let result = try? JSONSerialization.jsonObject(with: data) else {
                        let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: CLIError.failed(message?.isEmpty == false ? message! : "Tool exited without a result."))
                        return
                    }
                    if process.terminationStatus != 0 {
                        let message = (result as? [String: Any])?["error"] as? String ?? "Tool failed."
                        continuation.resume(throwing: CLIError.failed(message))
                    } else {
                        continuation.resume(returning: result)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
final class ToolStore: ObservableObject {
    private struct WorkspaceState {
        var values: [String: String]
        var files: [String: [URL]]
        var crop: CGRect
        var duration: Double
        var waveform: [Double]
        var mediaKind: String
        var conversionTargets: [String]
        var status: String
        var result: URL?
    }

    @Published var tools: [ToolSummary] = []
    @Published var selected: ToolDefinition?
    @Published var values: [String: String] = [:]
    @Published var files: [String: [URL]] = [:]
    @Published var crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @Published var duration: Double = 0
    @Published var waveform: [Double] = []
    @Published var waveformLoading = false
    @Published var mediaKind = ""
    @Published var conversionTargets: [String] = []
    @Published var conversionTargetsLoading = false
    @Published var running = false
    @Published private(set) var isLoading = true
    @Published var status = "Ready"
    @Published var result: URL?
    private var definitions: [String: ToolDefinition] = [:]
    private var workspaceStates: [String: WorkspaceState] = [:]
    private var mediaInspectionURL: URL?

    func load() async {
        defer { isLoading = false }
        do {
            let response = try await CLI.run(["bootstrap"])
            guard let object = response as? [String: Any],
                  let list = object["tools"] else { throw CLIError.invalidResponse }
            let data = try JSONSerialization.data(withJSONObject: list)
            tools = try JSONDecoder().decode([ToolSummary].self, from: data)
            if let initialTool = object["initial_tool"] as? [String: Any] {
                let definition = ToolDefinition(initialTool)
                definitions[definition.id] = definition
                applySelection(definition)
            }
        } catch { status = error.localizedDescription }
    }

    func select(_ id: String) async {
        guard selected?.id != id else { return }
        saveCurrentWorkspace()
        if let definition = definitions[id] {
            applySelection(definition)
            return
        }
        do {
            let response = try await CLI.run(["describe", id])
            guard let object = response as? [String: Any] else { throw CLIError.invalidResponse }
            let definition = ToolDefinition(object)
            definitions[definition.id] = definition
            applySelection(definition)
        } catch { status = error.localizedDescription }
    }

    private func saveCurrentWorkspace() {
        guard let id = selected?.id else { return }
        workspaceStates[id] = WorkspaceState(
            values: values,
            files: files,
            crop: crop,
            duration: duration,
            waveform: waveform,
            mediaKind: mediaKind,
            conversionTargets: conversionTargets,
            status: status,
            result: result
        )
    }

    private func applySelection(_ definition: ToolDefinition) {
        selected = definition
        if let saved = workspaceStates[definition.id] {
            values = saved.values
            files = saved.files
            crop = saved.crop
            duration = saved.duration
            waveform = saved.waveform
            waveformLoading = false
            mediaKind = saved.mediaKind
            conversionTargets = saved.conversionTargets
            conversionTargetsLoading = false
            status = saved.status
            result = saved.result
            mediaInspectionURL = nil
            if definition.id == "trim", duration <= 0,
               let field = definition.fields.first(where: { $0.kind == "file" }) {
                startMediaInspection(for: field)
            }
            return
        }
        values = [:]
        files = [:]
        result = nil
        duration = 0
        waveform = []
        waveformLoading = false
        mediaKind = ""
        conversionTargets = []
        conversionTargetsLoading = false
        mediaInspectionURL = nil
        crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        for field in selected?.fields ?? [] {
            if let fallback = field.defaultValue { values[field.name] = fallback }
            if field.kind == "time_range" { values[field.name + "_start"] = "0"; values[field.name + "_end"] = "0" }
        }
        status = "Ready"
    }

    func chooseFiles(_ field: ToolField, appending: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = field.kind == "files"
        if !field.extensions.isEmpty {
            panel.allowedContentTypes = field.extensions.compactMap { UTType(filenameExtension: $0) }
        }
        guard panel.runModal() == .OK else { return }
        let current = appending ? (files[field.name] ?? []) : []
        files[field.name] = current + panel.urls.filter { url in !current.contains(url) }
        inputFilesDidChange(field)
    }

    func importDroppedFiles(_ urls: [URL]) {
        guard let tool = selected else { return }
        let inputs = tool.fields.filter { $0.kind == "file" || $0.kind == "files" }
        guard let field = inputs.first(where: { field in
            urls.contains { accepts($0, for: field) }
        }) else {
            status = "These files are not supported by \(tool.title)."
            return
        }

        let accepted = urls.filter { accepts($0, for: field) }
        guard !accepted.isEmpty else { return }
        let imported: [URL]
        if field.kind == "files" {
            let current = files[field.name] ?? []
            imported = current + accepted.filter { !current.contains($0) }
        } else {
            imported = [accepted[0]]
        }
        files[field.name] = imported
        inputFilesDidChange(field)
    }

    func removeFile(_ url: URL, from fieldName: String) {
        guard var current = files[fieldName] else { return }
        current.removeAll { $0 == url }
        files[fieldName] = current
        result = nil
        status = "Ready"
        if selected?.id == "trim" {
            resetMediaInspection()
            resetTrimRange()
        } else if selected?.id == "crop" {
            crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        }
        if selected?.id == "convert-files" { Task { await reloadConversionTargets() } }
    }

    private func inputFilesDidChange(_ field: ToolField) {
        result = nil
        status = "Ready"
        if selected?.id == "trim", field.kind == "file" {
            resetMediaInspection()
            resetTrimRange()
            startMediaInspection(for: field)
        }
        if selected?.id == "convert-files" { Task { await reloadConversionTargets() } }
    }

    private func startMediaInspection(for field: ToolField) {
        guard let url = files[field.name]?.first else { return }
        waveformLoading = true
        mediaInspectionURL = url
        Task { await inspect(url, fieldName: field.name) }
    }

    private func resetMediaInspection() {
        mediaInspectionURL = nil
        duration = 0
        waveform = []
        waveformLoading = false
        mediaKind = ""
    }

    private func resetTrimRange() {
        guard let range = selected?.fields.first(where: { $0.kind == "time_range" }) else { return }
        values[range.name + "_start"] = "0"
        values[range.name + "_end"] = "0"
    }

    func moveFile(_ url: URL, toInsertionIndex rawDestination: Int, in fieldName: String) {
        guard var current = files[fieldName],
              let sourceIndex = current.firstIndex(of: url) else { return }
        let file = current.remove(at: sourceIndex)
        var destination = rawDestination
        if sourceIndex < rawDestination { destination -= 1 }
        destination = max(0, min(destination, current.count))
        current.insert(file, at: destination)
        files[fieldName] = current
        result = nil
        status = "Ready"
    }

    func reloadConversionTargets() async {
        guard selected?.id == "convert-files",
              let field = selected?.fields.first(where: { $0.kind == "files" }) else { return }
        let selectedFiles = files[field.name] ?? []
        guard !selectedFiles.isEmpty else {
            conversionTargets = []
            conversionTargetsLoading = false
            values["target"] = ""
            return
        }
        conversionTargetsLoading = true
        defer { conversionTargetsLoading = false }
        do {
            let response = try await CLI.run(["conversion-targets"] + selectedFiles.map(\.path))
            guard files[field.name] == selectedFiles else { return }
            conversionTargets = response as? [String] ?? []
            if !conversionTargets.contains(values["target"] ?? "") {
                values["target"] = conversionTargets.first ?? ""
            }
            if conversionTargets.isEmpty {
                status = "The selected files do not share a conversion format."
            } else if status != "Ready" {
                status = "Ready"
            }
        } catch {
            conversionTargets = []
            values["target"] = ""
            status = error.localizedDescription
        }
    }

    private func accepts(_ url: URL, for field: ToolField) -> Bool {
        !url.hasDirectoryPath && (field.extensions.isEmpty || field.extensions.contains(url.pathExtension.lowercased()))
    }

    func chooseOutput(_ field: ToolField) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName(for: field)
        if !field.extensions.isEmpty {
            panel.allowedContentTypes = field.extensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func suggestedName(for field: ToolField) -> String {
        let first = files.values.first?.first
        let source = first?.deletingPathExtension().lastPathComponent ?? "result"
        let inputSuffix = first?.pathExtension.lowercased() ?? ""
        let suffix = field.extensions.contains(inputSuffix) ? inputSuffix : (field.extensions.first ?? "pdf")
        return "\(source)-\(selected?.id ?? "output").\(suffix)"
    }

    private func inspect(_ url: URL, fieldName: String) async {
        defer {
            if mediaInspectionURL == url {
                waveformLoading = false
                mediaInspectionURL = nil
            }
        }
        do {
            let response = try await CLI.run(["inspect", url.path, "--waveform"])
            guard selected?.id == "trim",
                  mediaInspectionURL == url,
                  files[fieldName]?.contains(url) == true else { return }
            let object = response as? [String: Any] ?? [:]
            duration = object["duration"] as? Double ?? 0
            mediaKind = object["kind"] as? String ?? ""
            waveform = object["waveform"] as? [Double] ?? []
            if let field = selected?.fields.first(where: { $0.kind == "time_range" }) {
                values[field.name + "_end"] = String(format: "%.2f", duration)
            }
        } catch {
            guard mediaInspectionURL == url else { return }
            status = error.localizedDescription
        }
    }

    func execute() async {
        guard let tool = selected else { return }
        if tool.id == "convert-files" {
            await executeConversion(tool)
            return
        }
        guard let outputField = tool.fields.first(where: { $0.kind == "output" }),
              let destination = chooseOutput(outputField) else { return }
        var arguments = ["run", tool.id]
        for field in tool.fields {
            let flag = "--" + field.name.replacingOccurrences(of: "_", with: "-")
            arguments.append(flag)
            switch field.kind {
            case "file", "files":
                let chosen = files[field.name] ?? []
                if chosen.isEmpty { status = "Choose \(field.label.lowercased())."; return }
                arguments.append(contentsOf: chosen.map(\.path))
            case "output": arguments.append(destination.path)
            case "rectangle":
                arguments.append("\(crop.minX),\(crop.minY),\(crop.width),\(crop.height)")
            case "time_range":
                arguments.append("\(values[field.name + "_start"] ?? "0"),\(values[field.name + "_end"] ?? "0")")
            default:
                let value = values[field.name] ?? ""
                if value.isEmpty && field.required { status = "Enter \(field.label.lowercased())."; return }
                arguments.append(value)
            }
        }
        running = true
        status = "Running \(tool.title)…"
        result = nil
        do {
            let response = try await CLI.run(arguments)
            guard let path = (response as? [String: Any])?["output"] as? String else { throw CLIError.invalidResponse }
            result = URL(fileURLWithPath: path)
            status = "Done"
        } catch { status = error.localizedDescription }
        running = false
    }

    private func executeConversion(_ tool: ToolDefinition) async {
        guard let filesField = tool.fields.first(where: { $0.kind == "files" }) else { return }
        let selectedFiles = files[filesField.name] ?? []
        guard !selectedFiles.isEmpty else { return }
        let target = values["target"] ?? ""
        guard !target.isEmpty else {
            status = "Choose an output format."
            return
        }
        guard let destination = chooseConversionDestination(files: selectedFiles, target: target) else { return }

        var arguments = ["run", tool.id, "--files"]
        arguments.append(contentsOf: selectedFiles.map(\.path))
        arguments.append(contentsOf: ["--target", target, "--output", destination.path])
        running = true
        status = "Converting…"
        result = nil
        do {
            let response = try await CLI.run(arguments)
            guard let path = (response as? [String: Any])?["output"] as? String else { throw CLIError.invalidResponse }
            result = URL(fileURLWithPath: path)
            status = "Done"
        } catch { status = error.localizedDescription }
        running = false
    }

    private func chooseConversionDestination(files: [URL], target: String) -> URL? {
        let imageExtensions: Set<String> = [
            "avif", "bmp", "exr", "gif", "heic", "heif", "ico", "jfif", "jpeg", "jpg",
            "pbm", "pgm", "png", "pnm", "ppm", "qoi", "svg", "tga", "tif", "tiff", "webp"
        ]
        if target == "pdf" && files.allSatisfy({ imageExtensions.contains($0.pathExtension.lowercased()) }) {
            let panel = NSSavePanel()
            let stem = files.first?.deletingPathExtension().lastPathComponent ?? "converted"
            panel.nameFieldStringValue = files.count == 1 ? "\(stem).pdf" : "combined.pdf"
            panel.allowedContentTypes = [.pdf]
            return panel.runModal() == .OK ? panel.url : nil
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
