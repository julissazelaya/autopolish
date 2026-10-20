#!/usr/bin/env bash
# Checks that the run sheet + basecalling changes (STEPS.md) are all in place.
# Run from the top of the autopolish repo:  bash check_basecalling.sh
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
# has_re FILE REGEX DESCRIPTION
has_re() {
    if [ ! -f "$1" ]; then bad "$3 ($1 is missing)"
    elif grep -qE -- "$2" "$1"; then ok "$3"
    else bad "$3 (not found in $1)"; fi
}

if [ ! -f main.nf ] || [ ! -f nextflow.config ]; then
    echo "Run this from the top of the autopolish repo (the folder with main.nf and nextflow.config)."
    exit 1
fi

echo "== A1 bin/ scripts (exist and executable)"
for f in bin/read_run_sheet.py bin/basecalling_report.py bin/report_utils.py bin/fastcat_histogram.py bin/add_jsons.py; do
    if [ ! -f "$f" ]; then bad "$f is missing"
    elif [ -x "$f" ]; then ok "$f"
    else bad "$f is not executable (chmod +x $f)"; fi
done

echo "== A2 modules"
check_proc() { has "$1" "process $2 " "$1 defines $2"; }
check_proc modules/local/readrunsheet/main.nf       READRUNSHEET
check_proc modules/nf-core/samtools/cat/main.nf    SAMTOOLS_CAT
check_proc modules/nf-core/samtools/fastq/main.nf  SAMTOOLS_FASTQ
check_proc modules/local/dorado/basecaller/main.nf  DORADO_BASECALLER
check_proc modules/local/dorado/demux/main.nf       DORADO_DEMUX
check_proc modules/local/qsfilter/main.nf           QSFILTER
check_proc modules/local/basecallstats/main.nf      BASECALLSTATS
check_proc modules/local/progressivestats/main.nf   PROGRESSIVESTATS
check_proc modules/local/basecallreport/main.nf     BASECALLREPORT
check_proc modules/local/stopcondition/main.nf      STOPCONDITION
check_proc modules/local/basecallversions/main.nf   BASECALLVERSIONS
for f in modules/local/readrunsheet/environment.yml; do
    if [ -f "$f" ]; then ok "$f exists"; else bad "$f is missing"; fi
done
if grep -qF 'REPLACE_ME' modules/local/readrunsheet/main.nf 2>/dev/null; then
    note "modules/local/readrunsheet/main.nf still has REPLACE_ME container tags (Part C1)"
fi

echo "== A3 assets/schema_input.json"
has assets/schema_input.json '"organism_group"' 'schema_input.json is the run sheet version'
if command -v python3 >/dev/null 2>&1 && [ -f assets/schema_input.json ]; then
    if python3 -c "import json; json.load(open('assets/schema_input.json'))" 2>/dev/null; then ok "assets/schema_input.json is valid JSON"
    else bad "assets/schema_input.json is not valid JSON"; fi
fi

echo "== A4 subworkflows"
has subworkflows/local/run_sheet_input/main.nf    'workflow RUN_SHEET_INPUT'    'RUN_SHEET_INPUT'
has subworkflows/local/run_sheet_input/main.nf    'kit     = ch_kit'            'RUN_SHEET_INPUT emits kit (latest version)'
has subworkflows/local/dorado_basecalling/main.nf 'workflow DORADO_BASECALLING' 'DORADO_BASECALLING'
has subworkflows/local/barcode_reads/main.nf      'workflow BARCODE_READS'      'BARCODE_READS'
if [ -f subworkflows/local/dorado_basecalling/LICENSE_ONT ]; then ok "LICENSE_ONT next to DORADO_BASECALLING"
else bad "subworkflows/local/dorado_basecalling/LICENSE_ONT is missing (ONT license must travel with the ported code)"; fi
if [ -d subworkflows/local/wf_basecalling_input ]; then
    note "subworkflows/local/wf_basecalling_input/ exists; it is replaced by barcode_reads/ and can be deleted"
fi

echo "== B1 nextflow.config"
for p in run_sheet basecaller_cfg basecaller_model_path barcode_kit basecaller_chunk_size qscore_filter watch_path read_limit; do
    has_re nextflow.config "^[[:space:]]*${p}[[:space:]]*=" "param ${p}"
