// Generate the cells2stats visualization from a built SpatialData archive
// (.zarr.zip) using the `cells2stats visualize` subcommand (rc8+ sectioned CLI;
// formerly `cells2stats --build-viz-from-SDO`).
//
// This is a separate process from CELLS2STATS because the invocation is
// fundamentally different: it takes a pre-built SDO zip as input (not a run
// directory) and is intended to run AFTER an upstream build-spatialdata step.
// Sharing the same container as CELLS2STATS
// (params.c2s_container_url:params.c2s_container_tag) since the binary is one
// and the same.
//
// `visualize` accepts --output, so artifacts are written into this work dir
// without needing stageInMode 'copy' (required for the old --build-viz-from-SDO
// path that wrote adjacent to the resolved real path of the input zip).
//
// Output filenames are the CytoCanvas v4 / cells2stats 1.4.0-rc12+ layout
// (`*-zarr.zip`, unique `*.{…}-zarr-index.bin` / `*.zarr-index.bin`, `cyto.viz`
// file_version 4.0.0). Older rc11 parquet / `*-index.json.gz` emits are
// intentionally not declared — Tower/remote work dirs only stage declared
// outputs for publishDir.

process CELLS2STATS_SPATIALDATABUILD_VIZ {
    tag "$meta.id"
    label 'process_high'

    container "${params.c2s_container_url}:${params.c2s_container_tag}"

    input:
    tuple val(meta), path(sdo_zip)

    output:
    tuple val(meta), path("cell-shapes-zarr.zip")          , optional: true, emit: cell_shapes
    tuple val(meta), path("nuclear-shapes-zarr.zip")       , optional: true, emit: nuclear_shapes
    tuple val(meta), path("points-zarr.zip")               , optional: true, emit: points
    tuple val(meta), path("cyto.viz")                      , optional: true, emit: cyto_viz
    // Unique suffixes: `*zarr-index.bin` also matches `*.points-zarr-index.bin`
    // etc. and collapses four indexes into one ambiguous glob.
    tuple val(meta), path("*.{zarr-index.bin,points-zarr-index.bin,cell-shapes-zarr-index.bin,nuclear-shapes-zarr-index.bin}"), optional: true, emit: sdo_index
    // versions.yml is process-identity-scoped (same content regardless of meta.id),
    // so emit as a bare path per nf-core convention. Keeps softwareVersionsToYAML
    // happy without consumer-side meta-stripping.
    path "versions.yml"                                    , emit: versions
    tuple val(meta), path("run_spatialdatabuild_viz.log")  , emit: run_log

    when:
    task.ext.when == null || task.ext.when

    script:
    // Per nf-core convention, all user-configurable CLI flags are composed by
    // the consumer pipeline's conf/modules.config via task.ext.args. See
    // https://gitlab.com/elembio/analysis/elembio-nf-modules#module-configuration-via-taskextargs
    def args = task.ext.args ?: ''

    """
    logfile=run_spatialdatabuild_viz.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Executing Cells2Stats (visualize)..."
    echo "Container: ${task.container}"
    echo "SDO: ${sdo_zip}"

    cells2stats visualize \\
        ${args} \\
        -j ${task.cpus} \\
        --output . \\
        ${sdo_zip}

    echo "Post-run directory listing:"
    ls -laR

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: \$(cells2stats -v | sed -e "s/,//g" | awk '{print \$3}')
    END_VERSIONS
    """

    stub:
    """
    sdo_base=\$(basename ${sdo_zip} .zarr.zip)
    touch cell-shapes-zarr.zip
    touch nuclear-shapes-zarr.zip
    touch points-zarr.zip
    touch cyto.viz
    touch "\${sdo_base}.zarr-index.bin"
    touch "\${sdo_base}.points-zarr-index.bin"
    touch "\${sdo_base}.cell-shapes-zarr-index.bin"
    touch "\${sdo_base}.nuclear-shapes-zarr-index.bin"
    touch run_spatialdatabuild_viz.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: stub
    END_VERSIONS
    """
}
