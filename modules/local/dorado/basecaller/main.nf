// Ported from epi2me-labs/wf-basecalling v1.5.9 (lib/signal/ingress.nf, process dorado).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)

process DORADO_BASECALLER {
    tag "$meta.id"
    label 'process_gpu'
    // Same image as wf-basecalling; it ships the Dorado models under $DRD_MODELS_PATH
    container 'ontresearch/dorado:shac8f356489fa8b44b31beba841b84d2879de2088e'

    input:
    tuple val(meta), path(pod5s, stageAs: 'pod5/*')
    val model        // e.g. 'dna_r10.4.1_e8.2_400bps_sup@v5.2.0'
    path model_dir   // [] to use the model from the container; a folder to override it
    val kit          // barcoding kit, e.g. 'SQK-NBD114-96'; '' for none

    output:
    tuple val(meta), path("${prefix}.ubam"), emit: ubam
    tuple val("${task.process}"), val('dorado'), eval("dorado --version 2>&1 | head -n1"), emit: versions_dorado, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args      = task.ext.args ?: ''   // e.g. '--device cuda:all' (set in conf/modules.config)
    prefix        = task.ext.prefix ?: "${meta.id}"
    def model_arg = model_dir ? "${model_dir}" : "\${DRD_MODELS_PATH}/${model}"
    def kit_arg   = kit ? "--kit-name ${kit}" : ''
    """
    dorado basecaller \\
        ${model_arg} \\
        pod5/ \\
        ${kit_arg} \\
        ${args} \\
        | samtools view --no-PG -b -o ${prefix}.ubam -
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.ubam
    """
}
