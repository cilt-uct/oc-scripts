#!/usr/bin/env python3
import json
import sys

MIN_SILENCE = 60.0                  # seconds - for internal cuts
BUFFER = 0.75                       # seconds - to avoid cutting too close to speech
EDGE_SILENCE_THRESHOLD  = 120.0     # seconds - to trim beginning/end sections
MIN_BLOCK_DURATION = 30.0           # seconds - to ignore very short chatter / speech bursts
MIN_WORD_PROB = 0.45
MIN_AVG_LOGPROB = -1.0
MAX_NO_SPEECH_PROB = 0.8
EDGE_CONFIDENCE = 0.70              # probability threshold for edge blocks

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file) as f:
    data = json.load(f)

# -------------------------
# Extract reliable words
# -------------------------
words = []

for segment in data.get("segments", []):

    # Ignore likely silence
    if segment.get("no_speech_prob", 0) > MAX_NO_SPEECH_PROB:
        continue

    # Ignore poor transcription
    if segment.get("avg_logprob", 0) < MIN_AVG_LOGPROB:
        continue

    if "words" in segment:
        for word in segment["words"]:
            probability = word.get("probability", 1.0)
            if probability < MIN_WORD_PROB:
                continue

            words.append({
                "start": float(word["start"]),
                "end": float(word["end"]),
                "confidence": probability
            })

    else:
        words.append({
            "start": float(segment["start"]),
            "end": float(segment["end"]),
            "confidence": 1.0
        })

# No speech found
if not words:
    with open(output_file, "w") as f:
        json.dump([], f, indent=2)
    sys.exit(0)

# -------------------------
# Build speech blocks
# -------------------------
blocks = []

current_block = {
    "start": words[0]["start"],
    "end": words[0]["end"],
    "confidences": [words[0]["confidence"]]
}

for current, nxt in zip(words, words[1:]):
    silence = nxt["start"] - current["end"]

    if silence >= MIN_SILENCE:
        current_block["confidence"] = (sum(current_block["confidences"]) / len(current_block["confidences"]))
        blocks.append(current_block)

        current_block = {
            "start": nxt["start"],
            "end": nxt["end"],
            "confidences": [nxt["confidence"]]
        }

    else:
        current_block["end"] = nxt["end"]
        current_block["confidences"].append(nxt["confidence"])

# add final block
current_block["confidence"] = (sum(current_block["confidences"]) / len(current_block["confidences"]))
blocks.append(current_block)

# -------------------------
# Remove tiny blocks
# -------------------------
blocks = [b for b in blocks if (b["end"] - b["start"]) >= MIN_BLOCK_DURATION]

if not blocks:
    with open(output_file, "w") as f:
        json.dump([], f, indent=2)

    sys.exit(0)

# -------------------------
# Trim the beginning
# -------------------------
while len(blocks) > 1:
    gap = blocks[1]["start"] - blocks[0]["end"]

    if (gap >= EDGE_SILENCE_THRESHOLD and blocks[0]["confidence"] < EDGE_CONFIDENCE):
        blocks.pop(0)
    else:
        break

# -------------------------
# Trim the end
# -------------------------
while len(blocks) > 1:
    gap = blocks[-1]["start"] - blocks[-2]["end"]

    if (gap >= EDGE_SILENCE_THRESHOLD and blocks[-1]["confidence"] < EDGE_CONFIDENCE):
        blocks.pop()
    else:
        break

# -------------------------
# Convert blocks to cuts
# -------------------------
cuts = []

for block in blocks:
    cuts.append({
        "begin": int((block["start"] + BUFFER) * 1000),
        "end": int((block["end"] - BUFFER) * 1000)
    })

cuts[0]["begin"] = int(blocks[0]["start"] * 1000)
cuts[-1]["end"] = int(blocks[-1]["end"] * 1000)

for cut in cuts:
    cut["duration"] = (cut["end"] - cut["begin"])

# -------------------------
# Write cutmarks
# -------------------------
with open(output_file,"w") as f:
    json.dump(cuts, f, indent=2)