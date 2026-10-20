// Ported from epi2me-labs/wf-basecalling v1.5.9 (main.nf, process getVersions).
// This Source Code Form is subject to the terms of the Oxford Nanopore
// Technologies PLC. Public License, v. 1.0. Full licence can be found
// obtained from support@nanoporetech.com (copy in subworkflows/local/dorado_basecalling/LICENSE_ONT)

process BASECALLVERSIONS {
    label 'process_single'
    container 'ontresearch/dorado:shac8f356489fa8b44b31beba841b84d2879de2088e'

    output:
    path "versions.txt", emit: versions  // name,version lines for the basecalling report

    script:
    """
    dorado --version 2>&1 | head -n1 | sed 's/^/dorado,/' >> versions.txt
    samtools --version | head -n1 | sed 's/^samtools /samtools,/' >> versions.txt
    """

    stub:
    """
    echo 'dorado,stub' > versions.txt
    """
}
