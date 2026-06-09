//
// Subworkflow with functionality specific to the nf-core/autopolish pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Create channel from input file provided through params.input
    //

    channel
        .fromPath(params.input)
        .splitCsv(header: true, strip: true)
        .map { row ->
            [[id:row.sample], row.fastq_1, row.fastq_2]
        }
        .map {
            meta, fastq_1, fastq_2 ->
                if (!fastq_2) {
                    return [ meta.id, meta + [ single_end:true ], [ fastq_1 ] ]
                } else {
                    return [ meta.id, meta + [ single_end:false ], [ fastq_1, fastq_2 ] ]
                }
        }
        .groupTuple()
        .map { samplesheet ->
            validateInputSamplesheet(samplesheet)
        }
        .map {
            meta, fastqs ->
                return [ meta, fastqs.flatten() ]
        }
        .set { ch_samplesheet }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications

    main:
    summary_params = [:]

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                []
            )
        }

        completionSummary(monochrome_logs)
        if (hook_url) {
            imNotification(summary_params, hook_url)
        }
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Validate channels from input samplesheet
//
def validateInputSamplesheet(input) {
    def (metas, fastqs) = input[1..2]

    // Check that multiple runs of the same sample are of the same datatype i.e. single-end / paired-end
    def endedness_ok = metas.collect{ meta -> meta.single_end }.unique().size == 1
    if (!endedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must be of the same datatype i.e. single-end or paired-end: ${metas[0].id}")
    }

    return [ metas[0], fastqs ]
}
//
/// Generate help text for the pipeline
//
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
        --outdir            Path to output directory

    -----------------------------------------------------------------------
    BASECALLING & DEMULTIPLEXING  (pod5 input only)
    -----------------------------------------------------------------------
        --barcode_kit       Barcode kit used for demultiplexing [required for pod5]
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
        --hook_url          Slack/Teams hook URL for notifications
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
//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = [
            "Tools used in the workflow included:",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
