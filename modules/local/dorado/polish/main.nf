process DORADO_POLISH {
    tag "$meta.id"
    label 'process_high'
    label 'process_gpu'

    container "docker.io/nanoporetech/dorado:shae423e761540b9d08b526a1eb32faf498f32e8f22"

    input:
    tuple val(meta), path(bam), path(bai)
    tuple val(meta2), path(assembly)

    output:
    tuple val(meta), path("${meta.id}.polished.fasta"), emit: fasta
    path "versions.yml",                                emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    dorado polish \\
        ${bam} \\
        ${assembly} \\
        --bacteria \\
        --threads ${task.cpus} \\
        ${args} \\
        > ${prefix}.polished.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(dorado --version 2>&1 | head -n1)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.polished.fasta
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: "stub-version"
    END_VERSIONS
    """
}
