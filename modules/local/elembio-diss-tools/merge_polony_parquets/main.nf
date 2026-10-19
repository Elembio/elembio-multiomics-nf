process MERGE_POLONY_PARQUETS {
    tag "$meta.id"
    label 'process_high'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(polony_parquet, stageAs: "input_reads/*")
    tuple val(meta2), path(filtered_parquet, stageAs: "input_filtered/*")

    output:
    tuple val(meta), path("*_reads.parquet")                          , emit: merged_parquet
    tuple val(meta), path("*.log")                                    , emit: log
    path  "versions.yml"                                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "elembio_diss_rna2counts merge-polony-parquets --reads-parquet ${polony_parquet} --filtered-parquet ${filtered_parquet} --batch ${meta.batch} --well ${meta.well} --threads $task.cpus --memory-gb ${task.memory.toGiga()} --debug"

    elembio_diss_rna2counts merge-polony-parquets \\
        --reads-parquet ${polony_parquet} \\
        --filtered-parquet ${filtered_parquet} \\
        --output-dir . \\
        --batch ${meta.batch} \\
        --well ${meta.well} \\
        --threads $task.cpus \\
        --memory-gb ${task.memory.toGiga()} \\
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
