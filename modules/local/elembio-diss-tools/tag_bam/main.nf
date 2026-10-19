process TAG_BAM {
    tag "$meta.id"
    label 'process_medium'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(bam, stageAs: "input/*"), path(polony_parquet, stageAs: "input/*")

    output:
    tuple val(meta), path("*.tagged.polony.bam"), path("*.tagged.polony.bam.bai"), emit: tagged_bam
    tuple val(meta), path("*.log")                                               , emit: log
    path  "versions.yml"                                                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}.star.tagged.polony"
    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "elembio_diss_rna2counts tag-bam --alignment-file ${bam} --polony-parquet ${polony_parquet} --output-bam ${prefix}.bam --threads $task.cpus --memory-gb ${task.memory.toGiga()} ${args}"

    elembio_diss_rna2counts tag-bam \\
        --alignment-file ${bam} \\
        --polony-parquet ${polony_parquet} \\
        --output-bam ${prefix}.bam \\
        --threads $task.cpus \\
        --memory-gb ${task.memory.toGiga()} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}.star.tagged.polony"
    """
    touch run.log
    touch ${prefix}.bam
    touch ${prefix}.bam.bai

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: stub
    END_VERSIONS
    """
}
