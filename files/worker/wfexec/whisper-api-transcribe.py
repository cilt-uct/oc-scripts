#!/opt/opencast/wfexec/venv/bin/python
import os
import sys
import time
import subprocess
import tempfile
import mysql.connector
from openai import OpenAI
from datetime import datetime
from zoneinfo import ZoneInfo
from urllib.parse import urlparse

print("DEBUG: Python script started")

CONFIG_FILE = "/opt/opencast/etc/org.opencastproject.transcription.whisper.WhisperTranscriptionService.cfg"
DB_CONFIG_FILE = "/opt/opencast/etc/custom.properties"

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

def load_db_config():
    if not os.path.exists(DB_CONFIG_FILE):
        raise RuntimeError("DB config file not found")

    config = {}
    with open(DB_CONFIG_FILE) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                config[k.strip()] = v.strip()

    return config

def create_db_connection():
    cfg = load_db_config()

    url = cfg["org.opencastproject.db.jdbc.url"].replace("jdbc:", "")
    parsed = urlparse(url)

    return mysql.connector.connect(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=cfg["org.opencastproject.db.jdbc.user"],
        password=cfg["org.opencastproject.db.jdbc.pass"],
         database=parsed.path.lstrip("/")
    )

def generate_job_id():
    return str(int(time.time() * 1000))

def get_duration(input_file):
    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        input_file
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    # return float(result.stdout.strip())
    if result.returncode != 0:
        raise RuntimeError(
            f"ffprobe failed with exit code {result.returncode}: {result.stderr.strip()}"
        )
    output = result.stdout.strip()
    if not output:
        raise RuntimeError(
            f"ffprobe did not return a duration for '{input_file}'. Stderr: {result.stderr.strip()}"
        )
    try:
        return float(output)
    except ValueError as exc:
        raise RuntimeError(
            f"Unable to parse ffprobe duration output {output!r} for '{input_file}'. "
            f"Stderr: {result.stderr.strip()}"
        ) from exc

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

def insert_job(conn, mediapackage_id, duration, provider_id):
    cursor = conn.cursor()
    job_id = generate_job_id()

    cursor.execute("""
        INSERT INTO oc_transcription_service_job (
            id,
            date_created,
            mediapackage_id,
            provider_id,
            status,
            track_duration,
            track_id,
            job_id
        )
        VALUES (%(job_id)s, NOW(), 
                %(mediapackage_id)s, %(provider_id)s, 
                %(status)s, %(track_duration)s, 
                %(mediapackage_id)s, %(job_id)s)
    """, {
        "job_id": job_id,
        "provider_id": provider_id,
        "status": "InProgress",
        "track_duration": int(duration),
        "mediapackage_id": mediapackage_id
    })

    conn.commit()
    cursor.close()

    return job_id

def complete_job(conn, job_id, mediapackage_id, provider_id):
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE oc_transcription_service_job
                SET 
                    date_updated = NOW(),
                    date_completed = NOW(),
                    date_expected = NOW(),
                    status = %(status)s
                WHERE id = %(job_id)s
                AND mediapackage_id = %(mediapackage_id)s
                AND provider_id = %(provider_id)s
            """, {
                "status": "Closed",
                "job_id": job_id,
                "mediapackage_id": mediapackage_id,
                "provider_id": provider_id
            })
            conn.commit()
    except Exception as e:
        print(f"ERROR in complete_job: {e}", file=sys.stderr)

def fail_job(conn, job_id, mediapackage_id, provider_id):
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE oc_transcription_service_job
                SET 
                    date_updated = NOW(),
                    status = %(status)s
                WHERE id = %(job_id)s
                 AND mediapackage_id = %(mediapackage_id)s
                 AND provider_id = %(provider_id)s
            """, {
                "status": "Canceled",
                "job_id": job_id,
                "mediapackage_id": mediapackage_id,
                "provider_id": provider_id
            })
            conn.commit()
    except Exception as e:
        print(f"ERROR in fail_job: {e}", file=sys.stderr)

def main():
    prog = os.path.basename(sys.argv[0]) if sys.argv and sys.argv[0] else "whisper-api-transcribe.py"

    # Accept 3 required arguments and an optional 4th (track_id) for traceability
    if len(sys.argv) not in (4, 5):
        print(f"Usage: {prog} <input_file> <output_vtt> <mediapackage_id> [track_id]", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_vtt = sys.argv[2]
    mediapackage_id = sys.argv[3]
    track_id = sys.argv[4] if len(sys.argv) == 5 else None

    print(f"Input file: {input_file}")
    print(f"Output file: {output_vtt}")
    print(f"Mediapackage id: {mediapackage_id}")
    if track_id:
        # consume the previously unused argument for logging/traceability
        print(f"Track id: {track_id}")

    if not os.path.exists(input_file):
        print(f"ERROR: Input file '{input_file}' does not exist or is not accessible.", file=sys.stderr)
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
    job_id = None

    try:
        conn = create_db_connection()
        # Fetch provider_id for 'whisper-api' from oc_transcription_service_provider
        with conn.cursor() as cursor:
            cursor.execute("SELECT id FROM oc_transcription_service_provider WHERE provider = %(provider_name)s", {"provider_name": "whisper-api"})
            row = cursor.fetchone()
            if not row:
                print("ERROR: No provider found with name 'whisper-api'", file=sys.stderr)
                sys.exit(1)
            provider_id = row[0]
        print(f"DEBUG: Using provider_id = {provider_id}")
        duration = get_duration(input_file)
        job_id = insert_job(conn, mediapackage_id, duration, provider_id)
        print(f"DEBUG: Created transcription job {job_id}")

        with tempfile.TemporaryDirectory() as temp_dir:
            chunks = split_audio(input_file, temp_dir)

            merged_vtt = "WEBVTT\n\n"

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

            print(f"DEBUG: Wrote merged VTT to {output_vtt}")

        complete_job(conn, job_id, mediapackage_id, provider_id)
        print("Transcription successful")
        sys.exit(0)

    except Exception as e:
        print("ERROR during transcription:")
        print(str(e))
        if job_id:
            try:
                fail_job(conn, job_id, mediapackage_id, provider_id)
            except Exception as fe:
                print(f"ERROR while marking job as failed: {fe}")
        sys.exit(1)


if __name__ == "__main__":
    main()