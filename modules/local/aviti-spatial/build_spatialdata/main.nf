process BUILD_SPATIALDATA {
    tag "build_spatialdata"
    label 'process_high'
    scratch true

    container "${params.spatialdata_build_container_url}:${params.spatialdata_build_container_tag}"

    input:
    val run_id
    val run_dir
    val tile_args
    path wells_dirs, stageAs: "wells_parts/*"
    path genes_gtf, stageAs: "genes/*"
    path cellstats_parquet, stageAs: "c2s_dir/RawCellStats.parquet"
    path c2s_wells_dir, stageAs: "c2s_dir/Wells"
    path c2s_cell_segmentation, stageAs: "c2s_dir/CellSegmentation"
    path c2s_analysis_region, stageAs: "c2s_dir/AnalysisRegion"
    path c2s_metrics_dir, stageAs: "c2s_metrics"
    path b2f_metrics_dir, stageAs: "b2f_dir"
    path f2p_3p_metrics_dir, stageAs: "f2p_3p_dir"
    path intervals_metadata, stageAs: "intervals_metadata.tsv"
    path run_params_json,    stageAs: "run/RunParameters.json"
    path panel_json,         stageAs: "run/Panel.json"
    path manifest_csv,       stageAs: "run/RunManifest.csv"
    path manifest_json,      stageAs: "run/RunManifest.json"
    path provenance_json,    stageAs: "pipeline/Provenance.json"
    val proj_tiles

    output:
    path "*.zarr.zip"                                   , optional: true, emit: spatialdata_zip
    path "*.zarr"                                       , optional: true, emit: spatialdata_zarr
    path "debug_inputs.tar.gz"                          , optional: true, emit: debug_inputs
    path "*.log"                                        , emit: log 
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def do_zip = params.avsd_zip_spatialdata
    def debug_preserve = params.avsd_debug_preserve_inputs
    // Cap zip thread count: zip-store parallelism is I/O-bound and saturates
    // around 8-12 concurrent workers; beyond that threads idle without speedup.
    def zip_threads = Math.min(task.cpus as int, 12)

    // AnalysisRegion resolution: prefer explicit override; otherwise only pass
    // c2s_dir/AnalysisRegion when staged. Non-overlap runs ignore the flag.
    def analysis_region_override = params.analysis_region_dir ?: ''

    // Empty avsd_points_blocksize disables the read-time partition cap
    // (legacy upstream-row-group behavior); otherwise quote the value so
    // strings like '32 MiB' survive the shell pipeline.
    def points_blocksize = params.avsd_points_blocksize ?: ''
    def points_blocksize_arg = points_blocksize ? "--points-blocksize '${points_blocksize}'" : "--points-blocksize ''"

    // Match onboard aggregation-bin: POLARS_MAX_THREADS = worker count (Phase 2
    // is single-process); OMP/BLAS/MKL/NumExpr = small per-worker pool so Phase 1
    // OS threads ~= workers * 2 instead of workers * host cpu_count().
    def workers = task.cpus as int
    def per_worker_lib_threads = (params.avsd_per_worker_lib_threads ?: 2) as int

    """
    # Cap glibc per-thread arenas and drop trim threshold so freed memory is
    # returned to the OS rather than retained in arena fragmentation.  Critical
    # for keeping per-worker RSS bounded across the multi-phase build (images,
    # labels, shapes, points) on memory-constrained hosts (e.g. instrument).
    export MALLOC_ARENA_MAX=2
    export MALLOC_TRIM_THRESHOLD_=131072

    export POLARS_MAX_THREADS=${workers}
    export OMP_NUM_THREADS=${per_worker_lib_threads}
    export OPENBLAS_NUM_THREADS=${per_worker_lib_threads}
    export MKL_NUM_THREADS=${per_worker_lib_threads}
    export NUMEXPR_NUM_THREADS=${per_worker_lib_threads}

    logfile=build_spatialdata.log
    exec > >(tee \$logfile)
    exec 2>&1
    echo "SpatialData library thread caps: POLARS_MAX_THREADS=${workers}, OMP/OPENBLAS/MKL/NUMEXPR_NUM_THREADS=${per_worker_lib_threads}"

    # On failure, tar the staged input tree so it can be downloaded from the
    # task work dir and replayed locally. Projection is excluded — it's bulky
    # and recoverable via .command.run's nxf_stage S3 source paths. Off by
    # default; enable with --avsd_debug_preserve_inputs.
    _capture_inputs_on_failure() {
        local rc=\$?
        if [ "${debug_preserve}" = "true" ] && [ "\$rc" -ne 0 ]; then
            echo "Task failed (exit \$rc); capturing staged inputs to debug_inputs.tar.gz..."
            tar -czf debug_inputs.tar.gz \\
                --exclude='*/Projection' \\
                --ignore-failed-read \\
                polonies/ wells_parts/ genes/ c2s_dir/ c2s_metrics/ b2f_dir/ f2p_3p_dir/ run/ ${run_id}/ 2>/dev/null || true
            [ -f debug_inputs.tar.gz ] && ls -lh debug_inputs.tar.gz
        fi
        return \$rc
    }
    trap _capture_inputs_on_failure EXIT

    TASK_START=\$SECONDS

    echo "Running build-spatialdata..."
    echo "Inputs staged via Nextflow: run/ config, c2s_dir/, polonies/Wells/, genes/, b2f_dir/, f2p_3p_dir/ (Projection synced in-script)"

    ANALYSIS_REGION_ARG=""
    if [ -n "${analysis_region_override}" ]; then
        ANALYSIS_REGION_ARG="--analysis-region-dir ${analysis_region_override}"
        echo "Using explicit AnalysisRegion override: ${analysis_region_override}"
    fi

    # Soft-warn on missing optional config files. Channels with ifEmpty([])
    # cause NF to stage nothing for that input, matching the previous
    # `aws s3 cp ... || echo Warning` soft-failure behavior.
    mkdir -p run
    for f in RunParameters.json Panel.json RunManifest.csv RunManifest.json; do
        [ -f "run/\$f" ] || echo "Warning: run/\$f not staged (channel was empty)"
    done

    # Merge per-sample Wells trees from F2P SPLIT_POLONY_PARQUETS into
    # polonies/Wells/Well{well}/{batch}/{tile}_reads.parquet so discovery
    # takes the onboard is_combined=False path. Each SPLIT emit is named
    # {meta.id}_Wells (unique) to avoid NF input basename collision; contents
    # are still Well*/batch/*.parquet — merge preserves those parents.
    mkdir -p polonies/Wells
    if [ -d wells_parts ]; then
        for d in wells_parts/*; do
            [ -d "\$d" ] || continue
            echo "Merging Wells tree from \$d"
            cp -aL "\$d"/. polonies/Wells/
        done
    fi

    # Sync Projection in-script (NOT NF-staged). build-spatialdata's image
    # resolver expects projection images under Projection/Well<X>/, but NF
    # flat-glob staging dropped the Well<X>/ parent, yielding 0 images. aws
    # s3 sync preserves the directory tree; --force-glacier-transfer covers
    # Glacier-restored objects. proj_tiles (resolved tile IDs) drives the
    # tile --include filter; empty => sync the whole Projection tree.
    STEP_START=\$SECONDS
    echo "Syncing Projection from ${run_dir}/Projection (tiles: '${proj_tiles}')..."
    if [[ "${run_dir}" == s3://* ]]; then
        AWS_CMD=\$(which aws || echo "/usr/bin/aws")
        SYNC_ARGS=(--no-progress --force-glacier-transfer)
        if [ -n "${proj_tiles}" ]; then
            SYNC_ARGS+=(--exclude '*')
            for t in ${proj_tiles}; do SYNC_ARGS+=(--include "*\${t}*"); done
        fi
        \$AWS_CMD s3 sync "${run_dir}/Projection" run/Projection "\${SYNC_ARGS[@]}" \\
            || echo "Warning: Failed to sync Projection from ${run_dir}/Projection"
    elif [ -d "${run_dir}/Projection" ]; then
        # Local run_dir (dev): copy preserving Well<X>/ via cp --parents.
        WORK=\$PWD
        mkdir -p run/Projection
        if [ -n "${proj_tiles}" ]; then
            for t in ${proj_tiles}; do
                ( cd "${run_dir}/Projection" && find . -type f -name "*\${t}*" \\
                    -exec cp -L --parents {} "\$WORK/run/Projection/" \\; )
            done
        else
            cp -RL "${run_dir}/Projection/." run/Projection/
        fi
    else
        echo "Warning: ${run_dir}/Projection not found (not S3, not a local dir)"
    fi
    echo "Projection sync completed in \$((\$SECONDS - \$STEP_START))s"

    proj_count=\$(find run/Projection -type f 2>/dev/null | wc -l)
    echo "Projection files synced: \$proj_count"
    [ "\$proj_count" -eq 0 ] && echo "Warning: no Projection files synced"

    # Ensure c2s_dir/Wells exists — empty dirs don't survive scratch→S3 on AWS Batch
    mkdir -p c2s_dir/Wells

    # Overlay c2s curated small-metadata (RunStats.json, Versions.json, ...)
    # into c2s_dir/ so build-spatialdata's --c2s-dir auto-discovery picks them
    # up alongside the bulk artefacts (Wells/, RawCellStats.parquet,
    # CellSegmentation/, AnalysisRegion/) staged separately by Nextflow. Keeping
    # CellSegmentation and AnalysisRegion under c2s_dir/ guarantees SD-build
    # uses the same segmentation and per-tile masks c2s used to compute the
    # stats it also consumes (no silent divergence with run-dir copies).
    # Symlinks are relative so the layout stays self-contained if the work
    # dir is rehomed.
    if [ -d "c2s_metrics" ]; then
        echo "Overlaying c2s_metrics/ contents into c2s_dir/"
        for f in c2s_metrics/*; do
            [ -e "\$f" ] || continue
            bn=\$(basename "\$f")
            # Defensive: skip names that collide with the bulk stageAs entries
            case "\$bn" in
                Wells|CellSegmentation|AnalysisRegion|RawCellStats.parquet) continue ;;
            esac
            ln -sf "../c2s_metrics/\$bn" "c2s_dir/\$bn"
        done
    else
        echo "No c2s_metrics/ directory staged (unexpected — c2s always runs)"
    fi

    # Rename run/ to run_id so build-spatialdata names its output correctly
    # (build-spatialdata uses basename of --run-dir).
    mv run ${run_id}
    echo "Renamed run/ to ${run_id}/"

    # Build --batch-points-dir arguments from staged Wells tree.
    # Layout: polonies/Wells/Well{well}/{batch}/{tile_id}_reads.parquet
    echo "Staged polony Wells tree:"
    if [ -d polonies/Wells ]; then
        find polonies/Wells -type f -name '*_reads.parquet' 2>/dev/null | head -20 || true
        polony_count=\$(find polonies/Wells -type f -name '*_reads.parquet' 2>/dev/null | wc -l)
        unique_batches=\$(find polonies/Wells -mindepth 2 -maxdepth 2 -type d 2>/dev/null \\
            | xargs -r -n1 basename \\
            | sort -u)
    else
        echo "No polonies/Wells directory (no 3' batches)"
        polony_count=0
        unique_batches=""
    fi

    BATCH_POINTS_ARGS=""
    for batch in \$unique_batches; do
        BATCH_POINTS_ARGS="\$BATCH_POINTS_ARGS --batch-points-dir \${batch}:polonies/"
        echo "  Adding batch-points-dir: \${batch}:polonies/"
    done

    echo "Total polony files: \$polony_count"
    echo "Unique batches: \$(echo \$unique_batches | tr '\\n' ' ')"
    echo "BATCH_POINTS_ARGS: \$BATCH_POINTS_ARGS"
    
    # 3' args are conditional — genes GTF and merge-strategy-threeprime only apply to DISS runs
    THREE_PRIME_ARGS=""
    if [ -n "\$(ls genes/ 2>/dev/null)" ]; then
        THREE_PRIME_ARGS="--gtf-path ${genes_gtf} --merge-strategy-threeprime ${params.avsd_merge_strategy_three_prime_untargeted}"
        echo "3' inputs detected: adding --gtf-path and --merge-strategy-threeprime"
    else
        echo "No 3' inputs detected: skipping --gtf-path and --merge-strategy-threeprime"
    fi
    # Prefer the direct catalog from GENERATE_FEATURE_SAF when F2P_METRICS_DIR
    # never ran (no 3' FASTQs). build-spatialdata also auto-derives from
    # --f2p-3p-dir/genes/ when this flag is unset.
    if [ -f "intervals_metadata.tsv" ]; then
        THREE_PRIME_ARGS="\$THREE_PRIME_ARGS --threeprime-intervals-metadata-path intervals_metadata.tsv"
        echo "intervals_metadata.tsv staged: adding --threeprime-intervals-metadata-path"
    fi

    # Optional tool-dir inputs (b2f, f2p_3p). c2s is always present.
    TOOL_DIR_ARGS=""
    if [ -d "b2f_dir" ]; then
        TOOL_DIR_ARGS="\$TOOL_DIR_ARGS --b2f-dir b2f_dir"
        echo "b2f_dir detected: adding --b2f-dir"
    fi
    if [ -d "f2p_3p_dir" ]; then
        TOOL_DIR_ARGS="\$TOOL_DIR_ARGS --f2p-3p-dir f2p_3p_dir"
        echo "f2p_3p_dir detected: adding --f2p-3p-dir"
    fi
    if [ -d "pipeline" ]; then
        TOOL_DIR_ARGS="\$TOOL_DIR_ARGS --pipeline-provenance-dir pipeline"
        echo "pipeline provenance dir detected: adding --pipeline-provenance-dir"
    fi

    CMD="build-spatialdata \\
        --run-dir ${run_id} \\
        --output ${run_id}.zarr/ \\
        --overwrite \\
        --workers ${workers} \\
        --dask-write-threads ${params.avsd_dask_write_threads} \\
        ${points_blocksize_arg} \\
        --c2s-dir c2s_dir \\
        --segmentation-dir c2s_dir/CellSegmentation \\
        \$ANALYSIS_REGION_ARG \\
        \$THREE_PRIME_ARGS \\
        \$TOOL_DIR_ARGS \\
        \$BATCH_POINTS_ARGS \\
        ${tile_args} \\
        --merge-strategy-protein ${params.avsd_merge_strategy_protein} \\
        --merge-strategy-transcript ${params.avsd_merge_strategy_transcript} \\
        --merge-strategy-ops ${params.avsd_merge_strategy_ops} \\
        ${args}"

    echo "Command:"
    echo "\$CMD"
    echo ""

    STEP_START=\$SECONDS
    eval "\$CMD"
    echo "build-spatialdata completed in \$((\$SECONDS - \$STEP_START))s"

    if [ "${do_zip}" = "true" ]; then
        # Use 7zip in zip-store mode with explicit thread count for ~2.5-5x
        # faster packaging than single-threaded Info-ZIP on many-tiny-file zarr.
        # -mx=0 = store (no compression, same as `zip -0`).
        # Output is a standard ZIP readable by zarr.storage.ZipStore.
        # 7zip's "Scanning the drive:" line reports folder/file/byte counts, so
        # we skip pre-7zip du/find walks (each would re-walk the whole tree).
        STEP_START=\$SECONDS
        7z a -tzip -mx=0 -mmt=${zip_threads} ${run_id}.zarr.zip ${run_id}.zarr/
        echo "Zip completed in \$((\$SECONDS - \$STEP_START))s (threads=${zip_threads})"
        ls -lh ${run_id}.zarr.zip

        STEP_START=\$SECONDS
        rm -rf ${run_id}.zarr/
        echo "Zarr directory cleanup completed in \$((\$SECONDS - \$STEP_START))s"
    else
        echo "Skipped zipping (avsd_zip_spatialdata=false), output is ${run_id}.zarr/"
    fi

    STEP_START=\$SECONDS
    rm -rf ${run_id}/
    echo "Run directory cleanup completed in \$((\$SECONDS - \$STEP_START))s"
    echo "Total task wall time: \$((\$SECONDS - \$TASK_START))s"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        build-spatialdata: \$(uv run build-spatialdata --version 2>&1 | head -n1 || echo "unknown")
    END_VERSIONS
    """

    stub:
    """
    # Stub outputs match avsd_zip_spatialdata param
    if [ "${params.avsd_zip_spatialdata}" = "true" ]; then
        touch ${run_id}.zarr.zip
    else
        mkdir -p ${run_id}.zarr
    fi
    touch build_spatialdata.log
    touch build_summary.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        build-spatialdata: stub
    END_VERSIONS
    """
}

