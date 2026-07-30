import os
import sys
import json
from openai import OpenAI

print("DEBUG: Whisper transcription Python script started")

CONFIG_FILE = "/opt/opencast/etc/org.opencastproject.transcription.whisper.WhisperTranscriptionService.cfg"
DB_CONFIG_FILE = "/opt/opencast/etc/custom.properties"

def load_api_key():
    if not os.path.exists(CONFIG_FILE):
        raise RuntimeError("Config file not found")

    with open(CONFIG_FILE) as f:
        for line in f:
            if line.strip().startswith("whisper.client.api.key"):
                return line.split("=", 1)[1].strip()

    raise RuntimeError("API key not found in config file")

def translate_vtt(client, text, target_language):
    response = client.responses.create(
        model="gpt-4.1",
        input=f"""
            Translate the following subtitle text into {target_language}.

            Rules:
            - Preserve the meaning accurately.
            - Keep technical and academic terminology.
            - Return only the translated text.
            - Do not add explanations.

            Text:
            {text}
        """
    )

    return response.output_text.strip()


def main():

    prog = (
        os.path.basename(sys.argv[0])
        if sys.argv and sys.argv[0]
        else "translate-whisper-subtitles.py"
    )

    # Required:
    # input_vtt target_language output_vtt mediapackage_id
    if len(sys.argv) != 5:
        print(
            f"Usage: {prog} <input_vtt> <target_language> "
            f"<output_vtt> <mediapackage_id>",
            file=sys.stderr
        )
        sys.exit(1)

    input_vtt = sys.argv[1]
    target_language = sys.argv[2]
    output_vtt = sys.argv[3]
    mediapackage_id = sys.argv[4]

    print(f"Input VTT: {input_vtt}")
    print(f"Target language: {target_language}")
    print(f"Output VTT: {output_vtt}")
    print(f"MediaPackage id: {mediapackage_id}")

    if not os.path.exists(input_vtt):
        print(
            f"ERROR: Input file '{input_vtt}' does not exist or is not accessible.",
            file=sys.stderr
        )
        sys.exit(1)


    try:
        file_size_bytes = os.path.getsize(input_vtt)
        file_size_kb = file_size_bytes / 1024

        print(
            f"DEBUG: Input VTT size = {file_size_kb:.2f} KB "
            f"({file_size_bytes} bytes)"
        )

    except Exception as e:
        print(f"ERROR: Could not determine file size: {e}")
        sys.exit(1)

    try:
        api_key = load_api_key()
        client = OpenAI(api_key=api_key)

        with open(input_vtt, "r", encoding="utf-8") as f:
            lines = f.readlines()

        segments = []
        current_segment = None

        for line in lines:
            stripped = line.strip()

            # Ignore VTT header and empty lines
            if stripped == "WEBVTT" or stripped == "":
                continue

            # Timestamp line
            if "-->" in stripped:
                if current_segment:
                    segments.append(current_segment)

                start, end = stripped.split(" --> ")

                current_segment = {
                    "start": start,
                    "end": end,
                    "text": ""
                }

            # Subtitle text
            elif current_segment:
                current_segment["text"] += stripped + "\n"


        if current_segment:
            segments.append(current_segment)

        if not segments:
            raise RuntimeError("No subtitle segments found in VTT")

        print(f"DEBUG: Translating {len(segments)} subtitle segments")

        for index, segment in enumerate(segments):
            original_text = segment["text"].strip()

            if not original_text:
                continue

            print(
                f"Translating segment {index + 1}/{len(segments)}: "
                f"{original_text[:80]}"
            )

            translated = translate_vtt(
                client,
                original_text,
                target_language
            )

            segment["text"] = translated


        # Write translated VTT
        with open(output_vtt, "w", encoding="utf-8") as f:
            f.write("WEBVTT\n\n")

            for index, segment in enumerate(segments):
                f.write(f"{index + 1}\n")
                f.write(
                    f"{segment['start']} --> {segment['end']}\n"
                )
                f.write(
                    f"{segment['text']}\n\n"
                )

        print("Translation completed successfully")

    except Exception as e:
        print("ERROR during translation:")
        print(str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()