// Ported from epi2me-labs/wf-basecalling v1.5.9 (lib/signal/ingress.nf, workflow wf_dorado,
// and the report/watch parts of main.nf).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in LICENSE_ONT next to this file)
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    DORADO_BASECALLING
    POD5s -> Dorado basecalling in chunks -> Q-score filter -> dorado demux, the same
    steps wf-basecalling runs for simplex, barcoded, unaligned data. Also produces
    live HTML report and its --watch_path mode.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { DORADO_BASECALLER } from '../../../modules/local/dorado/basecaller/main'
include { QSFILTER          } from '../../../modules/local/qsfilter/main'
include { DORADO_DEMUX      } from '../../../modules/local/dorado/demux/main'
include { BASECALLVERSIONS  } from '../../../modules/local/basecallversions/main'
include { BASECALLSTATS     } from '../../../modules/local/basecallstats/main'
include { PROGRESSIVESTATS  } from '../../../modules/local/progressivestats/main'
include { BASECALLREPORT    } from '../../../modules/local/basecallreport/main'
include { STOPCONDITION     } from '../../../modules/local/stopcondition/main'

workflow DORADO_BASECALLING {

    take:
        pod5_dir     // folder with the run's POD5s 
        kit          // value channel: barcoding kit, e.g. 'SQK-NBD114-96'
        report_name  // value channel: name for the report, e.g. the run name

    main:
        if (!params.basecaller_cfg && !params.basecaller_model_path) {
            error "Basecalling needs a model: set --basecaller_cfg (e.g. dna_r10.4.1_e8.2_400bps_sup@v5.2.0) or --basecaller_model_path"
        }
        def model_dir = params.basecaller_model_path ? file(params.basecaller_model_path, type: 'dir', checkIfExists: true) : []
        if (params.basecaller_model_path) {
            log.warn "Overriding basecaller model with ${params.basecaller_model_path}"
        }

        def chunk_size = params.basecaller_chunk_size
        Integer chunk_idx = 0
        String stop_filename = "STOP.${workflow.sessionId}.pod5" // use the sessionId so resume works
        existing_pod5_chunks = channel
            .fromPath("${pod5_dir}/**.pod5", checkIfExists: true)

        // Define naming patterns
        // The default naming is: PAN00000_pass__abc012d4_wxy789z0_0.pod5
        def pattern_long = /[A-Z]{3}[0-9]{5}_(pass|fail)__[0-9a-zA-Z]{8}_[A-Za-z0-9]{8}_[0-9]*/
        // The alternative naming is: PAN00000_abc012d4_0.pod5
        def pattern_short = /[A-Z]{3}[0-9]{5}_[0-9a-zA-Z]{8}_[0-9]*/

        if (params.watch_path) {
            // watch input path for more pod5s
            if (params.read_limit) {
                log.warn "Watching ${pod5_dir} for new pod5 files, until ${params.read_limit} reads have been observed."
                log.warn "To stop this workflow early, create: ${pod5_dir}/${stop_filename}"
            }
            else {
                log.warn "Watching ${pod5_dir} for new pod5 files indefinitely."
                log.warn "To stop this workflow create: ${pod5_dir}/${stop_filename}"
            }
            watch_pod5_chunks = channel
                .watchPath("${pod5_dir}/**.pod5")
                .until { it.name == stop_filename }
            ready_pod5_chunks = existing_pod5_chunks
                .concat(watch_pod5_chunks)
                .buffer(size: chunk_size, remainder: true)
                .map { pod5s -> [ chunk_idx++, pod5s ] }
        } else {
            // Group POD5s from the same flow cell, run and pass/fail into chunks, so each
            // Dorado task gets related files. Files with other names are chunked as they come.
            existing_pod5_chunks
                .branch {
                    pattern_long: it.baseName ==~ pattern_long
                    pattern_short: it.baseName ==~ pattern_short
                    no_pattern: true
                }.set { branched_patterns }
            branched_patterns.pattern_long
                .map { filename ->
                    def fields = filename.baseName.split("_")
                    [ fields[-1] as int, fields[0], fields[3], fields[1], filename ]
                }
                .mix(
                    branched_patterns.pattern_short
                        // short names have no pass/fail, so treat all as pass
                        .map { filename ->
                            def fields = filename.baseName.split("_")
                            [ fields[-1] as int, fields[0], fields[1], 'pass', filename ]
                        }
                )
                // chunk number = floor(pod5 index / chunk size), first so grouping clusters by it
                .map { pod5_index, cell_id, run_id, pass, pod5 ->
                    [ Math.floor(pod5_index / chunk_size), cell_id, run_id, pass, pod5 ]
                }
                .groupTuple(by: [0, 1, 2, 3])
                .map { pod5_index, cell_id, run_id, pass, pod5s -> pod5s }
                .mix(
                    branched_patterns.no_pattern
                        .buffer(size: chunk_size, remainder: true)
                )
                // Replace the chunk number with a new progressive numbering
                .map { pod5s -> [ chunk_idx++, pod5s ] }
                .set { ready_pod5_chunks }
        }

        DORADO_BASECALLER(
            ready_pod5_chunks.map { idx, pod5s -> [ [ id: "chunk${idx}" ], pod5s ] },
            params.basecaller_cfg ?: '',
            model_dir,
            kit
        )

        QSFILTER(DORADO_BASECALLER.out.ubam, params.qscore_filter)

        // Demultiplex once every chunk is done (in watch mode: once the watch has stopped)
        DORADO_DEMUX(QSFILTER.out.pass.map { meta, cram -> cram }.collect())

        //
        // Live report: stats per chunk, added to a running total, report rebuilt each time
        //
        BASECALLVERSIONS()
        ch_params_json = channel.of(groovy.json.JsonOutput.toJson(params))
            .collectFile(name: 'params.json')
            .first()  // value channel, so the report can be rebuilt after every chunk
        BASECALLSTATS(QSFILTER.out.pass, report_name)
        ch_stats = PROGRESSIVESTATS.scan(BASECALLSTATS.out.json)
        BASECALLREPORT(ch_stats, BASECALLVERSIONS.out.versions, ch_params_json, report_name)

        // Watch mode: stop once --read_limit reads have been called
        if (params.watch_path && params.read_limit) {
            STOPCONDITION(ch_stats, stop_filename, params.read_limit).first().subscribe {
                log.info "Creating STOP file: '${stop_filename}'"
            }
        }

    emit:
        bams   = DORADO_DEMUX.out.bams.flatten()  // .../barcodeNN/*.bam, one or more per barcode
        report = BASECALLREPORT.out.html          // updated after every chunk
        fail   = QSFILTER.out.fail                // [ meta, chunkN.fail.cram ], reads below --qscore_filter
}
