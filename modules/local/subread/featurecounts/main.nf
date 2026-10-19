process FEATURECOUNTS_BAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/subread:2.0.6--he4a0461_2'
        : 'biocontainers/subread:2.0.6--he4a0461_2'}"

    input:
    tuple val(meta), path(bam)
    tuple val(meta2), path(annotation)

    output:
    tuple val(meta), path("*.featureCounts.bam")        , emit: bam
    tuple val(meta), path("*.featureCounts.txt.gz")     , emit: counts
    tuple val(meta), path("*.featureCounts.txt.summary"), emit: summary
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    
    """
    featureCounts \\
        ${args} \\
        -T ${task.cpus} \\
        -a ${annotation} \\
        -o ${prefix}.featureCounts.txt \\
        -R BAM \\
        ${bam}

    # Rename annotated BAM to standard name
    mv ${bam}.featureCounts.bam ${prefix}.featureCounts.bam

    # Compress counts file
    gzip ${prefix}.featureCounts.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        subread: \$( echo \$(featureCounts -v 2>&1) | sed -e "s/featureCounts v//g")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.featureCounts.bam
    echo "" | gzip > ${prefix}.featureCounts.txt.gz
    touch ${prefix}.featureCounts.txt.summary

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        subread: \$( echo \$(featureCounts -v 2>&1) | sed -e "s/featureCounts v//g")
    END_VERSIONS
    """
}

