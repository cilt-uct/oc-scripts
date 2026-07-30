#!/bin/bash

SRC="$1"
LANG="$2"
OUT="$3"
home="/opt/opencast ? /llm-subtrans" ###??????????? where

# --model gemini-3.1-flash-lite \

"$home/env_subtrans/bin/python" "$home/scripts/gemini-subtrans.py" \
  "$SRC" \
  --target-language "$LANG" \
  --output "$OUT" \
  --model gemini-3.5 \
  --preprocess \
  --postprocess \
  --maxbatchsize 120 \
  --minbatchsize 12 \
  --scenethreshold 180