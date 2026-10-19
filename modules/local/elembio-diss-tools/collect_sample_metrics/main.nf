process COLLECT_SAMPLE_METRICS {
    tag "$meta.id"
    label 'process_single'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(star_log), path(samtools_stats), path(basic_metrics), path(cell_counts_summary), path(rna_metrics), path(filtered_summary)

    output:
    tuple val(meta), path("*.f2p_metrics.json"), emit: metrics_json
    path  "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def filtered_summary_arg = filtered_summary.name != 'NO_FILE' ? "--filtered-summary ${filtered_summary}" : ''

    """
    elembio_diss_rna2counts collect-sample-metrics \\
        --star-log ${star_log} \\
        --samtools-stats ${samtools_stats} \\
        --basic-metrics ${basic_metrics} \\
        --cell-counts-summary ${cell_counts_summary} \\
        --rna-metrics ${rna_metrics} \\
        ${filtered_summary_arg} \\
        --sample-id ${meta.id} \\
        --well ${meta.well} \\
        --batch ${meta.batch} \\
        --batch-type ${meta.assay_type} \\
        --output ${meta.id}.f2p_metrics.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    """
    echo '{"SampleID":"${meta.id}","WellLocation":"${meta.well}","BatchName":"${meta.batch}","AssayType":"${meta.assay_type}"}' > ${meta.id}.f2p_metrics.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: stub
    END_VERSIONS
    """
}
