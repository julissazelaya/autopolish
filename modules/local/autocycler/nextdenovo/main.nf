process AUTOCYCLER_NEXTDENOVO {
    tag "$meta.id"
    label 'process_high'
    errorStrategy 'ignore'

    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_nextdenovo_nextpolish:5954f10c2e75e345' :
        'community.wave.seqera.io/library/autocycler_nextdenovo_nextpolish:5954f10c2e75e345' }"

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
    prefix     = task.ext.prefix ?: "${meta.id}_nextdenovo"
    """
    autocycler helper nextdenovo \\
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
    prefix = task.ext.prefix ?: "${meta.id}_nextdenovo"
    """
    touch ${prefix}.fasta
    touch versions.yml
    """
}