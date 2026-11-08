#!/usr/bin/env bash
# Offline smoke test for rea-video. Builds a 6s clip, splits it, and extracts audio.
# Does not call a VLM and does not run remake-run. The first run downloads two free
# weights files (UVR stem model ~67 MB and YuNet ~230 KB) into $REA_VIDEO_MODELS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if [ -x "$ROOT/.venv/bin/python" ]; then
    PY="$ROOT/.venv/bin/python"
  else
    PY="python3"
  fi
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required" >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe is required" >&2; exit 1; }
"$PY" -c 'import rea_video' || { echo "rea-video is not importable from $PY. Install with: $PY -m pip install -e \"$ROOT[ocr,dev]\"" >&2; exit 1; }

WORK="${1:-$ROOT/out/smoke-offline}"
mkdir -p "$WORK/home" "$WORK/models"
# Isolate prefs and keep this process from seeing a VLM key, even if the shell has one.
export REA_VIDEO_HOME="$WORK/home"
export REA_VIDEO_MODELS="${REA_VIDEO_MODELS:-$WORK/models}"
unset REA_VLM_BASE_URL REA_VLM_API_KEY REA_VLM_MODEL \
  VIDEO_ANALYSIS_BASE_URL VIDEO_ANALYSIS_API_KEY VIDEO_ANALYSIS_MODEL_NAME \
  GEMINI3_BASE_URL GEMINI3_API_KEY GEMINI3_MODEL_NAME || true

# White / black / blue differ in luma. A red-to-green swap with the same luma
# is not a reliable cut for this detector (gray difference stays near zero).
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=6" \
  -f lavfi -i "sine=frequency=1760:sample_rate=44100:duration=0.12" \
  -filter_complex "\
color=c=white:s=640x360:d=2:r=30[v0];\
color=c=black:s=640x360:d=2:r=30[v1];\
color=c=0x1E4DB7:s=640x360:d=2:r=30,drawbox=x=40:y=40:w=280:h=280:color=white:t=fill[v2];\
[v0][v1][v2]concat=n=3:v=1:a=0,format=yuv420p[v];\
[1]adelay=4500|4500,apad=whole_dur=6[beep];\
[0][beep]amix=inputs=2:duration=first:normalize=0[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart \
  "$WORK/clip.mp4"

"$PY" -m rea_video decompose "$WORK/clip.mp4" -o "$WORK/out" --no-vlm --lang en

"$PY" - "$WORK/out" <<'PY'
import json, sys
from pathlib import Path

out = Path(sys.argv[1])
b = json.loads((out / "breakdown.json").read_text(encoding="utf-8"))
shots = b["shots"]
starts = [s["start"] for s in shots]
ends = [s["end"] for s in shots]
assert len(shots) == 3, starts
assert abs(starts[0] - 0.0) < 0.05 and abs(ends[0] - 2.0) < 0.05
assert abs(starts[1] - 2.0) < 0.05 and shots[1]["transition_in"] == "cut"
assert abs(starts[2] - 4.0) < 0.05 and shots[2]["transition_in"] == "cut"
vlm = b.get("analysis", {}).get("vlm") or {}
assert vlm.get("status") == "off" and vlm.get("requested") is False, vlm
stems = b.get("stems") or {}
assert stems.get("ok") is True, stems
for name in ("original.wav", "vocals.wav", "music.wav"):
    p = out / "stems" / name
    assert p.is_file() and p.stat().st_size > 100_000, p
events = ((b.get("audio") or {}).get("sfx") or {}).get("events") or []
assert any(4.2 <= e.get("t", -1) <= 4.8 for e in events), events
print(json.dumps({
    "ok": True,
    "shots": [{"start": s["start"], "end": s["end"], "transition_in": s["transition_in"]} for s in shots],
    "vlm": vlm.get("status"),
    "stems": {k: stems.get(k) for k in ("ok", "model", "level_db")},
    "sfx_t": [e.get("t") for e in events],
    "out": str(out),
}, ensure_ascii=False))
PY

echo "PASS offline smoke -> $WORK/out"
