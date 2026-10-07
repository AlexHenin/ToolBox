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

    private let gold = Color(red: 0.98, green: 0.76, blue: 0.29)
    private let blue = Color(red: 0.35, green: 0.68, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WAVEFORM")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.56))
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(timeLabel(duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
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
            .foregroundStyle(.white.opacity(0.45))
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SELECTION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(timeLabel(max(end - start, 0)))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(timeLabel(playback.position))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
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
            HStack(spacing: 16) {
                labeledTime("START", value: $start)
                labeledTime("END", value: $end)
                Spacer()
                Text("Drag the yellow handles to set the trim range")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(18)
        .background(Color(red: 0.16, green: 0.17, blue: 0.185), in: RoundedRectangle(cornerRadius: 10))
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
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.55))
                Rectangle()
                    .fill(gold.opacity(0.13))
                    .frame(width: max(right - left, 0), height: height)
                    .offset(x: left)
                    .allowsHitTesting(false)
                WaveformBars(peaks: peaks, selection: startFraction...endFraction,
                             selectedColor: gold.opacity(0.95), otherColor: .white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(blue)
                    .frame(width: 2, height: height)
                    .offset(x: CGFloat(clamp(playback.position / max(duration, 0.001))) * width)
                    .allowsHitTesting(false)
                handle(at: left, height: height, width: width, isStart: true)
                handle(at: right, height: height, width: width, isStart: false)
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

    private func handle(at x: CGFloat, height: CGFloat, width: CGFloat, isStart: Bool) -> some View {
        ZStack {
            Rectangle().fill(gold).frame(width: 4, height: height)
            VStack {
                Circle().fill(gold).frame(width: 9, height: 9)
                Spacer()
                Circle().fill(gold).frame(width: 9, height: 9)
            }
        }
        .frame(width: 24, height: height)
        .position(x: min(max(x, 12), width - 12), y: height / 2)
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
                RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.42))
                WaveformBars(peaks: peaks, selection: 0...1,
                             selectedColor: .white.opacity(0.45), otherColor: .white.opacity(0.45))
                    .padding(.vertical, 7)
                Rectangle().fill(gold.opacity(0.2))
                    .frame(width: max(right - left, 0), height: geometry.size.height)
                    .offset(x: left)
                Rectangle().fill(gold).frame(width: 4).offset(x: left)
                Rectangle().fill(gold).frame(width: 4).offset(x: right - 4)
                Rectangle().fill(blue).frame(width: 2)
                    .offset(x: CGFloat(clamp(playback.position / max(duration, 0.001))) * width)
            }
        }
    }

    private func labeledTime(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
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

private struct WaveformBars: View {
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
