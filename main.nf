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
        --run_name           Short name for this run; output goes to
                            <analysis_base>/<run_name>
                            [default base: /mrsnStorage/projects/Autopolish/analysis]
        --outdir            Full output path, overrides --run_name if set

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
        --assembler_set     Assembler preset [default: standard]
                            standard: Flye, metaMDBG, miniasm, Plassembler, Raven
                            extended: standard + Canu
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
            --run_name my_run \\
            -profile singularity,slurm

        # POD5 input (full pipeline)
        nextflow run main.nf \\
            --input /path/to/pod5s/ \\
            --input_type pod5 \\
            --barcode_kit SQK-NBD114-96 \\
            --run_name my_run \\
            -profile singularity,slurm

+       # Add Canu to the assemblers
+       nextflow run main.nf \\
+           --input /path/to/fastqs/ \\
+           --input_type fastq \\
+           --assembler_set extended \\
+           --run_name my_run \\
+           -profile singularity,slurm
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
    // Validate required params up front, before anything tries to use them
    //
    def missing_params = []
    if (!params.input)       missing_params << '--input'
    if (!params.input_type)  missing_params << '--input_type'
    if (missing_params) {
        error "Missing required parameter(s): ${missing_params.join(', ')}\n" +
              "Run with --help to see usage."
    }

    def valid_input_types = ['fastq', 'bam', 'pod5']
    if (!(params.input_type in valid_input_types)) {
        error "Invalid --input_type '${params.input_type}'. Must be one of: ${valid_input_types.join(', ')}"
    }

    if (params.input_type == 'pod5' && !params.barcode_kit) {
        error "--barcode_kit is required when --input_type is 'pod5'."
    }

    if (!file(params.input).exists()) {
        error "Input path does not exist: ${params.input}"
    }

    //
    // Resolve outdir from run_name if not explicitly set
    //
    if (!params.outdir) {
        if (!params.run_name) {
            error "Provide --run_name or set --outdir directly."
        }
        params.outdir = "${params.analysis_base}/${params.run_name}"
    }

    def valid_assembler_sets = ['standard', 'extended']
        if (!(params.assembler_set?.toString()?.toLowerCase() in valid_assembler_sets)) {
            error "Invalid --assembler_set '${params.assembler_set}'. Must be one of: ${valid_assembler_sets.join(', ')}"
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