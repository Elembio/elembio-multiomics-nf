process PROCESS_READ_ASSIGNMENTS {
    tag "$meta.id"
    label 'process_high'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(polony_parquet, stageAs: "input/*")
    path run_parameters_json
    path cellstats_parquet
    tuple val(meta1), path(gtf, stageAs: "gtf/*")
    path intervals_metadata
    
    
    output:
    tuple val(meta), path("*.polony-qc_reads.parquet", optional: true)   , emit: qc_polonies_parquet
    tuple val(meta), path("*.cell-qc_reads.parquet", optional: true)    , emit: qc_cell_polonies_parquet
    tuple val(meta), path("*.gene-names.csv.gz")                        , emit: gene_names_csv
    tuple val(meta), path("*.selected-genes.csv.gz")                    , emit: selected_genes_csv
    tuple val(meta), path("*.basic-metrics.csv.gz")                     , emit: basic_metrics_csv_gz
    tuple val(meta), path("*.biotype-metrics.tsv", optional: true)      , emit: biotype_metrics
    tuple val(meta), path("*.tier-metrics.tsv", optional: true)         , emit: tier_metrics
    tuple val(meta), path("*.cell_read_counts_summary.parquet")         , emit: cell_read_counts_summary_parquet
    tuple val(meta), path("*.log")                                      , emit: log
    path  "versions.yml"                                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "elembio_diss_rna2counts process-read-assignments --bam-record-parquet ${polony_parquet} --run-parameters ${run_parameters_json} --well ${meta.well} --batch ${meta.batch} --gtf-file ${gtf} --intervals-metadata ${intervals_metadata} --output-dir . --cellstats-parquet ${cellstats_parquet} --sample-size ${params.f2p_qc_sample_size} --num-cells ${params.f2p_qc_cell_sample_size} --threads $task.cpus --memory ${task.memory.toGiga()} ${args} --debug"

    elembio_diss_rna2counts process-read-assignments \\
        --bam-record-parquet ${polony_parquet} \\
        --run-parameters ${run_parameters_json} \\
        --well ${meta.well} \\
        --batch ${meta.batch} \\
        --gtf-file ${gtf} \\
        --intervals-metadata ${intervals_metadata} \\
        --output-dir . \\
        --cellstats-parquet ${cellstats_parquet} \\
        --sample-size ${params.f2p_qc_sample_size} \\
        --num-cells ${params.f2p_qc_cell_sample_size} \\
        --threads $task.cpus \\
        --memory ${task.memory.toGiga()} \\
        ${args} \\
        --debug

    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "elembio_diss_rna2counts process-read-assignments --bam-record-parquet ${polony_parquet} --run-parameters ${run_parameters_json} --well ${meta.well} --batch ${meta.batch} --gtf-file ${gtf} --intervals-metadata ${intervals_metadata} --output-dir . --cellstats-parquet ${cellstats_parquet} --sample-size ${params.f2p_qc_sample_size} --num-cells ${params.f2p_qc_cell_sample_size} --threads $task.cpus --memory ${task.memory.toGiga()} ${args} --debug" > run.log
    touch ${prefix}.polony-qc_reads.parquet
    touch ${prefix}.cell-qc_reads.parquet
    touch ${prefix}.gene-names.csv.gz
    touch ${prefix}.selected-genes.csv.gz
    touch ${prefix}.basic-metrics.csv.gz
    touch ${prefix}.biotype-metrics.tsv
    touch ${prefix}.tier-metrics.tsv
    touch ${prefix}.cell_read_counts_summary.parquet

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: stub
    END_VERSIONS
    """
}
