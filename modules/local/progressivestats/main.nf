// Ported from epi2me-labs/wf-basecalling v1.5.9 (main.nf, process progressive_stats).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)
//
// Run with .scan() so each new chunk's stats are added to the running total, which keeps
// the report up to date while basecalling is still going. Needs
// 'nextflow.preview.recursion = true' in repo-root main.nf.
import nextflow.util.BlankSeparatedList

process PROGRESSIVESTATS {
    label 'process_single'
    maxForks 1
    container 'ontresearch/wf-common:sha21d552f9910c575766e5d465fcb7b52fefda4b79'

    input:
    path fastcat_stats

    output:
    path("all_stats.${task.index}")

    script:
    def new_input = fastcat_stats instanceof BlankSeparatedList ? fastcat_stats.first() : fastcat_stats
    def state = fastcat_stats instanceof BlankSeparatedList ? fastcat_stats.last() : "NOSTATE"
    def output = "all_stats.${task.index}"
    """
    touch "${state}"
    add_jsons.py "${new_input}" "${state}" "${output}"
    """
}
