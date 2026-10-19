process SPLIT_POLONY_PARQUETS {
    tag "$meta.id"
    label 'process_medium'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    tuple val(meta), path(polony_parquet, stageAs: "input_reads/*")

    output:
    // Unique basename per sample — BUILD_SPATIALDATA collects many of these and
    // Nextflow rejects duplicate staged names (wells_parts/Wells collision).
    // optional: empty wells (0 polonies) emit no Wells tree; BUILD already
    // collects with ifEmpty([]) and SD-build skips missing points files.
    tuple val(meta), path("*_Wells"), optional: true                  , emit: wells_dir
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

    echo "elembio_diss_rna2counts split-polony-parquets --reads-parquet ${polony_parquet} --batch ${meta.batch} --well ${meta.well} --threads $task.cpus --memory-gb ${task.memory.toGiga()} ${args} --debug"

    elembio_diss_rna2counts split-polony-parquets \\
        --reads-parquet ${polony_parquet} \\
        --output-dir . \\
        --batch ${meta.batch} \\
        --well ${meta.well} \\
        --threads $task.cpus \\
        --memory-gb ${task.memory.toGiga()} \\
        ${args} \\
        --debug

    # CLI writes Wells/ only when the input has tiles; rename so collected
    # inputs have distinct basenames. Empty wells intentionally emit nothing.
    if [ -d Wells ]; then
        mv Wells ${prefix}_Wells
    else
        echo "No polonies for ${prefix}; emitting no Wells tree"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    def well_label = meta.well.toString().startsWith('Well') ? meta.well : "Well${meta.well}"
    """
    echo "elembio_diss_rna2counts split-polony-parquets --reads-parquet ${polony_parquet} --batch ${meta.batch} --well ${meta.well} --threads $task.cpus --memory-gb ${task.memory.toGiga()} ${args} --debug" > run.log
    mkdir -p ${prefix}_Wells/${well_label}/${meta.batch}
    touch ${prefix}_Wells/${well_label}/${meta.batch}/L1R01C01S1_reads.parquet

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """
}
