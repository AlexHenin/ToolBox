import AVFoundation
import SwiftUI

@MainActor
private final class AudioPlayback: ObservableObject {
    @Published var position: Double = 0
    @Published var isPlaying = false
    private var player: AVAudioPlayer?
    private var source: URL?
    private var timer: Timer?

    func toggle(source: URL, start: Double, end: Double) {
        if isPlaying {
            player?.pause()
            timer?.invalidate()
            isPlaying = false
            return
        }
        if self.source != source || player == nil {
            player = try? AVAudioPlayer(contentsOf: source)
            self.source = source
            position = start
        }
        guard let player else { return }
        if position < start || position >= end { position = start }
        player.currentTime = position
        isPlaying = player.play()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
                if self.position >= end || !player.isPlaying {
                    player.pause()
                    self.timer?.invalidate()
                    self.isPlaying = false
                }
            }
        }
    }

    func seek(_ seconds: Double) {
        position = seconds
        player?.currentTime = seconds
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        isPlaying = false
    }
}

struct WaveformEditor: View {
    let url: URL
    let duration: Double
    let peaks: [Double]
    @Binding var start: Double
    @Binding var end: Double
    @StateObject private var playback = AudioPlayback()
    @State private var draggingStart: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.lg) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(timeLabel(duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            mainWaveform
                .frame(height: 188)
            HStack {
                Text("0:00")
                Spacer()
                Text(timeLabel(duration / 4))
                Spacer()
                Text(timeLabel(duration / 2))
                Spacer()
                Text(timeLabel(duration * 3 / 4))
                Spacer()
                Text(timeLabel(duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.quiet)
            HStack(alignment: .center, spacing: Layout.lg) {
                VStack(alignment: .leading, spacing: Layout.xs) {
                    Text("SELECTION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Palette.subdued)
                    Text(timeLabel(max(end - start, 0)))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(timeLabel(playback.position))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                Button {
                    playback.toggle(source: url, start: start, end: end)
                } label: {
                    Label(playback.isPlaying ? "Pause" : "Play selection",
                          systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minWidth: 105)
                }
                .buttonStyle(.bordered)
                .disabled(start < 0 || end > duration || start >= end)
            }
            overview
                .frame(height: 48)
            HStack(spacing: Layout.lg) {
                labeledTime("START", value: $start)
                labeledTime("END", value: $end)
                Spacer()
                Text("Drag the yellow handles to set the trim range")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.subdued)
            }
        }
        .padding(Layout.lg)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .onDisappear { playback.stop() }
    }

    private var mainWaveform: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            let startFraction = clamp(start / max(duration, 0.001))
            let endFraction = max(startFraction, clamp(end / max(duration, 0.001)))
            let left = CGFloat(startFraction) * width
            let right = CGFloat(endFraction) * width
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Palette.overlayStrong)
                Rectangle()
                    .fill(Palette.audioSelectionFill)
                    .frame(width: max(right - left, 0), height: height)
                    .offset(x: left)
                    .allowsHitTesting(false)
                WaveformBars(peaks: peaks, selection: startFraction...endFraction,
                             selectedColor: Palette.audioSelectionActive, otherColor: Palette.quiet)
                    .padding(.vertical, Layout.lg)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(Palette.audioPlayhead)
                    .frame(width: 2, height: height)
                    .offset(x: CGFloat(clamp(playback.position / max(duration, 0.001))) * width)
                    .allowsHitTesting(false)
                handle(at: left, height: height, isStart: true)
                handle(at: right, height: height, isStart: false)
            }
            .coordinateSpace(name: "waveform")
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("waveform"))
                .onChanged { value in
                    if draggingStart == nil {
                        draggingStart = abs(value.startLocation.x - left) <= abs(value.startLocation.x - right)
                    }
                    let selected = clamp(Double(value.location.x / width)) * duration
                    if draggingStart == true { start = max(0, min(selected, end - 0.01)) }
                    else { end = min(duration, max(selected, start + 0.01)) }
                    if playback.isPlaying { playback.stop() }
                }
                .onEnded { _ in draggingStart = nil })
        }
    }

    private func handle(at x: CGFloat, height: CGFloat, isStart: Bool) -> some View {
        let handleWidth: CGFloat = Layout.md
        let armLength: CGFloat = Layout.sm
        let path = Path { path in
            if isStart {
                path.move(to: CGPoint(x: armLength, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: armLength, y: height))
            } else {
                path.move(to: CGPoint(x: handleWidth - armLength, y: 0))
                path.addLine(to: CGPoint(x: handleWidth, y: 0))
                path.addLine(to: CGPoint(x: handleWidth, y: height))
                path.addLine(to: CGPoint(x: handleWidth - armLength, y: height))
            }
        }

        return path
            .stroke(Palette.audioSelection, style: StrokeStyle(lineWidth: Layout.xs, lineCap: .round, lineJoin: .round))
            .frame(width: handleWidth, height: height)
            .position(x: isStart ? x + handleWidth / 2 : x - handleWidth / 2, y: height / 2)
        .allowsHitTesting(false)
        .accessibilityLabel(isStart ? "Trim start handle" : "Trim end handle")
    }

    private var overview: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startFraction = clamp(start / max(duration, 0.001))
            let endFraction = max(startFraction, clamp(end / max(duration, 0.001)))
            let left = CGFloat(startFraction) * width
            let right = CGFloat(endFraction) * width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(Palette.overlaySubtle)
                WaveformBars(peaks: peaks, selection: 0...1,
                             selectedColor: Palette.quiet, otherColor: Palette.quiet)
                    .padding(.vertical, Layout.sm)
                Rectangle().fill(Palette.audioSelectionOverview)
                    .frame(width: max(right - left, 0), height: geometry.size.height)
                    .offset(x: left)
                Rectangle().fill(Palette.audioSelection).frame(width: 4).offset(x: left)
                Rectangle().fill(Palette.audioSelection).frame(width: 4).offset(x: right - 4)
                Rectangle().fill(Palette.audioPlayhead).frame(width: 2)
                    .offset(x: CGFloat(clamp(playback.position / max(duration, 0.001))) * width)
            }
        }
    }

    private func labeledTime(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: Layout.xs) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.subdued)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 95)
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private func timeLabel(_ seconds: Double) -> String {
        let safe = max(seconds, 0)
        return String(format: "%d:%05.2f", Int(safe) / 60, safe.truncatingRemainder(dividingBy: 60))
    }
}

struct WaveformBars: View {
    let peaks: [Double]
    let selection: ClosedRange<Double>
    let selectedColor: Color
    let otherColor: Color

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let stride = size.width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let amplitude = max(CGFloat(peak) * size.height * 0.9, 3)
                let center = (CGFloat(index) + 0.5) * stride
                let rectangle = CGRect(x: center - min(stride * 0.28, 1.5),
                                       y: (size.height - amplitude) / 2,
                                       width: max(min(stride * 0.56, 3), 1), height: amplitude)
                let fraction = Double(index) / Double(peaks.count)
                context.fill(Path(roundedRect: rectangle, cornerRadius: 1),
                             with: .color(selection.contains(fraction) ? selectedColor : otherColor))
            }
        }
    }
}
