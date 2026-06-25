process PLASSEMBLER_LONG {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_chopper_dnaapler_fastp_pruned:c48f917a2773734a' :
        'community.wave.seqera.io/library/autocycler_chopper_dnaapler_fastp_pruned:c48f917a2773734a' }"

    input:
    tuple val(meta), path(long_reads), val(genome_size)

    output:
    tuple val(meta), path("*.fasta"), optional: true, emit: fasta
    tuple val(meta), path("*.gfa"),   optional: true, emit: gfa
    path "versions.yml",              emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    export PLASSEMBLER_DB=${params.plassembler_db}

    autocycler helper plassembler \\
        --reads ${long_reads} \\
        --out_prefix ${prefix} \\
        --genome_size ${genome_size} \\
        --threads ${task.cpus} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
        plassembler: \$(plassembler --version)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fasta
    touch ${prefix}.gfa

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
        plassembler: \$(plassembler --version)
    END_VERSIONS
    """
}