process STAGEASSEMBLIES {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'docker://ubuntu:22.04' :
        'ubuntu:22.04' }"

    input:
    tuple val(meta), path(fastas, stageAs: "input_?/*")

    output:
    tuple val(meta), path("assemblies/*.fasta"), emit: assemblies

    when:
    task.ext.when == null || task.ext.when

    script:
    // Builds the assemblies/ folder that autocycler compress reads: gunzips any
    // .gz inputs and prefixes each file with its input_N folder so names can't clash.
    """
    mkdir -p assemblies
    for input_dir in input_*/; do
        idx=\$(basename \$input_dir)
        for fasta in \$input_dir*; do
            fname=\$(basename \$fasta)
            if [[ \$fasta == *.gz ]]; then
                gunzip -c \$fasta > assemblies/\${idx}_\${fname%.gz}
            else
                cp \$fasta assemblies/\${idx}_\${fname}
            fi
        done
    done
    """

    stub:
    """
    mkdir -p assemblies
    touch assemblies/stub.fasta
    """
}
