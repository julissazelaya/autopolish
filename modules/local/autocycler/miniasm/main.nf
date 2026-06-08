process AUTOCYCLER_MINIASM {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/autocycler_miniasm_minipolish:b2824e8b9f9e391c' :
        'community.wave.seqera.io/library/autocycler_miniasm_minipolish:b2824e8b9f9e391c' }"

    input:
    tuple val(meta), path(reads)
    val genome_size

    output:
    tuple val(meta), path("${prefix}.fasta"), optional: true, emit: fasta
    tuple val(meta), path("${prefix}.gfa"),   optional: true, emit: gfa
    path "versions.yml"                                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    
    """
    autocycler helper miniasm \\
        --reads ${reads} \\
        --out_prefix ${prefix} \\
        --threads ${task.cpus} \\
        --genome_size ${genome_size} \\
        --read_type ${params.read_type} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        autocycler: \$(autocycler --version | sed 's/Autocycler v//')
        miniasm: \$(miniasm --version | head -n 1 | sed 's/Miniasm v//')
    END_VERSIONS    
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}.fasta
    touch ${prefix}.gfa
    touch versions.yml
    """
}