#!/usr/bin/env python3

import os
import sys
import subprocess
import re

FFMPEG_BIN = "/opt/ffmpeg-latest/bin/ffmpeg"


def has_sound_signal(media_file):
    """
    Check that the media file has a decodable audio stream and that
    the decoded audio contains a non-zero signal.

    Returns:
        True  = audio stream exists and contains a signal
        False = no usable audio stream or audio is completely silent
    """

    result = subprocess.run(
        [
            FFMPEG_BIN,
            "-v", "info",
            "-i", media_file,
            "-map", "0:a",
            "-af", "astats=metadata=1:reset=1",
            "-f", "null",
            "-"
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    # FFmpeg could not decode the audio stream.
    if result.returncode != 0:
        return False

    output = result.stderr

    # Look for RMS/peak information produced by astats.
    #
    # A completely silent digital signal has:
    #   RMS level dB: -inf
    #
    # A signal containing any non-zero samples will have
    # a finite RMS/peak value.
    rms_matches = re.findall(r"RMS level dB:\s*(-?inf|[-+]?\d+(?:\.\d+)?)", output)

    if not rms_matches:
        return False

    # If at least one measured frame has a finite RMS level, there is a non-zero audio signal.
    for rms in rms_matches:
        if rms.lower() != "-inf":
            return True

    return False


def main():
    if len(sys.argv) != 3:
        print("Usage: detect-audio.py <media_file> <output_file>", file=sys.stderr)
        return 1

    media_file = sys.argv[1]
    output_file = sys.argv[2]

    if not os.path.isfile(media_file):
        print(f"Media file does not exist: {media_file}", file=sys.stderr)
        return 1

    has_audio = has_sound_signal(media_file)

    with open(output_file, "w") as f:
        f.write(f"has_audio={'true' if has_audio else 'false'}\n")

    print(
        f"Audio detection: "
        f"{'sound signal detected' if has_audio else 'no sound signal'}"
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())