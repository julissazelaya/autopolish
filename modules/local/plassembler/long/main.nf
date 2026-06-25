process PLASSEMBLER_LONG {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_canu_flye_necat_pruned:03bb63b44c09a95e' :
        'community.wave.seqera.io/library/autocycler_canu_flye_necat_pruned:03bb63b44c09a95e' }"

    input:
    tuple val(meta), path(long_reads), val(genome_size)

    output:
    tuple val(meta), path("*_plasmids.fasta"), optional: true, emit: fasta
    tuple val(meta), path("*_plasmids.gfa"),   optional: true, emit: gfa
    tuple val(meta), path("*_summary.tsv"),    optional: true, emit: tsv
    path "versions.yml",                                       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """

    plassembler long \\
        -l ${long_reads} \\
        -o plassembler_out \\
        --force \\
        --prefix ${prefix} \\
        --threads ${task.cpus} \\
        -d ${params.plassembler_db} \\
        -c ${genome_size} ${args}

    mv plassembler_out/${prefix}_plasmids.fasta . || true
    mv plassembler_out/${prefix}_plasmids.gfa   . || true
    mv plassembler_out/${prefix}_summary.tsv    . || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        plassembler: \$(plassembler --version)
    END_VERSIONS
    """
    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plasmids.fasta
    touch ${prefix}_plasmids.gfa
    touch ${prefix}_summary.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        plassembler: \$(plassembler --version)
    END_VERSIONS
    """
}