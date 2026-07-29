#!/usr/bin/env python3
import json
import sys

MIN_SILENCE = 4.0
BUFFER = 0.75

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file) as f:
    data = json.load(f)

words = []

for segment in data["segments"]:
    # ignore unreliable segments
    if segment.get("no_speech_prob", 0) > 0.8:
        continue

    if "words" not in segment:
        continue

    for word in segment["words"]:
        words.append({
            "start": word["start"],
            "end": word["end"]
        })

cuts = []

for current, nxt in zip(words, words[1:]):
    silence = nxt["start"] - current["end"]

    if silence >= MIN_SILENCE:
        cut_start = current["end"] + BUFFER
        cut_end = nxt["start"] - BUFFER

        if cut_end > cut_start:
            cuts.append({
                "begin": int(round(cut_start * 1000)),
                "end": int(round(cut_end * 1000)),
                "duration": int(round(cut_end-cut_start * 1000))
            })

# merge adjacent cuts

merged=[]

for cut in cuts:
    if not merged:
        merged.append(cut)
        continue

    previous=merged[-1]

    if cut["begin"] <= previous["end"] + 1000:
        previous["end"] = max(previous["end"], cut["end"])

    else:
        merged.append(cut)

for cut in merged:
    cut["duration"] = cut["end"] - cut["begin"]

with open(output_file,"w") as f:
    json.dump(
        merged,
        f,
        indent=2
    )