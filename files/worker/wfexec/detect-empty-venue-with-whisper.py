#!/usr/bin/env python3

import json
import math
import os
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Minimum confidence/probability for a word to be considered reliable speech.
CONFIDENCE_THRESHOLD = 0.75

# Minimum number of segments containing reliable words.
MIN_SEGMENTS = 1000

# Minimum number of reliable words across the recording.
MIN_WORDS = 3500

def load_whisper_json(filename):
  """Load and return the Whisper JSON."""

  try:
    with open(filename, "r", encoding="utf-8") as f:
        return json.load(f)

  except FileNotFoundError:
    print(f"ERROR: File not found: {filename}", file=sys.stderr)
    sys.exit(2)

  except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON: {e}", file=sys.stderr)
    sys.exit(2)


def get_word_confidence(word):
  """Return the confidence/probability value for a Whisper word."""

  for field in ("probability", "prob", "confidence"):
    value = word.get(field)

    if value is not None:
      try:
        value = float(value)

        if math.isfinite(value):
          return value

      except (TypeError, ValueError):
        pass

    return None

def analyse_whisper_json(data, confidence_threshold, min_segments, min_words):
  """
  Analyse Whisper output and determine whether meaningful speech was detected.

  Returns a dictionary containing the analysis results.
  """

  segments = data.get("segments", [])

  if segments is None:
    print("ERROR: Whisper JSON does not contain a 'segments' field", file=sys.stderr)
    sys.exit(2)

  reliable_segments = 0
  reliable_words = 0
  total_segments = len(segments)
  total_words = 0
  segments_with_word_data = 0

  segment_results = []

  for segment in segments:
    words = segment.get("words")

    if words is None:
      print(
        "ERROR: Whisper segment does not contain word-level data "
        f"(start={segment.get('start')}, "
        f"end={segment.get('end')})",
        file=sys.stderr
      )
      sys.exit(2)

    segments_with_word_data += 1
    segment_reliable_words = 0

    # ---------------------------------------------------------------
    # Word-level confidence
    # ---------------------------------------------------------------
    for word in words:
      text = word.get("word", "").strip()
      if not text:
        continue

      total_words += 1
      confidence = get_word_confidence(word)

      if confidence is None:
        print(
          "WARNING: Word has no valid probability "
          f"(word={text!r}, "
          f"segment_start={segment.get('start')})",
          file=sys.stderr
        )
        continue

      if confidence >= confidence_threshold:
        reliable_words += 1
        segment_reliable_words += 1

    if segment_reliable_words > 0:
      reliable_segments += 1

    segment_results.append({
        "start": segment.get("start"),
        "end": segment.get("end"),
        "reliable_words": segment_reliable_words
    })

  # -----------------------------------------------------------------------
  # Ensure word-level data was actually present.
  # -----------------------------------------------------------------------
  if total_segments > 0 and segments_with_word_data == 0:
    print("ERROR: No word-level data found in Whisper JSON", file=sys.stderr)
    sys.exit(2)

  # -------------------------------------------------------------------
  # Empty venue decision
  #
  # A venue is considered empty when there is insufficient reliable
  # speech according to BOTH thresholds.
  # -------------------------------------------------------------------
  empty_venue = (reliable_segments < min_segments and reliable_words < min_words)

  return {
    "empty_venue": empty_venue,
    "total_segments": total_segments,
    "total_words": total_words,
    "reliable_segments": reliable_segments,
    "reliable_words": reliable_words,
    "confidence_threshold": confidence_threshold,
    "min_segments": min_segments,
    "min_words": min_words,
    "segment_results": segment_results
  }

def write_result(output_file, result):
  """
  Write the detection result to segments.txt.

  The output file is intended to be attached to the MediaPackage by
  the execute-once workflow operation.
  """

  with open(output_file, "w", encoding="utf-8") as f:
    f.write(f"empty_venue={str(result['empty_venue']).lower()}\n")
    f.write(f"total_segments={result['total_segments']}\n")
    f.write(f"total_words={result['total_words']}\n")
    f.write(f"reliable_segments={result['reliable_segments']}\n")
    f.write(f"reliable_words={result['reliable_words']}\n")
    f.write(f"confidence_threshold="f"{result['confidence_threshold']}\n")
    f.write(f"min_segments={result['min_segments']}\n")
    f.write(f"min_words={result['min_words']}\n")

  return output_file

def main():
  # -----------------------------------------------------------------------
  # Arguments supplied by wrapper:
  #
  # $1 = Whisper JSON input file
  # $2 = MediaPackage ID
  # $3 = output file
  # -----------------------------------------------------------------------

  if len(sys.argv) < 4:
    print(
      f"Usage: {os.path.basename(sys.argv[0])} "
      "<input_file> <mediapackage_id> <output_file>",
      file=sys.stderr
    )
    sys.exit(1)

  input_file = sys.argv[1]
  mediapackage_id = sys.argv[2]
  output_file = sys.argv[3]

  print("Whisper empty venue detection")
  print("--------------------------------")
  print(f"MediaPackage ID:       {mediapackage_id}")
  print(f"Input file:            {input_file}")
  print(f"Output file:           {output_file}")
  print(f"Confidence threshold:  {CONFIDENCE_THRESHOLD}")
  print(f"Minimum segments:      {MIN_SEGMENTS}")
  print(f"Minimum words:         {MIN_WORDS}")
  print()

  # -----------------------------------------------------------------------
  # Validate input
  # -----------------------------------------------------------------------
  if not os.path.isfile(input_file):
    print(
      f"ERROR: Whisper JSON input file does not exist: {input_file}",
      file=sys.stderr
    )
    sys.exit(2)

  if not os.access(input_file, os.R_OK):
    print(
      f"ERROR: Whisper JSON input file is not readable: {input_file}",
      file=sys.stderr
    )
    sys.exit(2)

  # -----------------------------------------------------------------------
  # Load and analyse Whisper JSON
  # -----------------------------------------------------------------------
  data = load_whisper_json(input_file)
  result = analyse_whisper_json(data, CONFIDENCE_THRESHOLD, MIN_SEGMENTS, MIN_WORDS)

  # -----------------------------------------------------------------------
  # Display result
  # -----------------------------------------------------------------------
  print(f"Total segments:       {result['total_segments']}")
  print(f"Total words:          {result['total_words']}")
  print(f"Reliable segments:    {result['reliable_segments']}")
  print(f"Reliable words:       {result['reliable_words']}")
  print()

  if result["empty_venue"]:
    print("RESULT: EMPTY VENUE")
  else:
    print("RESULT: SPEECH DETECTED")

  # -----------------------------------------------------------------------
  # Write output
  # -----------------------------------------------------------------------
  output_file = write_result(output_file, result)
  print(f"Result written to:    {output_file}")

  sys.exit(0)

if __name__ == "__main__":
    main()