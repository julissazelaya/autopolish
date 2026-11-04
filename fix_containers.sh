#!/usr/bin/env bash
# Makes the STEPS.md B10 edits (ONT containers from Docker Hub) and the
# AUTOCYCLER_COMBINE input-line fix (2026-11-04).
# Run from the top of the autopolish repo:  bash fix_containers.sh
# Safe to run twice. It prints what it changed; check with `git diff` before you commit.

set -euo pipefail

if [ ! -f main.nf ] || [ ! -f nextflow.config ]; then
    echo "Run this from the top of the autopolish repo (the folder with main.nf and nextflow.config)."
    exit 1
fi

# 1. ONT containers: 'ontresearch/...' -> 'docker.io/ontresearch/...'
for f in \
    modules/local/dorado/basecaller/main.nf \
    modules/local/dorado/demux/main.nf \
    modules/local/qsfilter/main.nf \
    modules/local/basecallversions/main.nf \
    modules/local/basecallstats/main.nf \
    modules/local/progressivestats/main.nf \
    modules/local/basecallreport/main.nf \
    modules/local/stopcondition/main.nf
do
    if [ ! -f "$f" ]; then
        echo "  MISSING  $f"
    elif grep -q "container *'ontresearch/" "$f"; then
        perl -pi -e "s#container\s*'ontresearch/#container 'docker.io/ontresearch/#" "$f"
        echo "  CHANGED  $f"
    else
        echo "  ok       $f (already docker.io)"
    fi
done

# 2. AUTOCYCLER_COMBINE: path(reads) belongs after path(clusters, stageAs: ...), not inside it
f=modules/nf-core/autocycler/combine/main.nf
if [ ! -f "$f" ]; then
    echo "  MISSING  $f"
elif grep -qE 'path\(clusters, *stageAs: *("[^"]*"|'"'[^']*'"'), *path\(reads\)\)' "$f"; then
    perl -pi -e 's#path\(clusters,\s*stageAs:\s*("[^"]*"|\x27[^\x27]*\x27),\s*path\(reads\)\)#path(clusters, stageAs: $1), path(reads)#' "$f"
    echo "  CHANGED  $f"
else
    echo "  ok       $f (input line already fixed)"
fi

echo
echo "Done. Check the changes with: git diff"
