import json
import shutil
import subprocess
from array import array
from pathlib import Path

from toolbox import TimeRange, tool
from toolbox.files import atomic_output, check_output, check_source


AUDIO_EXTENSIONS = {
    ".aa", ".aac", ".aax", ".ac3", ".aif", ".aifc", ".aiff", ".alac", ".amr",
    ".ape", ".au", ".caf", ".dts", ".eac3", ".flac", ".gsm", ".m4a", ".m4b",
    ".mka", ".mp2", ".mp3", ".mpc", ".oga", ".ogg", ".opus", ".ra", ".shn",
    ".spx", ".tta", ".voc", ".wav", ".wave", ".wma", ".wv",
}

VIDEO_EXTENSIONS = {
    ".3g2", ".3gp", ".amv", ".asf", ".avi", ".divx", ".dv", ".f4v", ".flv",
    ".gif", ".gxf", ".m2ts", ".m2v", ".m4v", ".mkv", ".mov", ".mp4", ".mpeg",
    ".mpg", ".mts", ".mxf", ".nut", ".ogv", ".qt", ".rm", ".rmvb", ".roq",
    ".swf", ".ts", ".vob", ".webm", ".wmv", ".y4m",
}

MEDIA_EXTENSIONS = AUDIO_EXTENSIONS | VIDEO_EXTENSIONS


def _executable(name: str) -> str:
    executable = shutil.which(name)
    if executable is None:
        raise RuntimeError("FFmpeg is missing. Install it with: brew install ffmpeg")
    return executable


def media_info(source: Path) -> dict[str, object]:
    process = subprocess.run(
        [
            _executable("ffprobe"), "-v", "error",
            "-show_entries", "format=duration:stream=codec_type,duration",
            "-of", "json", str(source),
        ],
        capture_output=True, text=True, check=False,
    )
    if process.returncode:
        raise ValueError(process.stderr.strip() or "Could not read media information")
    try:
        payload = json.loads(process.stdout)
        streams = payload.get("streams", [])
        stream_types = {stream.get("codec_type") for stream in streams}
        candidates = [payload.get("format", {}).get("duration")]
        candidates.extend(stream.get("duration") for stream in streams)
        duration = max(float(value) for value in candidates if value not in (None, "N/A"))
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("Could not read media duration") from error
    if duration <= 0:
        raise ValueError("Media duration must be greater than zero")
    return {
        "kind": "video" if "video" in stream_types else "audio",
        "duration": duration,
        "has_audio": "audio" in stream_types,
    }


def media_waveform(source: Path, duration: float, has_audio: bool, bins: int = 320) -> list[float]:
    """Decode the first audio stream into display peaks, or return silence when absent."""
    if not has_audio:
        return [0.0] * bins
    process = subprocess.Popen(
        [
            _executable("ffmpeg"), "-hide_banner", "-loglevel", "error", "-i", str(source),
            "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "2000", "-f", "s16le", "-",
        ],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    peaks = [0.0] * bins
    total_samples = max(int(duration * 2000), 1)
    position = 0
    carry = b""
    assert process.stdout is not None
    while chunk := process.stdout.read(8192):
        data = carry + chunk
        even_length = len(data) - len(data) % 2
        carry = data[even_length:]
        samples = array("h")
        samples.frombytes(data[:even_length])
        for sample in samples:
            index = min(position * bins // total_samples, bins - 1)
            peaks[index] = max(peaks[index], abs(sample) / 32768)
            position += 1
    process.stdout.close()
    stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr else ""
    if process.stderr:
        process.stderr.close()
    if process.wait() != 0:
        raise ValueError(stderr.strip() or "Could not build media waveform")
    return [round(value ** 0.5, 4) for value in peaks]


@tool(
    title="Trim",
    description="Export a selected segment from an audio or video file.",
    extensions={
        "source": sorted(extension.removeprefix(".") for extension in MEDIA_EXTENSIONS),
        "output": sorted(extension.removeprefix(".") for extension in MEDIA_EXTENSIONS),
    },
)
def trim(source: Path, segment: TimeRange, output: Path) -> Path:
    source = check_source(source, MEDIA_EXTENSIONS)
    output = check_output(output, [source], MEDIA_EXTENSIONS)
    if output.suffix.lower() != source.suffix.lower():
        raise ValueError(f"Trimmed output must keep the {source.suffix.lower()} format")
    duration = float(media_info(source)["duration"])
    if not (0 <= segment.start < segment.end <= duration + 0.05):
        raise ValueError(f"Choose a range within 0–{duration:.2f} seconds")
    with atomic_output(output) as temporary:
        process = subprocess.run(
            [
                _executable("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y",
                "-ss", str(segment.start), "-i", str(source),
                "-t", str(segment.end - segment.start),
                "-map", "0:v:0?", "-map", "0:a:0?", "-sn", "-dn", "-map_metadata", "0",
                str(temporary),
            ],
            capture_output=True, text=True, check=False,
        )
        if process.returncode:
            raise RuntimeError(process.stderr.strip() or "FFmpeg could not trim this file")
    return output
