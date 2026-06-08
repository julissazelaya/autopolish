process DNAAPLER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/dnaapler_mmseqs2:39f8f0bdf999cf76' :
        'community.wave.seqera.io/library/dnaapler_mmseqs2:39f8f0bdf999cf76' }"

    input:
    tuple val(meta), path(gfa)

    output:
    tuple val(meta), path("${prefix}_reoriented.gfa"), emit: gfa
    tuple val("${task.process}"), val('dnaapler'), eval("dnaapler --version"), topic: versions, emit: versions_dnaapler

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
 

    """
    dnaapler all \\
        --input ${gfa} \\
        --output dnaapler \\
        --threads ${task.cpus} \\
        ${args}

    mv dnaapler/dnaapler_reoriented.gfa ${prefix}_reoriented.gfa
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"

    """    
    touch ${prefix}_reoriented.gfa
    """
}
