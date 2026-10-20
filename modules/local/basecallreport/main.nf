// Ported from epi2me-labs/wf-basecalling v1.5.9 (main.nf, process makeReport).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)

process BASECALLREPORT {
    label 'process_single'
    maxForks 1  // one at a time, so the newest report is the one published last
    container 'ontresearch/wf-common:sha21d552f9910c575766e5d465fcb7b52fefda4b79'

    input:
    path per_read_stats     // latest running total from PROGRESSIVESTATS
    path "versions/*"       // name,version files
    path "params.json"
    val sample_name

    output:
    path "*.html", emit: html

    script:
    def prefix = task.ext.prefix ?: "${sample_name}"
    """
    basecalling_report.py ${prefix}.basecalling-report.html \\
        --sample_name ${sample_name} \\
        --versions versions \\
        --stats ${per_read_stats} \\
        --params params.json \\
        --workflow_version ${workflow.manifest.version}
    """

    stub:
    def prefix = task.ext.prefix ?: "${sample_name}"
    """
    touch ${prefix}.basecalling-report.html
    """
}
