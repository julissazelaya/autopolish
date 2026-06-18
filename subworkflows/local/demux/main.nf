/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DORADO_DEMUX } from '../../../modules/local/dorado/demux/main.nf'
include { NANOPLOT     } from '../../../modules/nf-core/nanoplot/main'                                                                                                                                                                                                                                                                                                                                 
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

        nanoplot = NANOPLOT(ch_classified_reads)


    emit:
        reads = ch_classified_reads
        nanoplot = nanoplot.html
}