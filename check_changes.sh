#!/usr/bin/env bash
# Checks that the --assembler_mode / autocycler_fast / STAGEASSEMBLIES changes are all in
# place. Run from the top of the autopolish repo:  bash check_changes.sh
# It only reads files; it changes nothing. Paste the whole output back into the thread.

pass=0; fail=0; warn=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); }
note() { echo "  WARN  $1"; warn=$((warn+1)); }

# has FILE PATTERN DESCRIPTION  (fixed-string match)
has() {
    if [ ! -f "$1" ]; then bad "$3 ($1 is missing)"
    elif grep -qF -- "$2" "$1"; then ok "$3"
    else bad "$3 (not found in $1)"; fi
}
# lacks FILE PATTERN DESCRIPTION
lacks() {
    if [ ! -f "$1" ]; then bad "$3 ($1 is missing)"
    elif grep -qF -- "$2" "$1"; then bad "$3 ($1 line $(grep -nF -- "$2" "$1" | head -1 | cut -d: -f1))"
    else ok "$3"; fi
}
exists() { if [ -f "$1" ]; then ok "$1 exists"; else bad "$1 is missing"; fi; }

ROOT_MAIN=main.nf
DRAFT=subworkflows/local/draft_assembly/main.nf
CONFIG=nextflow.config
SCHEMA=nextflow_schema.json
MODCONF=conf/modules.config

if [ ! -f "$ROOT_MAIN" ] || [ ! -f "$CONFIG" ]; then
    echo "Run this from the top of the autopolish repo (the folder with main.nf and nextflow.config)."
    exit 1
fi

echo "== Old names left anywhere in the repo"
for old in assembler_set assemblerSets assemblersForSet COLLECT_ASSEMBLIES canu_mode; do
    hits=$(grep -rnF --exclude-dir=.git --exclude-dir=work --exclude-dir=results \
           --exclude-dir=.nextflow --exclude=check_changes.sh -- "$old" . 2>/dev/null)
    if [ -z "$hits" ]; then ok "no '$old'"; else bad "'$old' still in:"; echo "$hits" | sed 's/^/          /'; fi
done

echo "== Pasted '+' markers at the start of a line"
for f in "$ROOT_MAIN" "$DRAFT" "$CONFIG" "$MODCONF"; do
    [ -f "$f" ] || continue
    hits=$(grep -n '^+' "$f")
    if [ -z "$hits" ]; then ok "none in $f"; else bad "lines starting with + in $f:"; echo "$hits" | sed 's/^/          /'; fi
done

echo "== $CONFIG"
if grep -qE "assembler_mode[[:space:]]*=[[:space:]]*['\"]standard['\"]" "$CONFIG"; then
    ok "assembler_mode = 'standard'"; else bad "assembler_mode = 'standard' not set in params"; fi

echo "== $SCHEMA"
has   "$SCHEMA" '"assembler_mode"' 'assembler_mode property'
if grep -A6 -F '"assembler_mode"' "$SCHEMA" 2>/dev/null | grep -q '"fast"'; then
    ok "assembler_mode enum includes fast"; else bad "assembler_mode enum is missing \"fast\""; fi
if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json,sys; json.load(open('$SCHEMA'))" 2>/dev/null; then ok "$SCHEMA is valid JSON"
    else bad "$SCHEMA is not valid JSON (check commas around the edited property)"; fi
fi

echo "== $ROOT_MAIN (repo root)"
has "$ROOT_MAIN" "include { assemblerModes }" 'includes assemblerModes from DRAFT_ASSEMBLY'
has "$ROOT_MAIN" 'assemblerModes().keySet()'   'launch check uses assemblerModes()'
has "$ROOT_MAIN" '--assembler_mode'             'help text mentions --assembler_mode'
has "$ROOT_MAIN" '12 assemblies per sample'     'help text has the fast mode line'
lacks "$ROOT_MAIN" "['standard', 'extended', 'fast']" 'no hard-coded mode list left'

