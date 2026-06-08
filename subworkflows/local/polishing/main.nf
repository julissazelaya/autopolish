/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DORADO_POLISH  } from '../../../modules/local/dorado/polish/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow POLISHING {
    take:
        aligned_assembly
        consensus_assembly

    main:
        ch_polish_input = aligned_assembly
            .join(consensus_assembly)
            .map { meta, bam, bai, fasta -> [ meta, bam, bai, fasta ] }
        
        polished = DORADO_POLISH(
            ch_polish_input.map { meta, bam, bai, fasta -> [ meta, bam, bai ] },
            ch_polish_input.map { meta, bam, bai, fasta -> [ meta, fasta ] }
        )

    emit:
        fasta = polished.fasta
}
