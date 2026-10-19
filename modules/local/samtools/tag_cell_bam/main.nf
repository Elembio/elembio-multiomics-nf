process TAG_CELL_BAM {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.22.1--h96c455f_0' :
        'biocontainers/samtools:1.22.1--h96c455f_0' }"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("*.unsorted.tagged.bam"), emit: bam
    tuple val(meta), path("*.log"), emit: log
    path  "versions.yml"                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    // Extract cell barcode (CB) and batch (XB) from read name.
    // Cyto FASTQ always appends a 7-digit polony-map index after batch; that is
    // consumed from the read name via HeaderData.polony_index, not as a BAM tag.
    // Example: …:00000000:0:B03[:PPPPPPP]
    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    samtools view -h $bam | \\
    awk 'BEGIN {OFS="\\t"} 
        /^@/ {print; next} 
        {
            split(\$1, a, ":"); 
            cell_id=a[8]; 
            batch_id=a[10];
            print \$0, "CB:Z:" cell_id, "XB:Z:" batch_id;
        }' | \\
    samtools view -b -o ${prefix}.unsorted.tagged.bam
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version 2>&1 | head -n1 | sed -nE 's/^samtools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.unsorted.tagged.bam
    touch ${prefix}.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: stub
    END_VERSIONS
    """
}

