process AUTOCYCLER_GENOMESIZE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_raven-assembler:53191ef8c6711fb3' :
        'community.wave.seqera.io/library/autocycler_raven-assembler:53191ef8c6711fb3' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), stdout, emit: genome_size
    path "versions.yml",     emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    autocycler helper genome_size \
        --reads ${reads} \
        --threads ${task.cpus} \
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
    END_VERSIONS
    """

    stub:
    """
    echo 1000000

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
    END_VERSIONS
    """
}