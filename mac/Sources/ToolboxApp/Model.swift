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
    @Published var tools: [ToolSummary] = []
    @Published var selected: ToolDefinition?
    @Published var values: [String: String] = [:]
    @Published var files: [String: [URL]] = [:]
    @Published var crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @Published var duration: Double = 0
    @Published var waveform: [Double] = []
    @Published var waveformLoading = false
    @Published var running = false
    @Published var status = "Ready"
    @Published var result: URL?

    func load() async {
        do {
            let response = try await CLI.run(["list"])
            let data = try JSONSerialization.data(withJSONObject: response)
            tools = try JSONDecoder().decode([ToolSummary].self, from: data)
            if let first = tools.first { await select(first.id) }
        } catch { status = error.localizedDescription }
    }

    func select(_ id: String) async {
        do {
            let response = try await CLI.run(["describe", id])
            guard let object = response as? [String: Any] else { throw CLIError.invalidResponse }
            selected = ToolDefinition(object)
            values = [:]
            files = [:]
            result = nil
            duration = 0
            waveform = []
            waveformLoading = false
            crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            for field in selected?.fields ?? [] {
                if let fallback = field.defaultValue { values[field.name] = fallback }
                if field.kind == "time_range" { values[field.name + "_start"] = "0"; values[field.name + "_end"] = "0" }
            }
            status = "Ready"
        } catch { status = error.localizedDescription }
    }

    func chooseFiles(_ field: ToolField) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = field.kind == "files"
        if !field.extensions.isEmpty {
            panel.allowedContentTypes = field.extensions.compactMap { UTType(filenameExtension: $0) }
        }
        guard panel.runModal() == .OK else { return }
        files[field.name] = panel.urls
        result = nil
        status = "Ready"
        if field.kind == "file", let url = panel.urls.first {
            duration = 0
            waveform = []
            if ["mp3", "m4a", "wav"].contains(url.pathExtension.lowercased()) {
                waveformLoading = true
                Task { await inspect(url) }
            }
        }
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

    func inspect(_ url: URL) async {
        guard url.pathExtension.lowercased() == "mp3" || url.pathExtension.lowercased() == "m4a" || url.pathExtension.lowercased() == "wav" else { return }
        defer { waveformLoading = false }
        do {
            let response = try await CLI.run(["inspect", url.path, "--waveform"])
            guard files.values.contains(where: { $0.contains(url) }) else { return }
            let object = response as? [String: Any] ?? [:]
            duration = object["duration"] as? Double ?? 0
            waveform = object["waveform"] as? [Double] ?? []
            if let field = selected?.fields.first(where: { $0.kind == "time_range" }) {
                values[field.name + "_end"] = String(format: "%.2f", duration)
            }
        } catch { status = error.localizedDescription }
    }

    func execute() async {
        guard let tool = selected else { return }
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
}
