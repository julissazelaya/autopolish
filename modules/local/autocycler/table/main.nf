process AUTOCYCLER_TABLE {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/autocycler:0.5.2--h3ab6199_0':
        'quay.io/biocontainers/autocycler:0.5.2--h3ab6199_0' }"

    input:
    tuple val(meta), path(yamls, stageAs: 'autocycler_dir/yaml_???/*')

    output:
    tuple val(meta), path("${prefix}.tsv"), emit: tsv
    tuple val("${task.process}"), val("autocycler"), eval("autocycler --version |  sed 's/^[^ ]* //'"), emit: versions_autocycler, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args   ?: ''
    prefix   = task.ext.prefix ?: "${meta.id}"
    """

    autocycler table $args > ${prefix}.tsv

    autocycler table \\
        $args \\
        --autocycler_dir autocycler_dir \\
        --name ${meta.id} \\
        >> ${prefix}.tsv
    """

    stub:
    prefix   = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.tsv
    """
}
