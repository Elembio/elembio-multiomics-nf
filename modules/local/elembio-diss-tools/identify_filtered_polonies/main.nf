process IDENTIFY_FILTERED_POLONIES {
    tag "$meta.id"
    label 'process_high'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(polony_parquet, stageAs: "input/*")
    tuple val(meta2), path(rawreads_files, stageAs: "rawreads/*")

    output:
    tuple val(meta), path("*_filteredreads.parquet")                   , emit: filtered_parquet
    tuple val(meta), path("*_filteredreads_summary.json")             , emit: filtered_summary
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

    echo "elembio_diss_rna2counts identify-filtered-polonies --bam-record-parquet ${polony_parquet} --rawreads-parquet ${rawreads_files} --batch ${meta.batch} --well ${meta.well} --threads $task.cpus --memory-gb ${task.memory.toGiga()} --debug"

    elembio_diss_rna2counts identify-filtered-polonies \\
        --bam-record-parquet ${polony_parquet} \\
        --rawreads-parquet ${rawreads_files} \\
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
    touch ${prefix}_filteredreads.parquet
    echo '{"TotalInstrumentReads":0,"TotalPipelineReads":0,"TotalFilteredPolonies":0,"PctFilteredOfInstrument":0,"TotalTiles":0}' > ${prefix}_filteredreads_summary.json
    touch run.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """
}
