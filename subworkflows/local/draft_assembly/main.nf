/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { AUTOCYCLER_GENOMESIZE  } from '../../../modules/local/autocycler/genomesize/main'
include { AUTOCYCLER_SUBSAMPLE   } from '../../../modules/nf-core/autocycler/subsample/main'
include { AUTOCYCLER_MINIASM     } from '../../../modules/local/autocycler/miniasm/main'
include { AUTOCYCLER_WEIGHT as AUTOCYCLER_WEIGHT_PLASSEMBLER } from '../../../modules/local/autocycler/weight/main'
include { AUTOCYCLER_WEIGHT as AUTOCYCLER_WEIGHT_FLYE        } from '../../../modules/local/autocycler/weight/main'
include { FLYE                   } from '../../../modules/nf-core/flye/main'
include { METAMDBG_ASM           } from '../../../modules/nf-core/metamdbg/asm/main'
include { AUTOCYCLER_METAMDBGFILTER   } from '../../../modules/local/autocycler/metamdbgfilter/main'
include { PLASSEMBLER_LONG       } from '../../../modules/local/plassembler/long/main'
include { RAVEN                  } from '../../../modules/nf-core/raven/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow DRAFT_ASSEMBLY {

    take:
        reads

    main:
        /*
        -------------------------------
        Flatten reads per barcode
        -------------------------------
        */
        ch_reads_flat = reads
            .map { meta, fastq ->
                def barcode = (fastq instanceof List ? fastq[0] : fastq).name.toString()
                    .replaceAll('.fastq', '')
                    .replaceAll('.gz', '')
                [ [id: barcode], (fastq instanceof List ? fastq[0] : fastq) ]
            }

        /*
        -------------------------------
        Genome size calculation
        -------------------------------
        */
        genome_size = AUTOCYCLER_GENOMESIZE(ch_reads_flat)

        reads_with_size = ch_reads_flat
            .join(genome_size.genome_size.map { meta, size -> [ meta, size.trim() ] })
            .map { meta, reads, size -> [ meta, reads, size ] }

        ch_reads = reads_with_size.map { meta, reads, size ->
            [ meta, reads instanceof List ? reads[0] : reads ]
        }
        ch_genomesize = reads_with_size.map { meta, reads, size -> size }

        /*
        -------------------------------
        Subsampling
        -------------------------------
        */
        subsampled = AUTOCYCLER_SUBSAMPLE(ch_reads, ch_genomesize)

        /*
        -------------------------------
        Flatten subsampled reads per assembler run
        -------------------------------
        */
        ch_subsampled_flat = subsampled.subsampled_reads
            .transpose()
            .map { meta, fastq ->
                def sample_name = fastq.name.toString().replaceAll('.fastq.gz', '')
                [ [id: "${meta.id}_${sample_name}", barcode: meta.id], fastq ]
            }

        ch_subsampled_with_size = ch_subsampled_flat
            .map { meta, fastq -> [ meta.barcode, meta, fastq ] }
            .combine(
                reads_with_size.map { meta, reads, size -> [ meta.id, size ] },
                by: 0
            )
            .map { barcode, meta, fastq, size -> [ meta, fastq, size ] }

        ch_assembler_reads      = ch_subsampled_with_size.map { meta, fastq, size -> [ meta, fastq ] }
        ch_assembler_genomesize = ch_subsampled_with_size.map { meta, fastq, size -> size }

        /*
        -------------------------------
        Assemblers (parallel)
        -------------------------------
        */
        flye_assembly     = FLYE(ch_assembler_reads, params.flye_mode)
        metamdbg_assembly  = METAMDBG_ASM(ch_assembler_reads, params.metamdbg_input_type)
        metamdbg_filtered  = AUTOCYCLER_METAMDBGFILTER(metamdbg_assembly.contigs)
        raven_assembly    = RAVEN(ch_assembler_reads)
        miniasm_assembly  = AUTOCYCLER_MINIASM(ch_assembler_reads, ch_assembler_genomesize)

        ch_reads_for_plassembler = reads_with_size.map { meta, reads, size -> [ meta, reads, size ] }
        plassembler_assembly     = PLASSEMBLER_LONG(ch_reads_for_plassembler)

        /*
        --------------------------------------------------------
        Collect assemblies per barcode and weight for Autocycler
        --------------------------------------------------------
        */
        plassembler_fasta_remapped = plassembler_assembly.fasta
            .map { meta, fasta -> [ [id: "${meta.id}_plassembler", barcode: meta.id], fasta ] }

        plassembler_weighted = AUTOCYCLER_WEIGHT_PLASSEMBLER(
            plassembler_fasta_remapped,
            'cluster'
        )
        
        flye_weighted = AUTOCYCLER_WEIGHT_FLYE(
            flye_assembly.fasta,
            'consensus'
        )

        ch_all_assemblies = flye_weighted.fasta
            .mix(metamdbg_filtered.fasta)
            .mix(miniasm_assembly.fasta)
            .mix(plassembler_weighted.fasta)
            .mix(raven_assembly.fasta)
            .map { meta, fasta -> [ meta.barcode, fasta ] }
            .groupTuple(remainder: true)
            .map { barcode, fastas -> [ [id: barcode], fastas ] }

        assemblies = COLLECT_ASSEMBLIES(ch_all_assemblies)

    emit:
        subsampled_reads = subsampled.subsampled_reads
        assemblies       = assemblies.assemblies
        normalized_reads = ch_reads_flat
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    LOCAL PROCESS: COLLECT_ASSEMBLIES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process COLLECT_ASSEMBLIES {
    tag "$meta.id"
    label 'process_single'

    input:
    tuple val(meta), path(fastas, stageAs: "input_?/*")

    output:
    tuple val(meta), path("assemblies/*.fasta"), emit: assemblies

    script:
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