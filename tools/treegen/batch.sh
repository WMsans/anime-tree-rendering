#!/usr/bin/env bash
# Usage: tools/treegen/batch.sh <count> [out_dir]  — seeds 1..count for every preset.
set -euo pipefail
count=${1:?count}; out=${2:-assets/trees}
dir=$(dirname "$0")
for preset in banyan jungle_tall leaning broadleaf; do
  for seed in $(seq 1 "$count"); do
    blender -b --python "$dir/treegen.py" -- --preset "$preset" --seed "$seed" --out "$out" | grep '^wrote'
  done
done
