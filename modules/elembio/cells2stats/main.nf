process CELLS2STATS {
    tag "$meta.id"
    label 'process_high'
    scratch true

    container "${params.c2s_container_url}:${params.c2s_container_tag}"

    input:
    tuple val(meta), val(run_dir)
    path run_panel
    path run_manifest
    path segmentation
    path tca_manifest

    output:
    // Cells2Stats outputs
    tuple val(meta), path("AverageNormWellStats.csv")               , optional: true, emit: average_norm_well_stats_csv
    tuple val(meta), path("RawCellStats.csv")                       , emit: raw_cell_stats_csv
    tuple val(meta), path("RawCellStats.parquet")                   , emit: raw_cell_stats_parquet
    tuple val(meta), path("RunStats.json")                          , optional: true, emit: run_stats_json
    tuple val(meta), path("RunParameters.json")                     , optional: true, emit: run_parameters_json
    tuple val(meta), path("Panel.json")                             , optional: true, emit: panel_json
    tuple val(meta), path("RunManifest.json")                       , optional: true, emit: run_manifest_json
    tuple val(meta), path("RunManifest.csv")                        , optional: true, emit: run_manifest_csv
    tuple val(meta), path("Versions.json")                          , optional: true, emit: versions_json
    // directories (captured as single path to avoid globbing hundreds of files)
    tuple val(meta), path("Wells")                                  , optional: true, emit: wells_dir
    // Per-tile rawreads parquets under Wells/<well>/<batch>/. Glob-emit 
    tuple val(meta), path("Wells/**/*_rawreads.parquet")            , optional: true, emit: rawreads_files
    tuple val(meta), path("CellSegmentation")                       , optional: true, emit: cell_segmentation
    tuple val(meta), path("AnalysisRegion")                         , optional: true, emit: analysis_region
    tuple val(meta), path("Logs.tar.gz")                            , optional: true, emit: program_logs_tar
    tuple val(meta), path("Logs")                                   , optional: true, emit: program_logs
    // SpecializedTarget batch outputs
    tuple val(meta), path("TargetCellAssignmentManifest.csv")       , optional: true, emit: target_cell_assignment_manifest_csv
    tuple val(meta), path("TargetCellAssignmentManifest.json")      , optional: true, emit: target_cell_assignment_manifest_json
    // c2s 1.4.0-rc8 renamed TargetCounts.json → SpecializedTargetedCounts.json.
    // Emit both as optional so pre-rc8 and rc8+ containers publish whichever exists.
    tuple val(meta), path("TargetCounts.json")                      , optional: true, emit: target_counts_json
    tuple val(meta), path("SpecializedTargetedCounts.json")         , optional: true, emit: specialized_targeted_counts_json
    // visualization — CytoCanvas v4 / cells2stats 1.4.0-rc12+ filenames.
    // Analyze writes these under SpatialData/ (not workdir root). Older
    // visualization.zip / *-index.json.gz are intentionally not declared.
    // Index globs use unique suffixes (`*.zarr-index.bin` ≠ `*.points-…`).
    tuple val(meta), path("SpatialData/cyto.viz")                   , optional: true, emit: cyto_viz
    tuple val(meta), path("SpatialData/cell-shapes-zarr.zip")       , optional: true, emit: cell_shapes
    tuple val(meta), path("SpatialData/nuclear-shapes-zarr.zip")    , optional: true, emit: nuclear_shapes
    tuple val(meta), path("SpatialData/points-zarr.zip")            , optional: true, emit: points
    tuple val(meta), path("SpatialData/*.{zarr-index.bin,points-zarr-index.bin,cell-shapes-zarr-index.bin,nuclear-shapes-zarr-index.bin}"), optional: true, emit: sdo_index
    // spatial data outputs — `*.zarr.zip` is the SDO archive only (viz sidecars
    // are the exact SpatialData/*-zarr.zip emits above, not this glob).
    tuple val(meta), path("SpatialData")                            , optional: true, emit: spatial_data_dir
    tuple val(meta), path("SpatialData/*.zarr.zip")                 , optional: true, emit: spatial_data_zip
    tuple val(meta), path("SpatialData/*.zarr")                     , optional: true, emit: spatial_data_zarr
    // logs
    tuple val(meta), path("multiqc_report.html")                    , optional: true, emit: multiqc_report
    // versions.yml is process-identity-scoped (same content regardless of meta.id),
    // so emit as a bare path per nf-core convention. Keeps softwareVersionsToYAML
    // happy without consumer-side meta-stripping.
    path "versions.yml"                                             , emit: versions
    tuple val(meta), path("run.log")                                , emit: run_log
    // Curated small-metadata mirror for downstream tools (build-spatialdata
    // --c2s-dir). Contains only the named files in the allowlist below —
    // bulk artefacts like RawCellStats.* and Wells/ are excluded on purpose.
    tuple val(meta), path("metrics")                                , emit: metrics_dir

    when:
    task.ext.when == null || task.ext.when

    script:
    // Per nf-core convention, all user-configurable CLI flags are composed by
    // the consumer pipeline's conf/modules.config via task.ext.args. See
    // https://gitlab.com/elembio/analysis/elembio-nf-modules#module-configuration-via-taskextargs
    def args             = task.ext.args ?: ''
    def tar_logs         = task.ext.tar_logs ?: false

    // Path inputs that the module knows the CLI flag for
    def panel            = run_panel    ? "--panel ${run_panel}"                : ''
    def run_manifest_opt = run_manifest ? "--run-manifest ${run_manifest}"      : ''
    def segmentation_opt = segmentation ? "--segmentation ${segmentation}"      : ''
    def tca_manifest_opt = tca_manifest ? "--tca-manifest ${tca_manifest}"      : ''

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Executing Cells2Stats (analyze)..."
    echo "Container: ${task.container}"

    cells2stats analyze \\
        ${args} \\
        -j ${task.cpus} \\
        --output . \\
        ${panel} \\
        ${run_manifest_opt} \\
        ${segmentation_opt} \\
        ${tca_manifest_opt} \\
        ${run_dir}

    # Ensure directory outputs exist (cells2stats may not create all of them)
    mkdir -p Wells CellSegmentation Logs

    # Clean up empty bowtie-build logs
    rm -rf Logs/bowtie-build/

    if [ "${tar_logs}" = "true" ]; then
        tar czf Logs.tar.gz Logs/
        rm -rf Logs/
    fi

    # Curated small-metadata mirror for build-spatialdata --c2s-dir.
    # Top-level files only; denylist bulk extensions; 100 MB size cap.
    # Counts JSON is exempt from the size cap.
    mkdir -p metrics
    for f in *; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *.parquet|*.bam|*.bai|*.cram|*.crai|*.sam|*.fastq.gz|*.fq.gz|*.fastq|*.fq) continue ;;
            SpecializedTargetedCounts.json|TargetCounts.json)
                ln -sf "../\$f" "metrics/\$f"
                continue
                ;;
        esac
        size=\$(stat -c%s "\$f" 2>/dev/null || echo 0)
        [ "\$size" -gt 104857600 ] && continue
        ln -sf "../\$f" "metrics/\$f"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: \$(cells2stats -v | sed -e "s/,//g" | awk '{print \$3}')
    END_VERSIONS
    """

    stub:
    """
    touch RawCellStats.csv
    touch RawCellStats.parquet
    touch RunStats.json
    touch RunParameters.json
    touch Panel.json
    touch RunManifest.json
    touch RunManifest.csv
    touch Versions.json
    mkdir -p Wells CellSegmentation AnalysisRegion Logs
    touch run.log

    mkdir -p metrics
    for f in *; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *.parquet|*.bam|*.bai|*.cram|*.crai|*.sam|*.fastq.gz|*.fq.gz|*.fastq|*.fq) continue ;;
            SpecializedTargetedCounts.json|TargetCounts.json)
                ln -sf "../\$f" "metrics/\$f"
                continue
                ;;
        esac
        size=\$(stat -c%s "\$f" 2>/dev/null || echo 0)
        [ "\$size" -gt 104857600 ] && continue
        ln -sf "../\$f" "metrics/\$f"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: stub
    END_VERSIONS
    """
}
