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
nextflow.preview.recursion = true   // live basecalling report (PROGRESSIVESTATS.scan)
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { AUTOPOLISH              } from './workflows/autopolish'
include { assemblerModes          } from './subworkflows/local/draft_assembly'
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
                            (for wf_basecalling: a wf-basecalling or MinKNOW output
                            folder with demultiplexed barcodeNN/*.bam)
        --input_type        Input file type: 'pod5', 'wf_basecalling', 'fastq'
        --run_name          Short name for this run; output goes to
                            <analysis_base>/<run_name>
                            [default base: /mrsnStorage/projects/Autopolish/analysis]
        --outdir            Full output path, overrides --run_name if set

    -----------------------------------------------------------------------
    RUN SHEET  (pod5 and wf_basecalling input)
    -----------------------------------------------------------------------
        --run_sheet         Run sheet (.xls) or sample sheet (.csv).
                            Names each barcode by MRSN ID and gives
                            the barcoding kit. Required for pod5 and wf_basecalling

    -----------------------------------------------------------------------
    BASECALLING & DEMULTIPLEXING  (pod5 input only; as in wf-basecalling)
    -----------------------------------------------------------------------
        --basecaller_cfg    Dorado model
                            [default: dna_r10.4.1_e8.2_400bps_sup@v5.2.0]
        --basecaller_model_path
                            Dorado model folder; overrides --basecaller_cfg
                            (e.g. /mrsnStorage/resources/dorado_models/dna_r10.4.1_e8.2_400bps_sup@v5.2.0)
        --barcode_kit       Barcoding kit, e.g. 'SQK-NBD114-96'
                            [default: 'Barcoding Kit:' from the run sheet]
        --qscore_filter     Minimum mean read Q-score [default: 10]
        --basecaller_chunk_size
                            POD5 files per Dorado job [default: 25]
        --watch_path        Basecall new POD5s while the run is still sequencing
        --read_limit        With --watch_path: stop after this many reads

    -----------------------------------------------------------------------
    ASSEMBLY
    -----------------------------------------------------------------------
        --min_read_depth    Minimum read depth for assembly [default: 50]
        --read_type         Read type passed to assemblers [default: ont_r10]
        --flye_mode         Flye assembly mode [default: --nano-hq]
        --assembler_mode    Assemblers to run [default: standard]
                            standard  5 assemblers, 17 assemblies per sample
                                      Flye, metaMDBG, miniasm, Raven (x4 subsets)
                                      + Plassembler (x1, all reads)
                            extended  6 assemblers, 21 assemblies per sample
                                      standard + Canu (x4 subsets)
                            fast      6 assemblers, 12 assemblies per sample
                                      Flye, metaMDBG, miniasm, Myloasm, Plassembler,
                                      Raven (x2 subsets), as autocycler_fast.sh
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

        # POD5 input (full pipeline: basecall, demultiplex, name by run sheet, assemble)
        nextflow run main.nf \\
            --input /path/to/pod5s/ \\
            --input_type pod5 \\
            --run_sheet PROM_Run_07.xlsx \\
            --run_name my_run \\
            -profile singularity,slurm

        # POD5 input while the run is still sequencing; stop after 20 million reads
        nextflow run main.nf \\
            --input /path/to/pod5s/ \\
            --input_type pod5 \\
            --run_sheet PROM_Run_07.xlsx \\
            --watch_path --read_limit 20000000 \\
            --run_name my_run \\
            -profile singularity,slurm

        # Output of a separate wf-basecalling run
        nextflow run main.nf \\
            --input /path/to/wf-basecalling/output/ \\
            --input_type wf_basecalling \\
            --run_sheet PROM_Run_07.xlsx \\
            --run_name my_run \\
            -profile singularity,slurm

        # Add Canu to the assemblers
        nextflow run main.nf \\
            --input /path/to/fastqs/ \\
            --input_type fastq \\
            --assembler_mode extended \\
            --run_name my_run \\
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
    // Validate required params up front, before anything tries to use them
    //
    def missing_params = []
    if (!params.input)       missing_params << '--input'
    if (!params.input_type)  missing_params << '--input_type'
    if (missing_params) {
        error "Missing required parameter(s): ${missing_params.join(', ')}\n" +
              "Run with --help to see usage."
    }

    def valid_input_types = ['fastq', 'pod5']
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

    def valid_assembler_modes = assemblerModes().keySet()
    if (!(params.assembler_mode?.toString()?.toLowerCase() in valid_assembler_modes)) {
        error "Invalid --assembler_mode '${params.assembler_mode}'. Must be one of: ${valid_assembler_modes.join(', ')}"
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