echo "== $DRAFT"
has   "$DRAFT" 'def assemblerModes()'                 'defines assemblerModes()'
has   "$DRAFT" 'def assemblersForMode('               'defines assemblersForMode()'
has   "$DRAFT" "fast: fast"                           "assemblerModes() includes fast"
has   "$DRAFT" 'assemblersForMode(params.assembler_mode)' 'reads params.assembler_mode'
has   "$DRAFT" 'include { STAGEASSEMBLIES'            'includes STAGEASSEMBLIES'
has   "$DRAFT" 'STAGEASSEMBLIES(ch_all_assemblies)'   'calls STAGEASSEMBLIES'
lacks "$DRAFT" 'process COLLECT_ASSEMBLIES'           'old COLLECT_ASSEMBLIES process removed'
has   "$DRAFT" 'include { AUTOCYCLER_CANU'            'includes AUTOCYCLER_CANU'
has   "$DRAFT" 'canu_assembly.fasta'                  'Canu output in the .mix()'
has   "$DRAFT" 'include { AUTOCYCLER_MYLOASM'         'includes AUTOCYCLER_MYLOASM'
has   "$DRAFT" 'myloasm_assembly.fasta'               'Myloasm output in the .mix()'
has   "$DRAFT" 'plassembler_per_subsample'            'Plassembler per subsample in fast mode'

echo "== Module files"
for f in modules/local/stageassemblies/main.nf modules/local/stageassemblies/environment.yml \
         modules/local/stageassemblies/meta.yml \
         modules/local/autocycler/myloasm/main.nf modules/local/autocycler/myloasm/environment.yml \
         modules/local/autocycler/canu/main.nf modules/local/autocycler/canu/environment.yml; do
    exists "$f"
done
has   modules/local/stageassemblies/main.nf 'process STAGEASSEMBLIES' 'stageassemblies/main.nf defines STAGEASSEMBLIES'
lacks modules/local/stageassemblies/meta.yml 'stageassemblies --version' 'stageassemblies/meta.yml replaced (no template versions block)'
if [ -f modules/local/stageassemblies/tests/main.nf.test ]; then
    note "modules/local/stageassemblies/tests/main.nf.test is the nf-core template; delete it or write a real test"
fi
if grep -qF 'REPLACE_ME' modules/local/autocycler/myloasm/main.nf 2>/dev/null; then
    note "modules/local/autocycler/myloasm/main.nf still has REPLACE_ME (build the Wave image and paste its tag)"
fi
has modules/local/autocycler/canu/main.nf 'process AUTOCYCLER_CANU' 'canu/main.nf defines AUTOCYCLER_CANU'

echo "== $MODCONF"
has "$MODCONF" 'withName: AUTOCYCLER_MYLOASM' 'AUTOCYCLER_MYLOASM block'
has "$MODCONF" '--min_depth_rel 0.1'          'Myloasm gets --min_depth_rel 0.1'
has "$MODCONF" 'withName: AUTOCYCLER_CANU'    'AUTOCYCLER_CANU block'
has "$MODCONF" "'--count 2'"                  'subsample uses --count 2 in fast mode'
if [ -f "$MODCONF" ]; then
    n=$(awk '/withName:[[:space:]]*'"'"'?AUTOCYCLER_SUBSAMPLE/{inb=1; next} inb && /withName:/{inb=0} inb && /ext\.args/{c++} END{print c+0}' "$MODCONF")
    if [ "$n" = "1" ]; then ok "AUTOCYCLER_SUBSAMPLE sets ext.args once"
    elif [ "$n" = "0" ]; then bad "AUTOCYCLER_SUBSAMPLE block has no ext.args"
    else bad "AUTOCYCLER_SUBSAMPLE sets ext.args $n times (only the last one counts)"; fi
    if awk '/withName:[[:space:]]*'"'"'?AUTOCYCLER_SUBSAMPLE/{inb=1; next} inb && /withName:/{inb=0} inb' "$MODCONF" | grep -q 'min_read_depth'; then
        ok "AUTOCYCLER_SUBSAMPLE still passes --min_read_depth"
    else bad "AUTOCYCLER_SUBSAMPLE lost --min_read_depth"; fi
fi

echo
echo "Summary: $pass passed, $fail failed, $warn warnings"
