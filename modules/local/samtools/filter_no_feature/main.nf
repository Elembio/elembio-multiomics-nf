process FILTER_NO_FEATURE_BAM {
    tag "${meta.id}"
    label 'process_low'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.22.1--h96c455f_0' :
        'biocontainers/samtools:1.22.1--h96c455f_0' }"

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*.no_feature.bam"), emit: bam
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def frac = params.f2p_3p_full_annotation_downsample as float
    // samtools -s SEED.FRAC: integer part = seed (0 ⇒ deterministic), fraction = keep proportion.
    // Skip subsampling entirely when frac >= 1.0.
    def subsample = frac < 1.0 ? "-s ${frac}" : ""
    // Read-LEVEL no-feature subset of the cell-sorted, NAME-GROUPED, XS-tagged BAM (the SAME BAM
    // that builds the polony parquet), so the subset == polony's BOOL_AND(no-feature) population:
    //   * -s downsamples by READ NAME (all of a read's alignments kept/dropped together),
    //   * -F 0x4 drops unmapped reads,
    //   * awk buffers each read's adjacent records and emits ALL of them ONLY IF none is
    //     XS:Z:Assigned (drop any read with an assigned alignment — exactly BOOL_AND).
    // The full-annotation pass + read-level BOOL_AND then split these into intergenic vs unselected.
    """
    samtools view ${subsample} -h -F 0x4 ${bam} \\
        | awk 'BEGIN{FS=OFS="\\t"} /^@/{print;next}
               { if(\$1!=cur){ if(cur!="" && !drop) for(i=0;i<n;i++) print buf[i]; cur=\$1;n=0;drop=0 }
                 buf[n++]=\$0; for(i=12;i<=NF;i++) if(\$i=="XS:Z:Assigned"){drop=1;break} }
               END{ if(cur!="" && !drop) for(i=0;i<n;i++) print buf[i] }' \\
        | samtools view -b -o ${prefix}.no_feature.bam -

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version | head -1 | sed 's/samtools //')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.no_feature.bam
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: stub
    END_VERSIONS
    """
}
