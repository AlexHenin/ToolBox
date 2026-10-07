import json
import shutil
import subprocess
from array import array
from pathlib import Path

from toolbox import TimeRange, tool
from toolbox.files import atomic_output, check_output, check_source


FORMATS = {".mp3": "libmp3lame", ".m4a": "aac", ".wav": "pcm_s16le"}


def audio_duration(source: Path) -> float:
    ffprobe = shutil.which("ffprobe")
    if ffprobe is None:
        raise RuntimeError("FFmpeg is missing. Install it with: brew install ffmpeg")
    process = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "json", str(source)],
        capture_output=True, text=True, check=False,
    )
    if process.returncode:
        raise ValueError(process.stderr.strip() or "Could not read audio duration")
    try:
        return float(json.loads(process.stdout)["format"]["duration"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("Could not read audio duration") from error


def audio_waveform(source: Path, duration: float, bins: int = 320) -> list[float]:
    """Decode a low-rate mono stream and return display peaks in equal time bins."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("FFmpeg is missing. Install it with: brew install ffmpeg")
    process = subprocess.Popen(
        [ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(source),
         "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "2000", "-f", "s16le", "-"],
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
        raise ValueError(stderr.strip() or "Could not build audio waveform")
    return [round(value ** 0.5, 4) for value in peaks]


@tool(
    title="Trim Audio",
    description="Export an accurate segment of an MP3, M4A, or WAV file.",
    extensions={"source": ["mp3", "m4a", "wav"], "output": ["mp3", "m4a", "wav"]},
)
def trim_audio(source: Path, segment: TimeRange, output: Path) -> Path:
    source = check_source(source, set(FORMATS))
    output = check_output(output, [source], set(FORMATS))
    duration = audio_duration(source)
    if not (0 <= segment.start < segment.end <= duration + 0.05):
        raise ValueError(f"Choose a range within 0–{duration:.2f} seconds")
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("FFmpeg is missing. Install it with: brew install ffmpeg")
    with atomic_output(output) as temporary:
        process = subprocess.run(
            [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
             "-ss", str(segment.start), "-t", str(segment.end - segment.start),
             "-map", "0:a:0", "-vn", "-c:a", FORMATS[output.suffix.lower()], str(temporary)],
            capture_output=True, text=True, check=False,
        )
        if process.returncode:
            raise RuntimeError(process.stderr.strip() or "FFmpeg could not trim the audio")
    return output
