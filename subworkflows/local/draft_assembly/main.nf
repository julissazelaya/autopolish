/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { AUTOCYCLER_CANU        } from '../../../modules/local/autocycler/canu/main'          // NEW (assembler_mode)
include { AUTOCYCLER_GENOMESIZE  } from '../../../modules/local/autocycler/genomesize/main'
include { AUTOCYCLER_SUBSAMPLE   } from '../../../modules/nf-core/autocycler/subsample/main'
include { AUTOCYCLER_MINIASM     } from '../../../modules/local/autocycler/miniasm/main'
include { AUTOCYCLER_MYLOASM     } from '../../../modules/local/autocycler/myloasm/main'        // NEW (fast)
include { AUTOCYCLER_WEIGHT as AUTOCYCLER_WEIGHT_PLASSEMBLER } from '../../../modules/local/autocycler/weight/main'
include { AUTOCYCLER_WEIGHT as AUTOCYCLER_WEIGHT_FLYE        } from '../../../modules/local/autocycler/weight/main'
include { FLYE                   } from '../../../modules/nf-core/flye/main'
include { METAMDBG_ASM           } from '../../../modules/nf-core/metamdbg/asm/main'
include { AUTOCYCLER_METAMDBGFILTER                          } from '../../../modules/local/autocycler/metamdbgfilter/main'
include { AUTOCYCLER_PLASSEMBLER                             } from '../../../modules/local/autocycler/plassembler/main'
include { RAVEN                  } from '../../../modules/nf-core/raven/main'
include { STAGEASSEMBLIES        } from '../../../modules/local/stageassemblies/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow DRAFT_ASSEMBLY {

    take:
        reads

    main:
        def assemblers = assemblersForMode(params.assembler_mode)
        log.info "Assemblers (--assembler_mode ${params.assembler_mode}): ${assemblers.join(', ')}"

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
        flye_assembly      = FLYE(ch_assembler_reads.filter { 'flye' in assemblers }, params.flye_mode)
        metamdbg_assembly  = METAMDBG_ASM(ch_assembler_reads.filter { 'metamdbg' in assemblers }, params.metamdbg_input_type)
        metamdbg_filtered  = AUTOCYCLER_METAMDBGFILTER(metamdbg_assembly.contigs)
        raven_assembly     = RAVEN(ch_assembler_reads.filter { 'raven' in assemblers })
        miniasm_assembly   = AUTOCYCLER_MINIASM(
            ch_assembler_reads.filter      { 'miniasm' in assemblers },
            ch_assembler_genomesize.filter { 'miniasm' in assemblers }
        )
\       myloasm_assembly   = AUTOCYCLER_MYLOASM(ch_assembler_reads.filter { 'myloasm' in assemblers })
        canu_assembly      = AUTOCYCLER_CANU(
            ch_assembler_reads.filter      { 'canu' in assemblers },
            ch_assembler_genomesize.filter { 'canu' in assemblers }
        )

        def plassembler_per_subsample = params.assembler_mode?.toString()?.toLowerCase() == 'fast'
        ch_reads_for_plassembler = (plassembler_per_subsample ? ch_subsampled_with_size : reads_with_size)
            .map { meta, reads, size -> [ meta, reads, size ] }
            .filter { 'plassembler' in assemblers }
        plassembler_assembly     = AUTOCYCLER_PLASSEMBLER(ch_reads_for_plassembler)

        /*
        --------------------------------------------------------
        Collect assemblies per barcode and weight for Autocycler
        --------------------------------------------------------
        */
        plassembler_fasta_remapped = plassembler_assembly.fasta
            .map { meta, fasta ->
                def barcode = meta.barcode ?: meta.id     // NEW (fast): per-subsample runs already carry barcode
                [ [id: "${meta.id}_plassembler", barcode: barcode], fasta ]
            }

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
            .mix(canu_assembly.fasta) 
            .mix(myloasm_assembly.fasta)
            .map { meta, fasta -> [ meta.barcode, fasta ] }
            .groupTuple(remainder: true)
            .map { barcode, fastas -> [ [id: barcode], fastas ] }

        assemblies = STAGEASSEMBLIES(ch_all_assemblies)

    emit:
        subsampled_reads = subsampled.subsampled_reads
        assemblies       = assemblies.assemblies
        subsample_stats  = subsampled.stats
        normalized_reads = ch_reads_flat
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ASSEMBLER MODES  
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
def assemblerModes() {
    def standard = [ 'flye', 'metamdbg', 'miniasm', 'plassembler', 'raven' ]
    def extended = standard + [ 'canu' ]
    def fast     = standard + [ 'myloasm' ]                                     // NEW (fast)
    return [ standard: standard, extended: extended, fast: fast ]
}
def assemblersForMode(assembler_mode) {
    def modes = assemblerModes()
    def name = assembler_mode?.toString()?.toLowerCase()
    if (!modes.containsKey(name)) {
        error("Unknown --assembler_mode '${assembler_mode}'. Choose one of: ${modes.keySet().join(', ')}")
    }
    return modes[name]
}
