/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BARCODE_READS
    Demultiplexed BAMs (files under .../barcodeNN/) -> one FASTQ per barcode, named from
    the run sheet, using the nf-core samtools/cat and samtools/fastq modules. Used after DORADO_BASECALLING, and for the output of a
    separate wf-basecalling run (--input_type wf_basecalling).
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { SAMTOOLS_CAT   } from '../../../modules/nf-core/samtools/cat/main'
include { SAMTOOLS_FASTQ } from '../../../modules/nf-core/samtools/fastq/main'

workflow BARCODE_READS {

    take:
        ch_files    // demultiplexed BAM files; the barcode comes from the folder or file name
        ch_samples  // [ meta ] from RUN_SHEET_INPUT, with meta.id and meta.barcode

    main:
        ch_barcode_files = ch_files
            .map { f -> [ barcodeFromPath(f), f ] }
            .filter { barcode, f -> barcode != null }  // unclassified, merged and other files
            .groupTuple()

        // Match run sheet rows to barcodes; warn about either side missing
        ch_matched = ch_samples
            .map { meta -> [ meta.barcode, meta ] }
            .join(ch_barcode_files, remainder: true)
            .filter { barcode, meta, files ->
                if (meta == null) {
                    log.warn "Skipping ${barcode}: not on the run sheet"
                    return false
                }
                if (files == null) {
                    log.warn "No reads found for ${barcode} (${meta.id})"
                    return false
                }
                return true
            }
            // single_end: nanopore reads have no read 1/read 2, so samtools fastq writes them to *_other.fastq.gz
            .map { barcode, meta, files -> [ meta + [ single_end: true ], files.sort { it.name } ] }
            .branch { meta, bams ->
                several: bams.size() > 1
                one: true
            }

        // A barcode can have more than one BAM (e.g. several flow cells): merge those first
        SAMTOOLS_CAT(ch_matched.several)
        ch_bam = SAMTOOLS_CAT.out.bam
            .mix(ch_matched.one.map { meta, bams -> [ meta, bams[0] ] })

        SAMTOOLS_FASTQ(ch_bam, false)

    emit:
        fastq = SAMTOOLS_FASTQ.out.other  // [ meta, <MRSN>_other.fastq.gz ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// .../barcode01/x.bam or ..._barcode01.bam -> 'barcode01'; files without a barcode -> null.
// Only BAM files are kept.
//
def barcodeFromPath(f) {
    if (!f.name.endsWith('.bam')) {
        return null
    }
    def m = f.parent.name =~ /(?i)^(?:barcode|bc|nb)0*(\d+)$/
    if (!m) {
        m = f.name =~ /(?i)barcode0*(\d+)/
    }
    return m ? String.format('barcode%02d', m[0][1] as int) : null
}
