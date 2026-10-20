// Ported from epi2me-labs/wf-basecalling v1.5.9 (lib/signal/ingress.nf, process split_calls).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)

process DORADO_DEMUX {
    label 'process_low'
    container 'ontresearch/dorado:shac8f356489fa8b44b31beba841b84d2879de2088e'

    input:
    path(crams, stageAs: 'crams/*')  // every chunk's pass reads

    output:
    path("demuxed/**/*.bam"), emit: bams
    tuple val("${task.process}"), val('dorado'), eval("dorado --version 2>&1 | head -n1"), emit: versions_dorado, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Reads were already classified by 'dorado basecaller --kit-name', so demux only splits
    // them into one folder per barcode (.../barcodeNN/*.bam)
    def args = task.ext.args ?: ''
    """
    dorado demux --output-dir demuxed --no-classify --recursive ${args} crams
    """

    stub:
    """
    mkdir -p demuxed/stub/bam_pass/barcode01
    touch demuxed/stub/bam_pass/barcode01/stub.bam
    """
}
