/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DORADO_DEMUX } from '../../../modules/local/dorado/demux/main.nf'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow DEMUX {
    take:
        bam

    main:
        demuxed = DORADO_DEMUX(bam)

        demuxed.reads
            .filter { meta, fastq -> !fastq.name.contains('unclassified') }
            .map { meta, fastq ->
                def barcode_id = fastq.name.toString()
                    .replaceAll('.fastq', '')
                    .replaceAll('.gz', '')
                [ [id: barcode_id], fastq ]
            }
            .set { ch_classified_reads }

    emit:
        reads = ch_classified_reads
}