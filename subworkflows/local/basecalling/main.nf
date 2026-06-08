/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DORADO_BASECALLER     } from '../../../modules/local/dorado/basecaller/main.nf'
include { DORADO_DEMUX          } from '../../../modules/local/dorado/demux/main.nf'
include { SAMTOOLS_MERGE        } from '../../../modules/nf-core/samtools/merge/main.nf'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow BASECALLING {
    take:
        pod5

    main:
        basecalled = DORADO_BASECALLER(pod5)
        basecalled.bam
            .map { meta, bam -> [ [id: 'merged'], bam ] }
            .groupTuple()
            .set { ch_bams_to_merge }

        ch_merge_input = ch_bams_to_merge
            .map { meta, bams -> [ meta, bams, [] ] }
        ch_fasta = channel.value( [ [:], [], [], [] ] )
        merged = SAMTOOLS_MERGE(ch_merge_input, ch_fasta)


    emit:
        bam   = merged.bam
}
