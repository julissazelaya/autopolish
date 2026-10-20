/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { RUN_SHEET_INPUT    } from '../subworkflows/local/run_sheet_input/main'
include { DORADO_BASECALLING } from '../subworkflows/local/dorado_basecalling/main'
include { BARCODE_READS      } from '../subworkflows/local/barcode_reads/main'include { DEMUX           } from '../subworkflows/local/demux/main'
include { DRAFT_ASSEMBLY  } from '../subworkflows/local/draft_assembly/main'
include { AUTOCYCLER      } from '../subworkflows/local/autocycler/main'
include { ALIGNMENT       } from '../subworkflows/local/alignment/main'
include { POLISHING       } from '../subworkflows/local/polishing/main'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_autopolish_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow AUTOPOLISH {

    main:
    ch_versions = channel.empty()

    if (params.input_type == 'fastq') {
        channel.fromPath("${params.input}/*.fastq*", checkIfExists: true)
            .map { fastq ->
                def barcode_id = fastq.name.toString()
                    .replaceAll('.bam.fastq', '')
                    .replaceAll('.fastq.gz', '')
                    .replaceAll('.fastq', '')
                    .replaceAll('\\.bam$', '')
                [ [id: barcode_id], fastq ]
            }
            .filter { meta, fastq -> !fastq.name.contains('unclassified') }
            .set { ch_reads }
        
    } else if (params.input_type == 'bam') {
        channel.fromPath("${params.input}/*.bam", checkIfExists: true)
            .map { bam -> [ [id: 'merged'], bam ] }
            .groupTuple()
            .set { ch_bam_input }
        demuxed  = DEMUX(ch_bam_input)
        ch_reads = demuxed.reads

    } else if (params.input_type in ['pod5', 'wf_basecalling']) {
        // The run sheet names each barcode (MRSN ID) and gives the barcoding kit
        if (!params.run_sheet) {
            error "--input_type ${params.input_type} needs --run_sheet (the run sheet .xlsx or a sample sheet .csv)"
        }
        RUN_SHEET_INPUT(params.run_sheet)

        if (params.input_type == 'pod5') {
            // Dorado basecalling + demux, ported from wf-basecalling
            ch_kit = params.barcode_kit ? channel.value(params.barcode_kit) : RUN_SHEET_INPUT.out.kit
            DORADO_BASECALLING(
                params.input,
                ch_kit,
                RUN_SHEET_INPUT.out.samples.first().map { meta -> meta.run }
            )
            ch_demuxed = DORADO_BASECALLING.out.bams
        } else {
            // Output of a separate wf-basecalling run (its --out_dir)
            ch_demuxed = channel.fromPath("${params.input}/**.bam", checkIfExists: true)
        }

        BARCODE_READS(ch_demuxed, RUN_SHEET_INPUT.out.samples)
        ch_reads = BARCODE_READS.out.fastq   // [ meta, MRSNxxxxxx.fastq.gz ]
    }
    
    /*
    ----------------------------------------
    Workflow
    ----------------------------------------
    */
    draft      = DRAFT_ASSEMBLY(ch_reads)
    autocycler = AUTOCYCLER(draft.assemblies, draft.subsample_stats, draft.normalized_reads)

    aligned = ALIGNMENT(
        autocycler.consensus_assembly,
        draft.normalized_reads
    )

    polished = POLISHING(
        aligned.aligned_assembly,
        autocycler.consensus_assembly
    )

    /*
    ----------------------------------------
    Collate and save software versions
    ----------------------------------------
    */
    def topic_versions = Channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'autopolish_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
