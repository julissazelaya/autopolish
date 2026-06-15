#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/autopolish
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/autopolish
    Website: https://nf-co.re/autopolish
    Slack  : https://nfcore.slack.com/channels/autopolish
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { AUTOPOLISH              } from './workflows/autopolish'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_autopolish_pipeline'
include { UTILS_NFCORE_PIPELINE   } from './subworkflows/nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE } from './subworkflows/nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    HELP TEXT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
def helpText() {
    return """
    =========================================
     nf-core/autopolish
    =========================================
    Automated bacterial genome assembly and polishing from Oxford Nanopore long-read data.

    Usage:
        nextflow run main.nf --input <dir> --input_type <type> --outdir <dir> [options]

    -----------------------------------------------------------------------
    REQUIRED
    -----------------------------------------------------------------------
        --input             Path to directory containing input files
        --input_type        Input file type: 'fastq', 'bam', or 'pod5'
        --outdir            Path to output directory [default: ./]

    -----------------------------------------------------------------------
    BASECALLING & DEMULTIPLEXING  (pod5 input only)
    -----------------------------------------------------------------------
        --barcode_kit       Barcode kit for demultiplexing [required for pod5]
                            e.g. 'SQK-NBD114-96'
        --dorado_model      Dorado basecalling model
                            [default: dna_r10.4.1_e8.2_400bps_sup@v5.2.0]
        --dorado_models_dir Path to local Dorado models directory
                            [default: /mrsnStorage/resources/dorado_models]
        --dorado_modifications
                            Dorado modification calling model [default: null]

    -----------------------------------------------------------------------
    ASSEMBLY
    -----------------------------------------------------------------------
        --min_read_depth    Minimum read depth for assembly [default: 50]
        --read_type         Read type passed to assemblers [default: ont_r10]
        --flye_mode         Flye assembly mode [default: --nano-hq]
        --canu_mode         Canu assembly mode [default: -nanopore]
        --metamdbg_input_type
                            metaMDBG input type [default: ont]
        --plassembler_db    Path to Plassembler database
                            [default: /mrsnStorage/resources/plassembler]

    -----------------------------------------------------------------------
    ALIGNMENT
    -----------------------------------------------------------------------
        --rg_tag            Read group tag for BAM header
                            [default: 'ID:A\\tDS:basecall_model=dna_r10.4.1_e8.2_400bps_sup@v5.2.0']

    -----------------------------------------------------------------------
    RESOURCES
    -----------------------------------------------------------------------
        --threads           Number of threads [default: 96]

    -----------------------------------------------------------------------
    BOILERPLATE
    -----------------------------------------------------------------------
        --help              Show this help message and exit
        --version           Show pipeline version and exit
        --email             Email address for pipeline completion notification
        --email_on_fail     Email address for pipeline failure notification
        --plaintext_email   Send plain-text email instead of HTML [default: false]
        --monochrome_logs   Disable ANSI colour in log output [default: false]
        --hook_url          Slack or Teams hook URL for notifications
        --publish_dir_mode  Method for publishing results [default: copy]

    -----------------------------------------------------------------------
    EXAMPLES
    -----------------------------------------------------------------------
        # FASTQ input (skip basecalling)
        nextflow run main.nf \\
            --input /path/to/fastqs/ \\
            --input_type fastq \\
            --outdir /path/to/results/ \\
            -profile singularity,slurm

        # POD5 input (full pipeline)
        nextflow run main.nf \\
            --input /path/to/pod5s/ \\
            --input_type pod5 \\
            --barcode_kit SQK-NBD114-96 \\
            --outdir /path/to/results/ \\
            -profile singularity,slurm

        # BAM input (skip basecalling, demux from BAM)
        nextflow run main.nf \\
            --input /path/to/bams/ \\
            --input_type bam \\
            --outdir /path/to/results/ \\
            -profile singularity,slurm
    =========================================
    """.stripIndent()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow NFCORE_AUTOPOLISH {

    main:
    AUTOPOLISH ()

    emit:
    versions = AUTOPOLISH.out.versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    if (params.help) {
        log.info helpText()
        exit 0
    }
    //
    // Print version and exit if required, dump params to JSON
    //
    UTILS_NEXTFLOW_PIPELINE (
            params.version,
            true,
            params.outdir,
            workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )
    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        args
    )
    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_AUTOPOLISH ()
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        params.hook_url,
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/