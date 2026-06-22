/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { AUTOCYCLER_CLUSTER     } from '../../../modules/nf-core/autocycler/cluster/main'
include { AUTOCYCLER_COMBINE     } from '../../../modules/nf-core/autocycler/combine/main'
include { AUTOCYCLER_CLEAN       } from '../../../modules/local/autocycler/clean/main'
include { AUTOCYCLER_COMPRESS    } from '../../../modules/nf-core/autocycler/compress/main'
include { AUTOCYCLER_RESOLVE     } from '../../../modules/nf-core/autocycler/resolve/main'
include { AUTOCYCLER_SUBSAMPLE   } from '../../../modules/nf-core/autocycler/subsample/main'
include { AUTOCYCLER_TRIM        } from '../../../modules/nf-core/autocycler/trim/main'
include { AUTOCYCLER_GFA2FASTA   } from '../../../modules/local/autocycler/gfa2fasta/main'
include { DNAAPLER               } from '../../../modules/local/dnaapler/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow AUTOCYCLER {
    take:
        assemblies

    main:
        autocycler_compressed = AUTOCYCLER_COMPRESS(assemblies)
        autocycler_clustered  = AUTOCYCLER_CLUSTER(autocycler_compressed.gfa)

        autocycler_clustered.clusters
            .transpose()
            .map { meta, gfa ->
                def cluster_name = gfa.name.toString().replaceAll('.gfa', '')
                def cluster_id   = "${meta.id}_${cluster_name}"
                [ [id: cluster_id, barcode: meta.id], gfa ]
            }
            .set { ch_clusters }

        autocycler_trimmed  = AUTOCYCLER_TRIM(ch_clusters)
        autocycler_resolved = AUTOCYCLER_RESOLVE(autocycler_trimmed.gfa)

        autocycler_resolved.resolved
            .map { meta, gfa -> [ [id: meta.barcode], gfa ] }
            .groupTuple()
            .set { ch_resolved }

        autocycler_combined  = AUTOCYCLER_COMBINE(ch_resolved)
        autocycler_cleaned   = AUTOCYCLER_CLEAN(autocycler_combined.gfa)
        reoriented_assembly  = DNAAPLER(autocycler_cleaned.gfa)
        fasta_assembly       = AUTOCYCLER_GFA2FASTA(reoriented_assembly.gfa)

    emit:
        consensus_assembly = fasta_assembly.fasta
        consensus_stats    = autocycler_combined.stats
}