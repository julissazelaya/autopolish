process AUTOCYCLER_MYLOASM {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_myloasm:4d5ec6764d413bd8' :
        'community.wave.seqera.io/library/autocycler_myloasm:4d5ec6764d413bd8' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${prefix}.fasta"), optional: true, emit: fasta
    tuple val(meta), path("${prefix}.gfa"),   optional: true, emit: gfa
    tuple val(meta), path("${prefix}.log"),   optional: true, emit: log
    path "versions.yml",                      emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix   = task.ext.prefix ?: "${meta.id}"
    """
    autocycler helper myloasm \\
        --reads ${reads} \\
        --out_prefix ${prefix} \\
        --threads ${task.cpus} \\
        --read_type ${params.read_type} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/^[^ ]* //')
        myloasm: \$(myloasm --version | sed 's/.* //')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fasta
    touch ${prefix}.gfa
    touch ${prefix}.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/^[^ ]* //')
        myloasm: \$(myloasm --version | sed 's/.* //')
    END_VERSIONS
    """
}
