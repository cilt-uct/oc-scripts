#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ROOT_DIR=$(dirname "$0")

# handle log/pass/fail
log()  { echo -e "\n $1"; }
ok()   { echo "  $1"; }
fail() { echo "  $1"; FAILURES=$((FAILURES+1)); }

echo $ROOT_DIR
# check dir function
ensure_dir() {
  [[ -d "$1" ]] || mkdir -p "$1"
}

# echofile preview
print_file_preview() {
  local file="$1"
  [[ -f "$file" ]] || return
  echo "  --- preview ($file) ---"
  head -n 10 "$file" | sed 's/^/    /'
  echo "  --- end preview ---"
}

# clean tests leave raw files, just incase theres OS upgrade
clean_tests() {
  log "Cleaning test and output folders (raw untouched)"

  for d in video audio image; do
    [[ -d "$ROOT_DIR/$d/test" ]] && rm -f "$ROOT_DIR/$d/test"/*
    [[ -d "$ROOT_DIR/$d/output" ]] && rm -f "$ROOT_DIR/$d/output"/*
  done

  ok "Cleanup complete"
}

# FFmpeg – Video tests (mp4 / mkv)

test_video() {
  log "Testing video (FFmpeg)"

  RAW="$ROOT_DIR/raw/hoerilt2-30s-with-audio.mkv"
  TEST="$ROOT_DIR/video/test/video_test.json"
  OUT="$ROOT_DIR/video/output/video_output.json"

  ensure_dir "$ROOT_DIR/video/test"
  ensure_dir "$ROOT_DIR/video/output"

  echo "Raw input: $RAW"
  echo "Reference: $TEST"
  echo "Output:    $OUT"

  [[ -f "$RAW" ]] || { fail "Raw video not found"; return; }

  echo "Running ffprobe"
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,avg_frame_rate \
    -of json "$RAW" | tee "$OUT"

  [[ -f "$TEST" ]] || {
    cp "$RAW"
    ok "Reference created (bootstrap)"
  }

  if diff -u "$TEST" "$OUT" >/dev/null; then
    ok "Video metadata matches reference"
    echo "$TEST" "$OUT"
  else
    fail "Video metadata differs"
    diff -u "$TEST" "$OUT" || true
  fi
}

# SoX – Audio tests
test_audio() {
  log "Testing audio (SoX)"

  RAW="$ROOT_DIR/raw/flac_media_test.flac"
  TEST="$ROOT_DIR/audio/test/audio_test.sha256"
  OUT="$ROOT_DIR/audio/output/audio_output.sha256"

  ensure_dir "$ROOT_DIR/audio/test"
  ensure_dir "$ROOT_DIR/audio/output"

  echo "Raw input: $RAW"
  echo "Reference: $TEST"
  echo "Output:    $OUT"

  [[ -f "$RAW" ]] || { fail "Raw audio not found"; return; }

  # Sox create hash
  info "Generating audio hash - Sox test"
  sox "$RAW" -t raw - | sha256sum | awk '{echo$1}' > "$OUT"

  #
  [[ -f "$TEST" ]] || {
    cp "$OUT" "$TEST"
    ok "Reference created (bootstrap)"
  }

  # Always compare
  if diff -u "$TEST" "$OUT" >/dev/null; then
    ok "Audio hash matches reference"
  else
    fail "Audio hash differs"
    diff -u "$TEST" "$OUT" || true
    print_file_preview "$OUT"
  fi
}

test_ocr() {
  log "Testing OCR (Tesseract – raw text match)"

  RAW="$ROOT_DIR/raw/testmedia_oct_terrasect.png"
  TEST="$ROOT_DIR/image/test/image_test.txt"
  OUT="$ROOT_DIR/image/output/image_output.txt"

  ensure_dir "$ROOT_DIR/image/test"
  ensure_dir "$ROOT_DIR/image/output"

  echo "Raw input: $RAW"
  echo "Reference: $TEST"
  echo "Output:    $OUT"

  [[ -f "$RAW" ]] || { fail "Raw image not found"; return; }

  # OCR → normalize
  tesseract "$RAW" stdout --psm 6 2>/dev/null \
    | sed 's/[[:space:]]\+/ /g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^ *//;s/ *$//' \
    > "$OUT"

  # Bootstrap golden
  if [[ ! -f "$TEST" ]]; then
    cp "$OUT" "$TEST"
    ok "OCR reference created"
  fi

  # Compare
  if diff -u "$TEST" "$OUT" >/dev/null; then
    ok "OCR output matches reference"
  else
    fail "OCR output differs"
    diff -u "$TEST" "$OUT" || true
  fi
}


# to clean all test before running
case "$1" in
  clean)
    clean_tests
    exit 0
    ;;
esac

test_video
test_audio
test_ocr

echo
if [[ $FAILURES -eq 0 ]]; then
  ok "All media tests passed"
  exit 0
else
  echo "$FAILURES test(s) failed"
  exit 1
fi
