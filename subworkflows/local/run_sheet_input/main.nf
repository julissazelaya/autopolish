/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN_SHEET_INPUT
    Turns the lab's MinION/PromethION run sheet (.xlsx) into one meta map per barcode,
    checked against assets/schema_input.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { samplesheetToList } from 'plugin/nf-schema'
include { READRUNSHEET      } from '../../../modules/local/readrunsheet/main'

workflow RUN_SHEET_INPUT {

    take:
        run_sheet  // path to the run sheet (.xlsx) or sample sheet (.csv)

    main:
        def sheet_file = file(run_sheet)
        if (!sheet_file.exists()) {
            error "Run sheet not found: ${run_sheet}"
        }

        def schema = "${projectDir}/assets/schema_input.json"

        // One meta map per row: [ id:'MRSN489669', barcode:'barcode01', run:'PROM_Run_07', organism:..., ... ]
        if (sheet_file.name.toLowerCase().endsWith('.xlsx')) {
            READRUNSHEET(sheet_file)
            ch_samples = READRUNSHEET.out.csv
                .flatMap { csv ->
                    // Inside a channel, nf-schema's error only reaches .nextflow.log; print it here too
                    try {
                        samplesheetToList(csv, schema)
                    } catch (e) {
                        error((e.cause ?: e).message)
                    }
                }
                .map { row -> row[0] }
        } else if (sheet_file.name.toLowerCase().endsWith('.csv')) {
            // Already a sample sheet: checked at launch
            ch_samples = channel.fromList(samplesheetToList(sheet_file, schema)).map { row -> row[0] }
        } else {
            error "Run sheet must be .xlsx or .csv: ${run_sheet}"
        }

        ch_samples
            .map { meta -> meta.organism_group }
            .collect()
            .subscribe { groups ->
                log.info "Run sheet ${sheet_file.name}: ${groups.size()} samples (" +
                    groups.countBy { it }.collect { group, n -> "${n} ${group}" }.join(', ') + ")"
            }

        // An abbreviated genus ('K. pneumoniae') is grouped as fungi only if its species is in
        // FUNGAL_SPECIES in bin/read_run_sheet.py; list the rest so a missing fungus is noticed
        ch_samples
            .filter { meta -> meta.organism_group == 'bacteria' && meta.organism ==~ /(?i)[a-z]\.[ _].*/ }
            .map { meta -> "${meta.id} (${meta.organism})" }
            .collect()
            .subscribe { names ->
                log.warn "Grouped as bacteria from an abbreviated genus name; check none are fungi: ${names.join(', ')}"
            }

        // The barcoding kit from the run sheet header, for Dorado. One kit per run.
        ch_kit = ch_samples
            .map { meta -> meta.kit }
            .unique()
            .collect()
            .map { kits ->
                kits = kits.findAll { it }
                if (kits.size() != 1) {
                    error "Run sheet ${sheet_file.name} should name one barcoding kit (found: ${kits ?: 'none'}). Fill in 'Barcoding Kit:' or use --barcode_kit"
                }
                kits[0]
            }

    emit:
        samples = ch_samples  // [ meta ], one per barcode
        kit     = ch_kit      // e.g. 'SQK-NBD114-96'
}
