/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DORADO_ALIGNER                        } from '../../../modules/local/dorado/aligner/main'
include { SAMTOOLS_ADDREPLACERG                 } from '../../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_SORT } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_RG   } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_SORT                         } from '../../../modules/nf-core/samtools/sort/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow ALIGNMENT {
    take:
        consensus_assembly
        reads

    main:
        ch_align_input = consensus_assembly
            .join(reads)
            .map { meta, assembly, fq -> [ meta, fq, assembly ] }

        dorado_alignment = DORADO_ALIGNER(
            ch_align_input.map { meta, fq, assembly -> [ meta, fq ] },
            ch_align_input.map { meta, fq, assembly -> [ meta, assembly ] }
        )

        ch_sort_fasta = channel.value( [ [:], [], [] ] )
        sorted_alignment = SAMTOOLS_SORT(
            dorado_alignment.bam,
            ch_sort_fasta,
            ''
        )

        sorted_index = SAMTOOLS_INDEX_SORT(sorted_alignment.bam)

        ch_addreplacerg_input = sorted_alignment.bam
            .join(sorted_index.index)
            .map { meta, bam, index -> [ meta, bam, index, params.rg_tag.replaceAll('\\\\t', '\t') ] }

        ch_addreplacerg_fasta = channel.value( [ [:], [], [], [] ] )
        rg_alignment = SAMTOOLS_ADDREPLACERG(
            ch_addreplacerg_input,
            ch_addreplacerg_fasta
        )

        indexed_alignment = SAMTOOLS_INDEX_RG(rg_alignment.bam)

    emit:
        aligned_assembly = rg_alignment.bam
            .join(indexed_alignment.index)
}