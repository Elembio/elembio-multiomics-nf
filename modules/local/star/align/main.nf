process STAR_ALIGN {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/26/268b4c9c6cbf8fa6606c9b7fd4fafce18bf2c931d1a809a0ce51b105ec06c89d/data' :
        'community.wave.seqera.io/library/htslib_samtools_star_gawk:ae438e9a604351a4' }"

    input:
    tuple val(meta), path(reads, stageAs: "input*/*")
    tuple val(meta2), path(index)
    tuple val(meta3), path(gtf)
    val star_ignore_sjdbgtf
    
    output:
    tuple val(meta), path('*Log.final.out'), emit: log_final
    tuple val(meta), path('*Log.out'), emit: log_out
    tuple val(meta), path('*Log.progress.out'), emit: log_progress
    tuple val(meta), path("*.log"), emit: log
    path  "versions.yml", emit: versions
    tuple val(meta), path('*.star.bam'), path('*.star.bam.bai'), emit: bam_bai
    tuple val(meta), path('*.star.chimeric.bam'), path('*.star.chimeric.bam.bai'), emit: chimeric_bam_bai
    tuple val(meta), path('*.toTranscriptome.bam'), optional:true, emit: transcriptome_bam
    tuple val(meta), path('*.tab'), optional:true, emit: tab
    tuple val(meta), path('*.SJ.out.tab'), optional:true, emit: spl_junc_tab
    tuple val(meta), path('*.ReadsPerGene.out.tab'), optional:true, emit: read_per_gene_tab
    tuple val(meta), path('*.out.junction'), optional:true, emit: junction
    tuple val(meta), path('*.out.sam'), optional:true, emit: sam
    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    def reads1 = []
    def reads2 = []
    
    meta.single_end ? [reads].flatten().each{reads1 << it} : reads.eachWithIndex{ v, ix -> ( ix & 1 ? reads2 : reads1) << v }

    def ignore_gtf = star_ignore_sjdbgtf ? '' : "--sjdbGTFfile $gtf"
    def read_group = meta.read_group ? "${meta.read_group}__${meta.sample}" : "RG"
    def platform = meta.platform ? "${meta.platform}" : "PL"
    def center = meta.center ? "${meta.center}" : "CN"
    def sample = meta.sample ? "${meta.sample}" : "SM"

    def is_compressed = reads1.every { it.toString().toLowerCase().endsWith(".gz") } && (reads2?.every { it.toString().toLowerCase().endsWith(".gz") } ?: true)
    def read_cmd = is_compressed ? "--readFilesCommand zcat -dc" : ""
    def star_twopass_opt = params.star_twopassmode ? "--twopassMode ${params.star_twopassmode}" : ""

    // Named star_mode profiles supply stringency (RNA2counts star_default POR).
    def mode = (params.star_mode ?: 'star_default').toString()
    def profiles = params.star_profiles
    if (!(profiles instanceof Map) || !profiles.containsKey(mode)) {
        def known = (profiles instanceof Map) ? profiles.keySet().sort().join(', ') : 'star_default'
        throw new IllegalArgumentException("Unknown star_mode '${mode}'. Expected: ${known}")
    }
    def p = profiles[mode]
    def out_filter_multimap_nmax = params.star_outFilterMultimapNmax != null ? params.star_outFilterMultimapNmax : p.outFilterMultimapNmax
    def out_sam_mult_nmax = params.star_outSAMmultNmax != null ? params.star_outSAMmultNmax : p.outSAMmultNmax
    def out_filter_match_nmin = params.star_outFilterMatchNmin != null ? params.star_outFilterMatchNmin : p.outFilterMatchNmin
    def out_filter_score_min_over_lread = params.star_outFilterScoreMinOverLread != null ? params.star_outFilterScoreMinOverLread : p.outFilterScoreMinOverLread
    def out_filter_match_nmin_over_lread = params.star_outFilterMatchNminOverLread != null ? params.star_outFilterMatchNminOverLread : p.outFilterMatchNminOverLread
    def align_sj_overhang_min = params.star_alignSJoverhangMin != null ? params.star_alignSJoverhangMin : p.alignSJoverhangMin
    def chim_segment_min = params.star_chimSegmentMin != null ? params.star_chimSegmentMin : p.chimSegmentMin

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    STAR \\
        --genomeDir $index \\
        --readFilesIn ${reads1.join(",")} ${reads2.join(",")} \\
        --runThreadN $task.cpus \\
        ${star_twopass_opt} \\
        --alignEndsType ${params.star_align_ends_type} \\
        --outFileNamePrefix ${prefix}. \\
        --quantMode GeneCounts \\
        --outSAMtype BAM SortedByCoordinate \\
        --outSAMunmapped Within \\
        --outFilterMultimapNmax ${out_filter_multimap_nmax} \\
        --outSAMmultNmax ${out_sam_mult_nmax} \\
        --outFilterMatchNmin ${out_filter_match_nmin} \\
        --outFilterScoreMinOverLread ${out_filter_score_min_over_lread} \\
        --outFilterMatchNminOverLread ${out_filter_match_nmin_over_lread} \\
        --alignSJoverhangMin ${align_sj_overhang_min} \\
        --chimOutType SeparateSAMold \\
        --chimSegmentMin ${chim_segment_min} \\
        --outSAMmapqUnique 60 \\
        --outSAMattributes NH HI AS nM MD NM jM jI RG \\
        --outSAMattrRGline 'ID:$read_group' 'CN:$center' 'SM:$sample' 'PL:$platform' \\
        $ignore_gtf \\
        $read_cmd \\
        $args
        
    if [ -n "${params.star_twopassmode}" ]; then
        chmod -R a+rx ${prefix}._STARpass1 ${prefix}._STARgenome 2>/dev/null || true
        rm -rf ${prefix}._STARpass1 ${prefix}._STARgenome 2>/dev/null || true
    fi
    
    # standardize outputs
    mv ${prefix}.Aligned.sortedByCoord.out.bam ${prefix}.star.bam
    samtools index -@$task.cpus ${prefix}.star.bam

    if [ -f ${prefix}.Unmapped.out.mate1 ]; then
        mv ${prefix}.Unmapped.out.mate1 ${prefix}.unmapped_1.fastq
        gzip ${prefix}.unmapped_1.fastq
    fi
    if [ -f ${prefix}.Unmapped.out.mate2 ]; then
        mv ${prefix}.Unmapped.out.mate2 ${prefix}.unmapped_2.fastq
        gzip ${prefix}.unmapped_2.fastq
    fi

    samtools view -bS ${prefix}.Chimeric.out.sam | samtools sort --threads $task.cpus -m 1G -O BAM -o ${prefix}.star.chimeric.bam
    samtools index -@$task.cpus ${prefix}.star.chimeric.bam
    rm ${prefix}.Chimeric.out.sam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        star: \$(STAR --version 2>&1 | head -n1 | sed -nE 's/^STAR_([0-9][^[:space:]]*).*/\\1/p')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip > ${prefix}.unmapped_1.fastq.gz
    echo "" | gzip > ${prefix}.unmapped_2.fastq.gz
    touch run.log
    touch ${prefix}Xd.out.bam
    touch ${prefix}.Log.final.out
    touch ${prefix}.Log.out
    touch ${prefix}.Log.progress.out
    touch ${prefix}.sortedByCoord.out.bam
    touch ${prefix}.toTranscriptome.out.bam
    touch ${prefix}.Aligned.unsort.out.bam
    touch ${prefix}.Aligned.sortedByCoord.out.bam
    touch ${prefix}.star.bam
    touch ${prefix}.star.bam.bai
    touch ${prefix}.star.chimeric.bam
    touch ${prefix}.star.chimeric.bam.bai
    touch ${prefix}.tab
    touch ${prefix}.SJ.out.tab
    touch ${prefix}.ReadsPerGene.out.tab
    touch ${prefix}.Chimeric.out.junction
    touch ${prefix}.out.sam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        star: \$(STAR --version 2>&1 | head -n1 | sed -nE 's/^STAR_([0-9][^[:space:]]*).*/\\1/p')
    END_VERSIONS
    """
}
