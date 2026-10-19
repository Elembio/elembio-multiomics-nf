process AGGREGATE_F2P_METRICS {
    tag "aggregate_f2p_metrics"
    label 'process_single'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    val run_id
    path sample_metrics
    path run_parameters_json
    path provenance_json

    output:
    path "RunStats.json", emit: run_stats_json
    path "versions.yml" , emit: versions
    // Curated small-metadata mirror for downstream tools (build-spatialdata
    // --f2p-3p-dir). Contains only the run-level RunStats.json — per-sample
    // metrics and bulk parquets are excluded on purpose.
    path "metrics"      , emit: metrics_dir

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # --provenance embeds Provenance.json's .Tools + the full resolved .Params into
    # RunStats.json (the diss-tools aggregate-metrics CLI owns this as of 0.16.1) so
    # downstream / the QC report read the resolved workflow params (PF enforce/K/Q/
    # softclip, count policy, features, biotypes, slop, ...) without re-opening
    # pipeline_info.  (Replaces the prior inline-python Tools/Params merge.)
    elembio_diss_rna2counts aggregate-metrics \\
        --run-id ${run_id} \\
        --run-parameters ${run_parameters_json} \\
        --provenance ${provenance_json} \\
        --output RunStats.json \\
        ${sample_metrics}

    # Curated small-metadata mirror. Strict allowlist — keep bulk per-sample
    # metrics out of the downstream --f2p-3p-dir surface.
    mkdir -p metrics
    for f in RunStats.json; do
        [ -e "\$f" ] && ln -sf "../\$f" "metrics/\$f"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    """
    echo '{"AnalysisID":"f2p.stub","AnalysisVersion":"stub","FileVersion":"1.0.0","RunID":"${run_id}","RunName":"","FlowCellID":"","RunSummary":{},"Samples":[],"Tools":{},"Params":{}}' > RunStats.json

    mkdir -p metrics
    for f in RunStats.json; do
        [ -e "\$f" ] && ln -sf "../\$f" "metrics/\$f"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: stub
    END_VERSIONS
    """
}
