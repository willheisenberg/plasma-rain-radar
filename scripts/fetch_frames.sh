#!/usr/bin/env bash
set -euo pipefail

MAX_FRAMES="${MAX_FRAMES:-12}"
STEP_MINUTES="${STEP_MINUTES:-5}"
TIME_DIRECTION="${TIME_DIRECTION:-future}" # future|past

WMS_BASE_URL="${WMS_BASE_URL:-https://maps.dwd.de/geoserver/ows}"
WMS_LAYER="${WMS_LAYER:-dwd:Niederschlagsradar}"
WMS_VERSION="${WMS_VERSION:-1.3.0}"
WMS_CRS="${WMS_CRS:-EPSG:4326}"
# Germany extent in WGS84 (lat/lon)
WMS_BBOX="${WMS_BBOX:-47.0,5.5,55.5,15.5}"
WMS_WIDTH="${WMS_WIDTH:-900}"
WMS_HEIGHT="${WMS_HEIGHT:-700}"

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/plasma-rain-radar"
FRAMES_DIR="$CACHE_ROOT/frames"
MANIFEST="$CACHE_ROOT/manifest.json"

mkdir -p "$FRAMES_DIR"
rm -f "$FRAMES_DIR"/*

# Round current UTC timestamp down to STEP_MINUTES.
now_epoch="$(date -u +%s)"
step_sec="$((STEP_MINUTES * 60))"
base_epoch="$(( (now_epoch / step_sec) * step_sec ))"

ok=0
idx=0
frame_entries=""

for ((i = 0; i < MAX_FRAMES; i++)); do
  if [ "$TIME_DIRECTION" = "past" ]; then
    ts_epoch="$((base_epoch - (MAX_FRAMES - 1 - i) * step_sec))"
  else
    ts_epoch="$((base_epoch + i * step_sec))"
  fi
  ts="$(date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")"

  fname="frame_$(printf '%02d' "$idx").png"
  out="$FRAMES_DIR/$fname"
  url="${WMS_BASE_URL}?SERVICE=WMS&VERSION=${WMS_VERSION}&REQUEST=GetMap&LAYERS=${WMS_LAYER}&STYLES=&CRS=${WMS_CRS}&BBOX=${WMS_BBOX}&WIDTH=${WMS_WIDTH}&HEIGHT=${WMS_HEIGHT}&FORMAT=image/png&TRANSPARENT=TRUE&TIME=${ts}"

  if curl -fsSL "$url" -o "$out"; then
    if [ "$(head -c 8 "$out" | xxd -p)" = "89504e470d0a1a0a" ]; then
      bytes="$(wc -c < "$out" | tr -d ' ')"
      if [ "$bytes" -gt 1200 ]; then
        ok=$((ok + 1))
        # Build JSON entry for this frame
        if [ -n "$frame_entries" ]; then
          frame_entries="${frame_entries},"
        fi
        frame_entries="${frame_entries}{\"file\":\"${fname}\",\"time\":\"${ts}\"}"
      else
        rm -f "$out"
      fi
    else
      rm -f "$out"
    fi
  fi

  idx=$((idx + 1))
done

if [ "$ok" -eq 0 ]; then
  printf '{"ok":false,"error":"WMS lieferte keine nutzbaren Radarframes","source":"%s","layer":"%s"}\n' "$WMS_BASE_URL" "$WMS_LAYER"
  exit 2
fi

updated="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf '{"ok":true,"count":%d,"updated":"%s","source":"%s","layer":"%s","direction":"%s","frames":[%s]}\n' \
  "$ok" "$updated" "$WMS_BASE_URL" "$WMS_LAYER" "$TIME_DIRECTION" "$frame_entries" | tee "$MANIFEST"
