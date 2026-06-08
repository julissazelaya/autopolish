process DORADO_ALIGNER {
    tag "$meta.id"
    label 'process_medium'

    container "docker.io/nanoporetech/dorado:shae423e761540b9d08b526a1eb32faf498f32e8f22"


    input:
    tuple val(meta), path(reads)
    tuple val(meta2), path(assembly)

    output:
    tuple val(meta), path("${meta.id}.bam"), emit: bam
    path "versions.yml", emit: versions

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    dorado aligner \
        ${assembly} \\
        ${reads} \\
        ${args} \\
        > ${prefix}.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(dorado --version 2>&1 | head -n1)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: "stub-version"
    END_VERSIONS
    """
}
