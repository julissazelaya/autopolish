/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { BASECALLING     } from '../subworkflows/local/basecalling/main'
include { DEMUX           } from '../subworkflows/local/demux/main'
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

    /*
    ----------------------------------------
    Input handling
    ----------------------------------------
    */
    if (params.fastq) {
        /*
        FASTQ input mode — skip basecalling and demultiplexing
        */
        channel.fromPath("${params.fastq}/*.fastq*", checkIfExists: true)
            .map { fastq ->
                def barcode_id = fastq.name.toString()
                    .replaceAll('.bam.fastq', '')
                    .replaceAll('.fastq.gz', '')
                    .replaceAll('.fastq', '')
                [ [id: barcode_id], fastq ]
            }
            .filter { meta, fastq -> !fastq.name.contains('unclassified') }
            .set { ch_reads }
    } else if (params.bam) {
        /*
        BAM input mode — skip basecalling, feed existing BAMs into demux
        */
        channel.fromPath("${params.bam}/*.bam", checkIfExists: true)
            .map { bam -> [ [id: 'merged'], bam ] }
            .groupTuple()
            .set { ch_bam_input }
        demuxed  = DEMUX(ch_bam_input)
        ch_reads = demuxed.reads
    } else if (params.pod5) {
        /*
        pod5 input mode — full pipeline from raw signal files
        */
        channel.fromPath("${params.pod5}/*.pod5", checkIfExists: true)
            .map { file -> [ [id: file.baseName], file ] }
            .set { ch_pod5 }
        basecalled = BASECALLING(ch_pod5)
        demuxed    = DEMUX(basecalled.bam)
        ch_reads   = demuxed.reads
    } else {
        error "Please specify either --pod5, --bam, or --fastq as input"
    }
    /*
    ----------------------------------------
    Workflow
    ----------------------------------------
    */
    draft      = DRAFT_ASSEMBLY(ch_reads)
    autocycler = AUTOCYCLER(draft.assemblies)

    aligned = ALIGNMENT(
        autocycler.consensus_assembly,
        ch_reads
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
