#!/usr/bin/env bash
# Bump every Autocycler module in nf-core-autopolish from 0.5.2 to 0.8.0, and make sure the
# new Singularity image is in the shared cache.
# Run from the pipeline root:  bash bump_autocycler.sh
# Only the container tags and conda pins change; your existing customisations stay as they are.
set -euo pipefail

OLD_TAG='autocycler:0.5.2--h3ab6199_0'
NEW_TAG='autocycler:0.8.0--h79ce301_0'      # bioconda build autocycler-0.8.0-h79ce301_0
OLD_CONDA='autocycler=0.5.2'
NEW_CONDA='autocycler=0.8.0'

# Singularity image cache (override with: CACHE=/some/dir bash bump_autocycler.sh)
CACHE="${CACHE:-$HOME/mrsnStorage/dev/images/singularity/cache}"
# The file name Nextflow looks for in the cache for the module's depot.galaxyproject.org URL
IMAGE_URL="https://depot.galaxyproject.org/singularity/${NEW_TAG}"
IMAGE_FILE="depot.galaxyproject.org-singularity-${NEW_TAG/:/-}.img"

files=$(ls modules/nf-core/autocycler/*/main.nf  modules/nf-core/autocycler/*/environment.yml \
           modules/local/autocycler/*/main.nf    modules/local/autocycler/*/environment.yml 2>/dev/null || true)

echo "Updating:"
for f in $files; do
    if grep -q -e "$OLD_TAG" -e "$OLD_CONDA" "$f"; then
        sed -i -e "s/${OLD_TAG}/${NEW_TAG}/g" -e "s/${OLD_CONDA}/${NEW_CONDA}/g" "$f"
        echo "  $f"
    fi
done

echo
echo "Autocycler references still not on 0.8.0 (multi-tool or custom containers; update these by hand):"
leftover=$( { grep -rn -i "autocycler" modules/ subworkflows/ conf/ 2>/dev/null || true; } \
    | { grep -E "container|depot|quay|wave|seqera|docker|singularity|=0\.[0-9]|:0\.[0-9]" || true; } \
    | { grep -v "0\.8\.0" || true; } )
echo "${leftover:-  none}"

echo
if [[ -s "${CACHE}/${IMAGE_FILE}" ]]; then
    echo "Image already cached: ${CACHE}/${IMAGE_FILE}"
elif [[ -d "$CACHE" ]] && command -v singularity >/dev/null; then
    echo "Pulling ${IMAGE_URL}"
    echo "  into ${CACHE}/${IMAGE_FILE}"
    singularity pull --name "${CACHE}/${IMAGE_FILE}" "$IMAGE_URL"
else
    echo "Couldn't pull the image here (no cache dir at ${CACHE}, or no singularity). On a node with both, run:"
    echo "  singularity pull --name ${CACHE}/${IMAGE_FILE} ${IMAGE_URL}"
fi

echo
echo "Next: record the change in each nf-core module's patch file, e.g."
echo "  for m in cluster combine compress resolve subsample trim; do nf-core modules patch autocycler/\$m; done"
