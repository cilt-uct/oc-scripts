#!/opt/opencast/wfexec/venv/bin/python
import os
import sys
import subprocess
import tempfile
import json
from openai import OpenAI

print("DEBUG: Python script started")

CONFIG_FILE = "/opt/opencast/etc/org.opencastproject.transcription.whisper.WhisperTranscriptionService.cfg"
CHUNK_SECONDS = 600  # 10 minutes
OVERLAP_SECONDS = 30

def load_api_key():
    if not os.path.exists(CONFIG_FILE):
        raise RuntimeError("Config file not found")

    with open(CONFIG_FILE) as f:
        for line in f:
            if line.strip().startswith("whisper.client.api.key"):
                return line.split("=", 1)[1].strip()

    raise RuntimeError("API key not found in config file")

def get_duration(input_file):
    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        input_file
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())

def split_audio(input_file, temp_dir):
    duration = get_duration(input_file)
    chunks = []

    step = CHUNK_SECONDS - OVERLAP_SECONDS
    if step <= 0:
        raise ValueError("OVERLAP_SECONDS must be smaller than CHUNK_SECONDS")

    start = 0
    while start < duration:
        chunk_file = os.path.join(temp_dir, f"chunk_{int(start)}.wav")

        cmd = [
            "ffmpeg",
            "-y",
            "-i", input_file,
            "-ss", str(start),
            "-t", str(CHUNK_SECONDS),
            "-ac", "1",
            "-ar", "16000",
            chunk_file
        ]

        subprocess.run(cmd, check=True)
        chunks.append((chunk_file, start))

        start += step

    return chunks

def offset_timestamp(ts, offset):
    h, m, s_ms = ts.split(":")
    s, ms = s_ms.split(".")
    total = int(h)*3600 + int(m)*60 + int(s) + offset
    h = total // 3600
    m = (total % 3600) // 60
    s = total % 60
    return f"{h:02}:{m:02}:{s:02}.{ms}"

def offset_vtt(vtt_text, offset):
    lines = vtt_text.splitlines()
    new_lines = []

    for line in lines:
        line = line.strip()

        if line == "WEBVTT":
            continue
        if line.isdigit():
            continue

        if "-->" in line:
            start, end = line.split(" --> ")
            start = offset_timestamp(start.strip(), offset)
            end = offset_timestamp(end.strip(), offset)
            new_lines.append(f"{start} --> {end}")
        else:
            new_lines.append(line)

    return "\n".join(new_lines).strip()

def main():
    if len(sys.argv) != 4:
        sys.exit(1)

    input_file = sys.argv[1]
    output_vtt = sys.argv[2]
    # output_json = sys.argv[2]

    print(f"Input file: {input_file}")
    print(f"Output file: {output_vtt}")
    # print(f"Output file: {output_json}")

    if not os.path.exists(input_file):
        sys.exit(1)

    # Print file size
    try:
        file_size_bytes = os.path.getsize(input_file)
        file_size_mb = file_size_bytes / (1024 * 1024)
        print(f"DEBUG: Input file size = {file_size_mb:.2f} MB ({file_size_bytes} bytes)")
    except Exception as e:
        print(f"ERROR: Could not determine file size: {e}")
        sys.exit(1)

    api_key = load_api_key()
    client = OpenAI(api_key=api_key)

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            chunks = split_audio(input_file, temp_dir)

            merged_vtt = "WEBVTT\n\n"
            # merged_json = {"segments": []}

            for chunk_file, start_offset in chunks:
                print(f"Transcribing chunk starting at {start_offset}s")

                with open(chunk_file, "rb") as audio:
                    transcript = client.audio.transcriptions.create(
                        file=audio,
                        model="whisper-1",
                        response_format="vtt"
                    )

                adjusted_vtt = offset_vtt(transcript, start_offset)
                merged_vtt += adjusted_vtt.strip() + "\n\n"

            with open(output_vtt, "w", encoding="utf-8") as f:
                f.write(merged_vtt)

            print(f"DEBUG: Wrote VTT to {output_vtt}")

        print("Transcription successful")
        sys.exit(0)

    except Exception as e:
        print("ERROR during transcription:")
        print(str(e))
        sys.exit(1)

if __name__ == "__main__":
    main()