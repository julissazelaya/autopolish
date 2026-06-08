process AUTOCYCLER_GFA2FASTA {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_seqkit:4ed8a47183130c75' :
        'community.wave.seqera.io/library/autocycler_seqkit:4ed8a47183130c75' }"

    input:
    tuple val(meta), path(gfa)

    output:
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.fasta"), emit: fasta
    path "versions.yml",                                          emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    autocycler gfa2fasta \\
        -i ${gfa} \\
        -o ${prefix}.fasta \\
        ${args}

    seqkit sort --by-length --reverse ${prefix}.fasta > ${prefix}.sorted.fasta
    mv ${prefix}.sorted.fasta ${prefix}.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
        seqkit: \$(seqkit version | sed 's/seqkit v//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo ">stub_contig" > ${prefix}.fasta
    echo "ATGC" >> ${prefix}.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
        seqkit: \$(seqkit version | sed 's/seqkit v//')
    END_VERSIONS
    """
}