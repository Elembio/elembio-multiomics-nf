// Generate the cells2stats Cell Painting QC HTML report from a built
// SpatialData archive (.zarr.zip) using `cells2stats generate_qc_report`
// (rc8+ sectioned CLI).
//
// This is the external-facing CP QC report. Pipelines that also ship an
// internal-only run-quality-report (elembio-spatialdata-analysis) should keep
// that as a separate process with distinct output names and publish dirs.
//
// Sibling to CELLS2STATS_SPATIALDATABUILD_VIZ: takes a pre-built SDO zip (not a
// run directory), shares the CELLS2STATS container, and writes via --output .

process CELLS2STATS_GENERATE_QC_REPORT {
    tag "$meta.id"
    label 'process_medium'

    container "${params.c2s_container_url}:${params.c2s_container_tag}"

    input:
    tuple val(meta), path(sdo_zip)

    output:
    tuple val(meta), path("qc_report.html")                , optional: true, emit: qc_report
    tuple val(meta), path("qc_report*")                    , optional: true, emit: qc_report_files
    // versions.yml is process-identity-scoped (same content regardless of meta.id),
    // so emit as a bare path per nf-core convention. Keeps softwareVersionsToYAML
    // happy without consumer-side meta-stripping.
    path "versions.yml"                                    , emit: versions
    tuple val(meta), path("run_generate_qc_report.log")    , emit: run_log

    when:
    task.ext.when == null || task.ext.when

    script:
    // Per nf-core convention, all user-configurable CLI flags are composed by
    // the consumer pipeline's conf/modules.config via task.ext.args. See
    // https://gitlab.com/elembio/analysis/elembio-nf-modules#module-configuration-via-taskextargs
    def args = task.ext.args ?: ''

    """
    logfile=run_generate_qc_report.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Executing Cells2Stats (generate_qc_report)..."
    echo "Container: ${task.container}"
    echo "SDO: ${sdo_zip}"

    cells2stats generate_qc_report \\
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
    touch qc_report.html
    touch run_generate_qc_report.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: stub
    END_VERSIONS
    """
}
