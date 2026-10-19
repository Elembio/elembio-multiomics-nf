process APPLY_READ_FILTER {
    tag "$meta.id"
    label 'process_medium'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(polony_parquet, stageAs: "input/*")

    output:
    tuple val(meta), path("*_reads.parquet")  , emit: polony_parquet
    tuple val(meta), path("*.log")            , emit: log
    path  "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "elembio_diss_rna2counts apply-read-filter --input-parquet ${polony_parquet} --batch ${meta.batch} --well ${meta.well} --softclip-max ${params.f2p_3p_read_filter_softclip_max} --threads $task.cpus --memory-gb ${task.memory.toGiga()} --debug"

    elembio_diss_rna2counts apply-read-filter \\
        --input-parquet ${polony_parquet} \\
        --output-dir . \\
        --batch ${meta.batch} \\
        --well ${meta.well} \\
        --softclip-max ${params.f2p_3p_read_filter_softclip_max} \\
        --threads $task.cpus \\
        --memory-gb ${task.memory.toGiga()} \\
        --debug

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.well}_${meta.batch}_reads.parquet
    touch run.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """
}
