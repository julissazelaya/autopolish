
process READRUNSHEET {
    tag "${run_sheet.name}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://community.wave.seqera.io/library/openpyxl_python:fcafab6af980d837' :
        'community.wave.seqera.io/library/openpyxl_python:fcafab6af980d837' }"

    input:
    path run_sheet

    output:
    path "samplesheet.csv", emit: csv
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/Python //'"), emit: versions_python, topic: versions
    tuple val("${task.process}"), val('openpyxl'), eval("python -c 'import openpyxl; print(openpyxl.__version__)'"), emit: versions_openpyxl, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // bin/read_run_sheet.py: reads the run header and sample table of the lab's xlsx run sheet and writes the sample sheet CSV

    """
    read_run_sheet.py ${run_sheet} samplesheet.csv
    """

    stub:
    """
    echo 'sample,barcode,run' > samplesheet.csv
    """
}