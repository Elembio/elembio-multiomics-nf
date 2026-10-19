// Generate the run-quality HTML report from a built SpatialData archive
// (.zarr.zip).
//
// Runs AFTER an upstream BUILD_SPATIALDATA step. The CLI is `run-quality-report`
// (entry point of the run-quality report package, split out of
// elembio-spatialdata-analysis), invoked inside the image pinned by
// spatialdata_analysis_container_url/_tag.
//
// Output set (always emitted when the process runs):
//   - <run_id>.qc.html  — self-contained tabbed HTML report
//   - <run_id>.qc.tsv   — flat key/value run summary
//   - <run_id>.qc.json  — nested run/sequencing/modalities summary
//   - <run_id>.qc.log   — captured stdout/stderr
//
// stageInMode 'copy' mirrors CELLS2STATS_SPATIALDATABUILD_VIZ: the analysis
// CLI reads the zip in-process via zipfile/s3fs, so symlink staging is fine
// for the input itself, but `copy` keeps the artifact tree self-contained
// inside the work dir for reliable publish and resume.

process SPATIALDATA_QC_REPORT {
    tag         "$meta.id"
    label       'process_high'
    stageInMode 'copy'

    container "${params.spatialdata_analysis_container_url}:${params.spatialdata_analysis_container_tag}"

    input:
    tuple val(meta), path(sdo_zip)

    output:
    tuple val(meta), path("*.qc.html")  , emit: qc_html
    tuple val(meta), path("*.qc.tsv")   , emit: summary_tsv
    tuple val(meta), path("*.qc.json")  , emit: summary_json
    tuple val(meta), path("*.qc.log")   , emit: run_log
    // versions.yml is process-identity-scoped (same content regardless of meta.id),
    // so emit as a bare path per nf-core convention.
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Per nf-core convention, all user-configurable CLI flags are composed by
    // the consumer pipeline's conf/modules.config via task.ext.args.
    def args = task.ext.args ?: ''
    def stem = "${meta.id}"
    """
    logfile=${stem}.qc.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Executing run-quality-report..."
    echo "Container: ${task.container}"
    echo "SDO: ${sdo_zip}"

    run-quality-report \\
        --source ${sdo_zip} \\
        --output ${stem}.qc.html \\
        ${args}

    echo "Post-run directory listing:"
    ls -laR

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        run-quality-report: \$(run-quality-report --version 2>&1 | awk '{print \$NF}' || echo "unknown")
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}.qc.html
    touch ${meta.id}.qc.tsv
    touch ${meta.id}.qc.json
    touch ${meta.id}.qc.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        run-quality-report: stub
    END_VERSIONS
    """
}
