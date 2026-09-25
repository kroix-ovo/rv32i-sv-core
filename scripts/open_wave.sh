#!/bin/sh
# Open the generated FST with the repository's signal grouping. The macOS app
# launcher avoids the deprecated Homebrew Perl wrapper; other hosts use PATH.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
wave_file="$repo_dir/sim/build/cocotb/dump.fst"
save_file="$repo_dir/waves/rv32i_core.gtkw"
mac_app=/Applications/gtkwave.app
mac_launcher="$mac_app/Contents/MacOS/gtkwave"

if [ ! -f "$wave_file" ]; then
  echo "Missing $wave_file; run 'make test-cocotb-waves' first." >&2
  exit 1
fi

if [ -x "$mac_launcher" ]; then
  cd "$mac_app"
  exec ./Contents/MacOS/gtkwave "$wave_file" "$save_file"
fi

exec gtkwave "$wave_file" "$save_file"
