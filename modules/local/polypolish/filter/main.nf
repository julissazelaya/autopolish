process POLYPOLISH_FILTER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/polypolish:0.6.0--hdbdd923_0':
        'quay.io/biocontainers/polypolish:0.6.0--hdbdd923_0' }"

    input:
    tuple val(meta), path(in1), path(in2)

    output:
    tuple val(meta), path("${task.ext.prefix ?: meta.id}_1.sam"), path("${task.ext.prefix ?: meta.id}_2.sam"), emit: sam
    tuple val("${task.process}"), val('polypolish'), eval("polypolish --version"), topic: versions, emit: versions_polypolish

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    polypolish filter \\
        --in1 ${in1} \\
        --in2 ${in2} \\
        --out1 ${prefix}_1.sam \\
        --out2 ${prefix}_2.sam \\
        ${args}}
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    echo $args
    
    touch ${prefix}_1.sam
    touch ${prefix}_2.sam    
    """
}
