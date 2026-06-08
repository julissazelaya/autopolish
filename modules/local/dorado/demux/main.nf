process DORADO_DEMUX {
    tag "$meta.id"
    label 'process_high'

    container "docker.io/nanoporetech/dorado:shae423e761540b9d08b526a1eb32faf498f32e8f22"


    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*.fastq"), emit: reads
    
    script:
    """
    mkdir -p demuxed
    dorado demux \
        --output-dir demuxed \
        --emit-fastq \
        --no-classify \
        ${bam}
    mv demuxed/*.fastq .
    """
    
    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_barcode01.fastq
    touch ${prefix}_barcode02.fastq
    """
}
