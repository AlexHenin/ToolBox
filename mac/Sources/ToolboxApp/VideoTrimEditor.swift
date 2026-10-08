import AppKit
import AVFoundation
import AVKit
import SwiftUI

@MainActor
private final class VideoPlayback: ObservableObject {
    let player: AVPlayer
    @Published var position: Double = 0
    @Published var isPlaying = false
    private var timer: Timer?
    private var selectionEnd: Double = .greatestFiniteMagnitude

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func startMonitoring(end: Double) {
        selectionEnd = end
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let currentTime = self.player.currentTime().seconds
                self.position = currentTime.isFinite ? currentTime : 0
                self.isPlaying = self.player.rate != 0
                if self.position >= self.selectionEnd, self.player.rate != 0 {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }

    func updateSelection(end: Double) {
        selectionEnd = end
    }

    func seek(_ seconds: Double) {
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func toggle(start: Double, end: Double) {
        selectionEnd = end
        if player.rate != 0 {
            player.pause()
            isPlaying = false
            return
        }
        if position < start || position >= end { seek(start) }
        player.play()
        isPlaying = true
    }

    func stop() {
        player.pause()
        timer?.invalidate()
        timer = nil
    }
}

struct VideoTrimEditor: View {
    let url: URL
    let duration: Double
    let peaks: [Double]
    @Binding var start: Double
    @Binding var end: Double
    @StateObject private var playback: VideoPlayback
    @State private var thumbnails: [CGImage] = []
    @State private var draggingStart: Bool?

    init(url: URL, duration: Double, peaks: [Double], start: Binding<Double>, end: Binding<Double>) {
        self.url = url
        self.duration = duration
        self.peaks = peaks
        _start = start
        _end = end
        _playback = StateObject(wrappedValue: VideoPlayback(url: url))
    }

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

            VStack(spacing: 0) {
                AVPlayerContainer(player: playback.player)
                    .frame(height: 290)
                    .background(Color.black)
                HStack(spacing: Layout.md) {
                    Button {
                        playback.toggle(start: start, end: end)
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: Layout.lg)
                    }
                    .buttonStyle(.plain)
                    Slider(
                        value: Binding(get: { playback.position }, set: { playback.seek($0) }),
                        in: 0...max(duration, 0.01)
                    )
                    Text(timeLabel(playback.position))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.horizontal, Layout.md)
                .frame(height: 40)
                .background(Palette.overlayStrong)
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.sm))

            VStack(spacing: 2) {
                frameStrip
                    .frame(height: 76)
                compactWaveform
                    .frame(height: 52)
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.sm))

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
                labeledTime("START", value: $start)
                labeledTime("END", value: $end)
            }
        }
        .padding(Layout.lg)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .task(id: url) { await loadThumbnails() }
        .onAppear { playback.startMonitoring(end: end) }
        .onChange(of: end) { _, value in playback.updateSelection(end: value) }
        .onDisappear { playback.stop() }
    }

    private var frameStrip: some View {
        GeometryReader { geometry in
            let count = max(thumbnails.count, 1)
            HStack(spacing: 2) {
                if thumbnails.isEmpty {
                    ForEach(0..<10, id: \.self) { _ in
                        Rectangle().fill(Palette.overlayStrong)
                    }
                } else {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: max((geometry.size.width - CGFloat(count - 1) * 2) / CGFloat(count), 1),
                                   height: geometry.size.height)
                            .clipped()
                    }
                }
            }
        }
    }

    private var compactWaveform: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            let startFraction = clamp(start / max(duration, 0.001))
            let endFraction = max(startFraction, clamp(end / max(duration, 0.001)))
            let left = CGFloat(startFraction) * width
            let right = CGFloat(endFraction) * width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.overlayStrong)
                Rectangle()
                    .fill(Palette.audioSelectionFill)
                    .frame(width: max(right - left, 0), height: height)
                    .offset(x: left)
                WaveformBars(peaks: peaks, selection: startFraction...endFraction,
                             selectedColor: Palette.audioSelectionActive, otherColor: Palette.quiet)
                    .padding(.vertical, Layout.sm)
                    .allowsHitTesting(false)
                Rectangle().fill(Palette.audioPlayhead).frame(width: 2, height: height)
                    .offset(x: CGFloat(clamp(playback.position / max(duration, 0.001))) * width)
                    .allowsHitTesting(false)
                trimHandle(at: left, height: height, isStart: true)
                trimHandle(at: right, height: height, isStart: false)
            }
            .coordinateSpace(name: "video-timeline")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("video-timeline"))
                    .onChanged { value in
                        if draggingStart == nil {
                            draggingStart = abs(value.startLocation.x - left) <= abs(value.startLocation.x - right)
                        }
                        let selected = clamp(Double(value.location.x / width)) * duration
                        if draggingStart == true { start = max(0, min(selected, end - 0.01)) }
                        else { end = min(duration, max(selected, start + 0.01)) }
                        playback.seek(selected)
                    }
                    .onEnded { _ in draggingStart = nil }
            )
        }
    }

    private func trimHandle(at x: CGFloat, height: CGFloat, isStart: Bool) -> some View {
        Rectangle()
            .fill(Palette.audioSelection)
            .frame(width: 4, height: height)
            .position(x: isStart ? x + 2 : x - 2, y: height / 2)
            .allowsHitTesting(false)
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

    private func loadThumbnails() async {
        let source = url
        let clipDuration = duration
        thumbnails = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: source)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 140)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
            return (0..<10).compactMap { index in
                let seconds = clipDuration * (Double(index) + 0.5) / 10
                return try? generator.copyCGImage(
                    at: CMTime(seconds: seconds, preferredTimescale: 600),
                    actualTime: nil
                )
            }
        }.value
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private func timeLabel(_ seconds: Double) -> String {
        let safe = max(seconds, 0)
        return String(format: "%d:%05.2f", Int(safe) / 60, safe.truncatingRemainder(dividingBy: 60))
    }
}

private struct AVPlayerContainer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
