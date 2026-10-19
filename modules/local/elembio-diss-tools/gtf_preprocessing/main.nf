process GTF_PREPROCESSING {
    tag "GTF_PREPROCESSING"
    label 'process_low'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    path(gtf, stageAs: "input/*")

    output:
    tuple path("*.gtf.gz"), path("*.gtf.gz.tbi")    , emit: gtf_compressed
    path("*.log")                                   , emit: log
    path  "versions.yml"                            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    
    """
    logfile=gtf_preprocessing.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Processing GTF file: ${gtf}"

    # Compress and index GTF for IGV / tabix consumers
    bgzip input/*.gtf
    tabix -p gff input/*.gtf.gz
    cp input/*.gtf.* .

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bgzip: \$(echo \$(bgzip --version 2>&1) | head -n1 | sed 's/^.*bgzip //; s/ .*\$//')
        tabix: \$(echo \$(tabix --version 2>&1) | head -n1 | sed 's/^.*tabix //; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    """
    touch gtf_preprocessing.log
    touch ${gtf.baseName}.gtf.gz
    touch ${gtf.baseName}.gtf.gz.tbi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bgzip: stub
        tabix: stub
    END_VERSIONS
    """
}

