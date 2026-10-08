process AUTOCYCLER_CANU {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_canu_flye_necat_pruned:03bb63b44c09a95e' :
        'community.wave.seqera.io/library/autocycler_canu_flye_necat_pruned:03bb63b44c09a95e' }"

    input:
    tuple val(meta), path(reads)
    val genome_size

    output:
    tuple val(meta), path("${prefix}.fasta"), optional: true, emit: fasta
    tuple val(meta), path("${prefix}.log"),   optional: true, emit: log
    path "versions.yml",                      emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix   = task.ext.prefix ?: "${meta.id}"
    """
    autocycler helper canu \\
        --reads ${reads} \\
        --out_prefix ${prefix} \\
        --genome_size ${genome_size} \\
        --threads ${task.cpus} \\
        --read_type ${params.read_type} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/^[^ ]* //')
        canu: \$(canu -version 2>&1 | sed 's/^canu //')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fasta
    touch ${prefix}.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/^[^ ]* //')
        canu: \$(canu -version 2>&1 | sed 's/^canu //')
    END_VERSIONS
    """
}
