// Ported from epi2me-labs/wf-basecalling v1.5.9 (main.nf, process stopCondition).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)
//
// Watch mode: once --read_limit reads have been called, write the STOP file that ends the
// watch. conf/modules.config publishes it into the POD5 folder that is being watched.

process STOPCONDITION {
    label 'process_single'
    container 'ontresearch/wf-common:sha21d552f9910c575766e5d465fcb7b52fefda4b79'

    input:
    path json            // running total from PROGRESSIVESTATS
    val stop_filename
    val read_limit

    output:
    path "${stop_filename}", optional: true, emit: stop

    script:
    """
    #!/usr/bin/env python
    import json
    from pathlib import Path
    with open("${json}") as json_file:
        state = json.load(json_file)
        total = 0
        for k, v in state.items():
            total += v["total_reads"]
        if total >= ${read_limit}:
            p = Path("${stop_filename}")
            p.touch(exist_ok=False)
    """
}
