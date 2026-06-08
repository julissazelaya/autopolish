process AUTOCYCLER_WEIGHT {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/autocycler:0.5.2--h3ab6199_0':
        'quay.io/biocontainers/autocycler:0.5.2--h3ab6199_0' }"  

    input:
    tuple val(meta), path(fasta)
    val weight_type

    output:
    tuple val(meta), path("${fasta}"), emit: fasta

    when:
    task.ext.when == null || task.ext.when

    script:
    if (weight_type == 'cluster') {
        """
        sed -i 's/circular=True/circular=True Autocycler_cluster_weight=2/' ${fasta}
        """
    } else if (weight_type == 'consensus') {
        """
        sed -i 's/^>.*\$/& Autocycler_consensus_weight=2/' ${fasta}
        """
    } else {
        error "Unknown weight_type: ${weight_type}. Must be 'cluster' or 'consensus'"
    }

    stub:
    """
    touch ${fasta}
    """
}