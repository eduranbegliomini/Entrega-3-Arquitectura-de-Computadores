# Shared settings for every LibreLane run (sourced by the other scripts).
LIBRELANE_REV=64ef80802d3d189b476636d2a6b17888c03304ee   # LibreLane v3.0.17
PDK=gf180mcuD
SCL=gf180mcu_fd_sc_mcu7t5v0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

librelane_cmd() {
  if command -v librelane >/dev/null 2>&1; then
    librelane "$@"
  else
    nix shell "github:librelane/librelane/$LIBRELANE_REV" --command librelane "$@"
  fi
}

# Tool from PATH, or the copy that LibreLane's Nix closure already contains.
find_tool() {
  if command -v "$1" >/dev/null 2>&1; then command -v "$1"; return; fi
  local t; t=$(ls -d /nix/store/*-"$2"-*/bin/"$1" 2>/dev/null | head -1)
  [ -n "$t" ] || { echo "error: $1 not found" >&2; exit 1; }
  echo "$t"
}
