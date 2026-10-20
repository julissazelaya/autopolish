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
        log.info "Assemblers for fungi (organism_group 'fungi' on the run sheet): ${fungiAssemblers().join(', ')}, 4 read subsets"

        // Fungi only get fungiAssemblers() (Flye); everything else gets --assembler_mode's
        def fungi_assemblers = fungiAssemblers()
        def runsAssembler = { meta, name ->
            meta.organism_group == 'fungi' ? name in fungi_assemblers : name in assemblers
        }

        /*
        -------------------------------
        Flatten reads per barcode
        -------------------------------
        */
        ch_reads_named = reads
            .map { meta, fastq ->
                def fq = fastq instanceof List ? fastq[0] : fastq
                // Run sheet reads (meta.run is set): the MRSN ID is meta.id.
                // Other inputs: the sample name comes from the file name, as before.
                def barcode = meta?.run ? meta.id : fq.name.toString()
                    .replaceAll('.fastq', '')
                    .replaceAll('.gz', '')
                [ [id: barcode], fq, meta?.organism_group ?: 'bacteria' ]
            }

        ch_reads_flat      = ch_reads_named.map { meta, fq, group -> [ meta, fq ] }
        ch_organism_groups = ch_reads_named.map { meta, fq, group -> [ meta.id, group ] }

        /*
        -------------------------------
        Genome size calculation
        -------------------------------
        */
        genome_size = AUTOCYCLER_GENOMESIZE(ch_reads_flat)

        reads_with_size = ch_reads_flat
            .join(genome_size.genome_size.map { meta, size -> [ meta, size.trim() ] })
            .map { meta, reads, size -> [ meta.id, meta, reads, size ] }
            .join(ch_organism_groups)
            .map { id, meta, reads, size, group -> [ meta + [organism_group: group], reads, size ] }

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
                [ [id: "${meta.id}_${sample_name}", barcode: meta.id, organism_group: meta.organism_group], fastq ]
            }

        ch_subsampled_with_size = ch_subsampled_flat
            .map { meta, fastq -> [ meta.barcode, meta, fastq ] }
            .combine(
                reads_with_size.map { meta, reads, size -> [ meta.id, size ] },
                by: 0
            )
            .map { barcode, meta, fastq, size -> [ meta, fastq, size ] }

        // One channel per assembler, holding only the subsamples that assembler runs on
        def forAssembler = { name ->
            ch_subsampled_with_size.filter { meta, fastq, size -> runsAssembler(meta, name) }
        }
        def readsFor = { name -> forAssembler(name).map { meta, fastq, size -> [ meta, fastq ] } }
        def sizeFor  = { name -> forAssembler(name).map { meta, fastq, size -> size } }

        /*
        -------------------------------
        Assemblers (parallel)
        -------------------------------
        */
        flye_assembly      = FLYE(readsFor('flye'), params.flye_mode)
        metamdbg_assembly  = METAMDBG_ASM(readsFor('metamdbg'), params.metamdbg_input_type)
        metamdbg_filtered  = AUTOCYCLER_METAMDBGFILTER(metamdbg_assembly.contigs)
        raven_assembly     = RAVEN(readsFor('raven'))
        miniasm_assembly   = AUTOCYCLER_MINIASM(readsFor('miniasm'), sizeFor('miniasm'))
        myloasm_assembly   = AUTOCYCLER_MYLOASM(readsFor('myloasm'))
        canu_assembly      = AUTOCYCLER_CANU(readsFor('canu'), sizeFor('canu'))

        def plassembler_per_subsample = params.assembler_mode?.toString()?.toLowerCase() == 'fast'
        ch_reads_for_plassembler = (plassembler_per_subsample ? ch_subsampled_with_size : reads_with_size)
            .filter { meta, reads, size -> runsAssembler(meta, 'plassembler') }
        plassembler_assembly     = AUTOCYCLER_PLASSEMBLER(ch_reads_for_plassembler)

        /*
        --------------------------------------------------------
        Collect assemblies per barcode and weight for Autocycler
        --------------------------------------------------------
        */
        plassembler_fasta_remapped = plassembler_assembly.fasta
            .map { meta, fasta ->
                def barcode = meta.barcode ?: meta.id
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
        subsampled_reads = subsampled.subsampled_reads.map { meta, fastqs -> [ [id: meta.id], fastqs ] }
        assemblies       = assemblies.assemblies
        subsample_stats  = subsampled.stats.map { meta, yaml -> [ [id: meta.id], yaml ] }
        normalized_reads = ch_reads_flat
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ASSEMBLER MODES  
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// Fungi (organism_group 'fungi' from the run sheet) are assembled with Flye only, on 4 read
// subsets, whatever --assembler_mode is. 
// The subset count for fungi is set in conf/modules.config (AUTOCYCLER_SUBSAMPLE).
def fungiAssemblers() {
    return [ 'flye' ]
}

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
