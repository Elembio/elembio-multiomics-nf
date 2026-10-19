process BAM_TO_PARQUET {
    tag "$meta.id"
    label 'process_high'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(bam, stageAs: "input/*")
    path run_parameters_json
    
    output:
    tuple val(meta), path("*.raw_reads.parquet")                     , emit: raw_polony_parquet
    tuple val(meta), path("*.log")                                      , emit: log
    path  "versions.yml"                                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "elembio_diss_rna2counts bam-to-parquet --alignment-file ${bam} --batch ${meta.batch} --well ${meta.well} --run-parameters ${run_parameters_json} --threads $task.cpus --batch-size ${params.f2p_batch_size} --debug"
    
    elembio_diss_rna2counts bam-to-parquet \\
        --alignment-file ${bam} \\
        --output-dir . \\
        --batch ${meta.batch} \\
        --well ${meta.well} \\
        --run-parameters ${run_parameters_json} \\
        --threads $task.cpus \\
        --batch-size ${params.f2p_batch_size} \\
        --debug
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch run.log
    touch ${prefix}.raw_reads.parquet

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: stub
    END_VERSIONS
    """
}
