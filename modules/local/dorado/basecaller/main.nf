process DORADO_BASECALLER {
    tag "$meta.id"
    label 'process_high'
    label 'process_gpu'

    container "docker.io/nanoporetech/dorado:shae423e761540b9d08b526a1eb32faf498f32e8f22"

    input:
    tuple val(meta), 
    path(pod5)

    output:
    tuple val(meta), path("${meta.id}.bam"), emit: bam
    path "versions.yml", emit: versions

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mods   = params.dorado_modifications ? "--modified-bases ${params.dorado_modifications}" : ""
    def device = task.ext.use_gpu ? "--device cuda:all" : ""
    """
    dorado basecaller \\
        ${params.dorado_models_dir}/${params.dorado_model} \\
        ${pod5} \\
        --kit-name ${params.barcode_kit} \\
        ${mods} \\
        ${device} \\
        ${args} \\
        > ${prefix}.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(dorado --version 2>&1 | head -n1)
    END_VERSIONS
    """
}
