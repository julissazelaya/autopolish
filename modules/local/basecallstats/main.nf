// Ported from epi2me-labs/wf-basecalling v1.5.9 (main.nf, process bamstats).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)

process BASECALLSTATS {
    tag "$meta.id"
    label 'process_low'
    container 'ontresearch/wf-common:sha21d552f9910c575766e5d465fcb7b52fefda4b79'

    input:
    tuple val(meta), path(cram, stageAs: 'input.cram')  // one chunk's pass reads
    val sample_name                                    // name shown in the report (the run)

    output:
    path "${meta.id}.bamstats.tsv", emit: tsv
    path "${meta.id}.stats.json"  , emit: json

    script:
    """
    bamstats --threads=${task.cpus} -u input.cram > ${meta.id}.bamstats.tsv
    fastcat_histogram.py \\
        --sample_id "${sample_name}" \\
        ${meta.id}.bamstats.tsv ${meta.id}.stats.json
    """

    stub:
    """
    touch ${meta.id}.bamstats.tsv
    echo '{"${sample_name}": {"total_reads": 0}}' > ${meta.id}.stats.json
    """
}
