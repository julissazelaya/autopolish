process AUTOCYCLER_NECAT {
    tag "$meta.id"
    label 'process_high'

    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'community.wave.seqera.io/library/autocycler_canu_flye_necat_pruned:03bb63b44c09a95e' :
        'community.wave.seqera.io/library/autocycler_canu_flye_necat_pruned:03bb63b44c09a95e' }"

    input:
    tuple val(meta), path(reads)
    val genome_size

    output:
    tuple val(meta), path("${prefix}.fasta"), emit: fasta
    path "versions.yml",                      emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    prefix     = task.ext.prefix ?: "${meta.id}_necat"
    """
    autocycler helper necat \\
        --reads ${reads} \\
        --out_prefix ${prefix} \\
        --genome_size ${genome_size} \\
        --threads ${task.cpus} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version 2>&1 | sed 's/autocycler //')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}_necat"
    """
    touch ${prefix}.fasta
    touch versions.yml
    """
}