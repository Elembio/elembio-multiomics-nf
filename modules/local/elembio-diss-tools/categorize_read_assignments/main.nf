process CATEGORIZE_READ_ASSIGNMENTS {
    tag "$meta.id"
    label 'process_high'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(raw_polony_parquet, stageAs: "input/*")
    val count_simple_multimapping_reads
    path intervals_metadata
    path hgnc_gene_groups

    output:
    tuple val(meta), path("*_reads.parquet")                         , emit: polony_parquet
    tuple val(meta), path("*.resolver_metrics.tsv"), optional: true  , emit: resolver_metrics
    tuple val(meta), path("*.log")                                      , emit: log
    path  "versions.yml"                                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def count_simple_multimapping_reads_option = params.f2p_3p_count_simple_multimapping_reads ? "--count-simple-multimapping-reads" : ""
    def unique_only_categories_option = params.f2p_3p_unique_only_tiers ? "--unique-only-categories ${params.f2p_3p_unique_only_tiers}" : ""
    def intervals_metadata_option = "--intervals-metadata ${intervals_metadata}"
    // featureCounts+rank engine (1.2.5): the duckdb point resolver was removed, so the
    // --use-polya-point-resolver flag is retired. strandedness is always passed (drives the
    // umbrella heavy/light split + matches featureCounts -s 2); family rescue + the
    // all-records metrics TSV still apply to the rank collapse.
    def rescue_gene_family_option = params.f2p_3p_rescue_gene_family ? "--rescue-gene-family" : ""
    def hgnc_gene_groups_option = hgnc_gene_groups.name != 'NO_FILE' ? "--hgnc-gene-groups ${hgnc_gene_groups}" : ""
    def strandedness_option = "--strandedness ${params.f2p_3p_strandedness}"
    def resolver_metrics_option = params.f2p_3p_resolver_metrics ? "--resolver-metrics ${meta.well}_${meta.batch}.resolver_metrics.tsv" : ""

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "elembio_diss_rna2counts categorize-read-assignments --bam-record-parquet ${raw_polony_parquet} --batch ${meta.batch} --well ${meta.well} ${count_simple_multimapping_reads_option} ${unique_only_categories_option} ${intervals_metadata_option} ${rescue_gene_family_option} ${hgnc_gene_groups_option} ${strandedness_option} ${resolver_metrics_option} --threads $task.cpus --memory-gb ${task.memory.toGiga()} ${args} --debug"

    elembio_diss_rna2counts categorize-read-assignments \\
        --bam-record-parquet ${raw_polony_parquet} \\
        --output-dir . \\
        --batch ${meta.batch} \\
        --well ${meta.well} \\
        ${count_simple_multimapping_reads_option} \\
        ${unique_only_categories_option} \\
        ${intervals_metadata_option} \\
        ${rescue_gene_family_option} \\
        ${hgnc_gene_groups_option} \\
        ${strandedness_option} \\
        ${resolver_metrics_option} \\
        --threads $task.cpus \\
        --memory-gb ${task.memory.toGiga()} \\
        ${args} \\
        --debug
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reads.parquet
    touch run.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """
}