done
has nextflow.config 'nf-schema' 'nf-schema plugin listed'
for old in dorado_model dorado_models_dir dorado_modifications; do
    hits=$(grep -rn --include=*.nf --include=*.config --exclude-dir=work --exclude-dir=.nextflow -w -- "${old}" . 2>/dev/null | grep -v '^./subworkflows/local/basecalling/')
    if [ -z "$hits" ]; then ok "no '${old}' left (outside the old basecalling subworkflow)"
    else bad "'${old}' still used (now basecaller_cfg / basecaller_model_path):"; echo "$hits" | sed 's/^/          /'; fi
done

echo "== B2 conf/modules.config"
for p in DORADO_BASECALLER QSFILTER DORADO_DEMUX BASECALLSTATS BASECALLREPORT STOPCONDITION; do
    has conf/modules.config "withName: '${p}'" "${p} block"
done
has modules/local/dorado/basecaller/main.nf "label 'process_gpu'" "DORADO_BASECALLER has label process_gpu"
has conf/mrsn.config 'withLabel:process_gpu' 'conf/mrsn.config sends process_gpu jobs to the GPU node'
if grep -A10 -F "withName: 'DORADO_BASECALLER'" conf/modules.config 2>/dev/null | grep -qE '^[[:space:]]*(accelerator|containerOptions|clusterOptions)[[:space:]]*='; then
    note "DORADO_BASECALLER block in conf/modules.config sets GPU options; remove them so conf/mrsn.config's process_gpu settings apply"
fi

echo "== B3 nextflow_schema.json"
for p in run_sheet basecaller_cfg basecaller_model_path barcode_kit basecaller_chunk_size qscore_filter watch_path read_limit; do
    has nextflow_schema.json "\"${p}\"" "schema has ${p}"
done
has nextflow_schema.json '"wf_basecalling"' 'input_type enum includes wf_basecalling'
if python3 -c "import json,sys; d=json.load(open('nextflow_schema.json')); p=[g['properties']['input'] for g in d.get('\$defs',d.get('definitions',{})).values() if 'input' in g.get('properties',{})]; sys.exit(0 if p and 'schema' not in p[0] and p[0].get('format')!='file-path' else 1)" 2>/dev/null; then
    ok "input is a folder path, not the template's samplesheet"
else bad "input in nextflow_schema.json still looks like the nf-core samplesheet template (schema/file-path/.csv)"; fi
if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json; json.load(open('nextflow_schema.json'))" 2>/dev/null; then ok "nextflow_schema.json is valid JSON"
    else bad "nextflow_schema.json is not valid JSON (check commas around the new properties)"; fi
fi

echo "== B4 workflows/autopolish.nf"
W=workflows/autopolish.nf
for s in RUN_SHEET_INPUT DORADO_BASECALLING BARCODE_READS; do
    has_re "$W" "include[[:space:]]*\{[[:space:]]*${s}[[:space:]]*\}" "includes ${s}"
done
has "$W" "params.input_type in ['pod5', 'wf_basecalling']" 'pod5 / wf_basecalling branch'
if [ -d modules/local/mergebamtofastq ]; then note "modules/local/mergebamtofastq/ is no longer used (nf-core samtools/cat + samtools/fastq replace it)"; fi
has "$W" 'BARCODE_READS(ch_demuxed, RUN_SHEET_INPUT.out.samples)' 'calls BARCODE_READS'
if grep -qE 'BASECALLING\(ch_pod5\)|include[[:space:]]*\{[[:space:]]*BASECALLING[[:space:]]*\}' "$W" 2>/dev/null; then
    bad "old BASECALLING include/call still in $W"
else ok "old BASECALLING removed from $W"; fi

echo "== B5 repo-root main.nf"
has_re main.nf '^[[:space:]]*nextflow\.preview\.recursion[[:space:]]*=[[:space:]]*true' 'nextflow.preview.recursion = true'
if grep -qE "\[[^]]*'pod5'[^]]*\]" main.nf; then
    has main.nf "'wf_basecalling'" "input_type list in main.nf includes wf_basecalling"
fi

echo "== B6 subworkflows/local/draft_assembly/main.nf"
D=subworkflows/local/draft_assembly/main.nf
has "$D" 'meta?.run ? meta.id' 'DRAFT_ASSEMBLY names run sheet reads from meta.id'
if grep -qE '^[[:space:]]*\\[[:space:]]' "$D" 2>/dev/null; then
    bad "stray backslash at the start of a line in $D (line $(grep -nE '^[[:space:]]*\\[[:space:]]' "$D" | head -1 | cut -d: -f1))"
else ok "no stray backslash lines in $D"; fi

echo
echo "Summary: $pass passed, $fail failed, $warn warnings"
