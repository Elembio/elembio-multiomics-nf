process GENERATE_FEATURE_SAF {
    tag "gen-feature-saf"
    label 'process_low'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    path(gtf, stageAs: "input/*")
    tuple path(fasta), path(fai), path(genome_file), path(chrom_sizes), path(genome_dict)

    output:
    path("*.targets.saf")                          , emit: saf
    path("*.intervals_metadata.tsv")               , emit: intervals_metadata
    path("*.gene_metadata.tsv")                    , emit: gene_metadata
    path("*.extensions_for_igv.bed")               , emit: extensions_for_igv
    path("*.saf.bed")                              , emit: saf_bed
    path("*.saf.bed.gz")    , optional: true       , emit: saf_bed_gz
    path("*.saf.bed.gz.tbi"), optional: true       , emit: saf_bed_tbi
    path("*.log")                                  , emit: log
    path  "versions.yml"                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = "${gtf.baseName}.featureset${task.ext.suffix ?: ''}"
    // `f2p_3p_features` is the SINGLE source of truth for tier-group selection
    // (e.g. "utr,exon,chrm" or, to count introns, "utr,exon,intron,chrm"). The old
    // additive `f2p_3p_include_intron` / `f2p_3p_include_chrm_umbrella` booleans were
    // removed in 1.8.2 — they could only append, never force-off, which was
    // misleading (chrm was already in features). task.ext.features overrides the run
    // param when a process alias needs a different tier set without changing the
    // main selection.
    // --annotate-then-select: emit the full tier/biotype universe; --features /
    // --include-gene-types only mark intervals_metadata.selected (diss-tools 0.30.0
    // dual collapse). Requires a container that has that flag (not 0.29.0).
    def feats = task.ext.features ?: params.f2p_3p_features
    def include_types = task.ext.include_gene_types ?: params.f2p_3p_include_gene_types
    def exclude_gene_types_opt = params.f2p_3p_exclude_gene_types ? "--exclude-gene-types ${params.f2p_3p_exclude_gene_types}" : ""
    """
    logfile=${prefix}.bed_generation.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Generating SAF + sidecar metadata from ${gtf}"

    elembio_diss_rna2counts gen-feature-bed \\
        --gtf ${gtf} \\
        --genome-fai ${fai} \\
        --output-saf ${prefix}.targets.saf \\
        --output-intervals-metadata ${prefix}.intervals_metadata.tsv \\
        --output-gene-metadata ${prefix}.gene_metadata.tsv \\
        --output-extensions-for-igv ${prefix}.extensions_for_igv.bed \\
        --output-saf-bed ${prefix}.saf.bed \\
        --features ${feats} \\
        --slop-5p-bp ${params.f2p_3p_slop_5p_bp} \\
        --slop-3p-bp ${params.f2p_3p_slop_3p_bp} \\
        --include-gene-types ${include_types} \\
        ${exclude_gene_types_opt} \\
        --annotate-then-select \\
        --debug

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: \$(elembio_diss_rna2counts -v 2>&1 | tr -d '\\033' | sed -E 's/\\[[0-9;]*[A-Za-z]//g' | sed -nE 's/^elembio_diss_tools[[:space:]]+([0-9][^[:space:]]*).*/\\1/p' | head -n1)
    END_VERSIONS
    """

    stub:
    def prefix = "${gtf.baseName}.featureset"
    """
    touch ${prefix}.bed_generation.log
    touch ${prefix}.targets.saf
    touch ${prefix}.intervals_metadata.tsv
    touch ${prefix}.gene_metadata.tsv
    touch ${prefix}.extensions_for_igv.bed
    touch ${prefix}.saf.bed
    touch ${prefix}.saf.bed.gz
    touch ${prefix}.saf.bed.gz.tbi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        elembio_diss_tools: stub
    END_VERSIONS
    """
}
