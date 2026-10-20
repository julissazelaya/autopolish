// Ported from epi2me-labs/wf-basecalling v1.5.9 (lib/signal/ingress.nf, process qsFilter).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)

process QSFILTER {
    tag "$meta.id"
    label 'process_low'
    container 'ontresearch/dorado:shac8f356489fa8b44b31beba841b84d2879de2088e'

    input:
    tuple val(meta), path(ubam)
    val qscore  // keep reads with mean Q >= this (wf-basecalling default 10)

    output:
    tuple val(meta), path("${prefix}.pass.cram"), emit: pass
    tuple val(meta), path("${prefix}.fail.cram"), emit: fail
    tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), emit: versions_samtools, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    samtools view -e '[qs] >= ${qscore}' ${ubam} \\
        --output ${prefix}.pass.cram \\
        --unoutput ${prefix}.fail.cram \\
        -O CRAM
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.pass.cram ${prefix}.fail.cram
    """
}
