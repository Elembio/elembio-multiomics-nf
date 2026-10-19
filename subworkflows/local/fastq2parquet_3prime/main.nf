//
// FASTQ2PARQUET_3PRIME: Align 3' untargeted FASTQ reads, assign to features, and generate polony parquets
//

include { GTF_PREPROCESSING } from '../../../modules/local/elembio-diss-tools/gtf_preprocessing/main.nf'
include { GENERATE_FEATURE_SAF } from '../../../modules/local/elembio-diss-tools/generate_feature_saf/main.nf'

include { STAR_ALIGN } from '../../../modules/local/star/align/main'
include { TAG_CELL_BAM } from '../../../modules/local/samtools/tag_cell_bam/main'
include { FEATURECOUNTS_BAM } from '../../../modules/local/subread/featurecounts/main'
include { SAMTOOLS_SORT as SAMTOOLS_SORT_CELL } from '../../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_SORT as SAMTOOLS_SORT_POS } from '../../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_STATS } from '../../../modules/nf-core/samtools/stats/main'
include { SAMTOOLS_IDXSTATS } from '../../../modules/nf-core/samtools/idxstats/main'
include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'
include { UCSC_GTFTOGENEPRED } from '../../../modules/nf-core/ucsc/gtftogenepred/main'
include { PICARD_COLLECTRNASEQMETRICS } from '../../../modules/local/picard/collect_rna_seq_metrics'

include { BAM_TO_PARQUET } from '../../../modules/local/elembio-diss-tools/bam_to_parquet/main.nf'
include { CATEGORIZE_READ_ASSIGNMENTS } from '../../../modules/local/elembio-diss-tools/categorize_read_assignments/main.nf'
include { APPLY_READ_FILTER } from '../../../modules/local/elembio-diss-tools/apply_read_filter/main.nf'
include { TAG_BAM } from '../../../modules/local/elembio-diss-tools/tag_bam/main.nf'
include { IDENTIFY_FILTERED_POLONIES } from '../../../modules/local/elembio-diss-tools/identify_filtered_polonies/main.nf'
include { MERGE_POLONY_PARQUETS } from '../../../modules/local/elembio-diss-tools/merge_polony_parquets/main.nf'
include { SPLIT_POLONY_PARQUETS } from '../../../modules/local/elembio-diss-tools/split_polony_parquets/main.nf'
include { PROCESS_READ_ASSIGNMENTS } from '../../../modules/local/elembio-diss-tools/process_read_assignments/main.nf'
include { COLLECT_SAMPLE_METRICS } from '../../../modules/local/elembio-diss-tools/collect_sample_metrics/main.nf'
include { AGGREGATE_F2P_METRICS } from '../../../modules/local/aggregate_f2p_metrics/main.nf'
include { F2P_METRICS_DIR } from '../../../modules/local/f2p_metrics_dir/main.nf'

workflow FASTQ2PARQUET_3PRIME {

    take:
    ch_fastq                // channel: [ [meta], [fastq_files] ] - parsed FASTQ channel from BASES2FASTQ
    ch_star_index           // channel: STAR index path
    ch_genes_gtf            // channel: GTF annotation file
    ch_genes_bed12          // channel: BED12 annotation file
    ch_genome               // tuple: [fasta, fasta_fai, genome_file, chrom_sizes, genome_dict]
    run_parameters_json     // file: run parameters JSON
    ch_cellstats_parquet    // channel: [ [meta], parquet ] from CELLS2STATS
    ch_c2s_rawreads_files   // channel: [ [meta], [files] ] per-tile rawreads parquets from CELLS2STATS (glob-emit)
    run_id                  // val: run identifier
    ch_provenance_json      // channel: pipeline_info/Provenance.json — .Tools + .Params embedded into RunStats.json

    main:

    ch_versions = Channel.empty()

    // One-time GTF bgzip+tabix indexing (outputs consumed by IGV/tabix; BUILD_SPATIALDATA reads the raw GTF directly)
    GTF_PREPROCESSING (
        ch_genes_gtf
    )

    // Build the SAF + sidecar metadata used by featureCounts (-F SAF) and
    // the post-hoc feature_category lookup in CATEGORIZE_READ_ASSIGNMENTS.
    // On-target KPIs are SAF-derived (Unique+MultiSimple / Mapped); Picard
    // CollectHsMetrics + its GTF BED generators are retired.
    GENERATE_FEATURE_SAF (
        ch_genes_gtf,
        ch_genome,
    )
    ch_feature_saf = GENERATE_FEATURE_SAF.out.saf
    ch_intervals_metadata = GENERATE_FEATURE_SAF.out.intervals_metadata
    ch_gene_metadata = GENERATE_FEATURE_SAF.out.gene_metadata   // run-level; rides F2P_METRICS_DIR → BUILD_SPATIALDATA
    ch_versions = ch_versions.mix(GENERATE_FEATURE_SAF.out.versions)

    // HGNC gene-groups map for the resolver's Layer-2 family rescue (default OFF).
    // Optional: tracked assets/NO_FILE sentinel when unset (stages cleanly on cloud
    // backends). .first() → value channel so the single file broadcasts to every well.
    ch_hgnc_gene_groups = ( params.f2p_3p_hgnc_gene_groups
        ? Channel.fromPath(params.f2p_3p_hgnc_gene_groups, checkIfExists: true)
        : Channel.fromPath("${projectDir}/assets/NO_FILE", checkIfExists: true) ).first()

    // STAR
    STAR_ALIGN (
        ch_fastq,
        ch_star_index.map { [ [:], it ] },
        ch_genes_gtf.map { [ [:], it ] },
        params.star_ignore_sjdbgtf
    )
    ch_bam_bai = STAR_ALIGN.out.bam_bai

    // Tag BAM with cell barcode (CB) and batch (XB) from read name
    TAG_CELL_BAM (
        ch_bam_bai
    )

    // Assign reads to genes using featureCounts (outputs annotated BAM).
    // Annotation is the SAF built by GENERATE_FEATURE_SAF — slop is baked
    // into the SAF intervals, so featureCounts no longer applies
    // --readExtension5/3 (see conf/modules.config).
    FEATURECOUNTS_BAM (
        TAG_CELL_BAM.out.bam,
        ch_feature_saf.map { [ [:], it ] }
    )

    // Sort BAM by cell barcode tag (CB) - produces cell-sorted BAM
    SAMTOOLS_SORT_CELL (
        FEATURECOUNTS_BAM.out.bam,
        [[:], []],  // no reference needed
        []          // no index_format
    )
    ch_tagged_cell_sorted_bam = SAMTOOLS_SORT_CELL.out.bam

    // Sort BAM by position - produces position-sorted BAM  
    SAMTOOLS_SORT_POS (
        FEATURECOUNTS_BAM.out.bam,
        [[:], []],  // no reference needed
        "bai"       // generate .bai index
    )
    
    // Combine position-sorted BAM with its index
    ch_tagged_pos_sorted_bam_bai = SAMTOOLS_SORT_POS.out.bam
        .join(SAMTOOLS_SORT_POS.out.bai)

    // Samtools stats for BAM QC metrics
    SAMTOOLS_STATS (
        ch_tagged_pos_sorted_bam_bai,
        [[:], []]  // no reference needed
    )

    // Samtools idxstats for per-chromosome mapped/unmapped read counts (reads the .bai index)
    SAMTOOLS_IDXSTATS (
        ch_tagged_pos_sorted_bam_bai
    )

    // Samtools flagstat for summary alignment counts (mapped, duplicates, primary/secondary/supplementary)
    SAMTOOLS_FLAGSTAT (
        ch_tagged_pos_sorted_bam_bai
    )

    // ch_genome is a 5-element list [fasta, fai, genome_file, chrom_sizes, genome_dict]
    def fasta = ch_genome[0]

    // Generate refFlat from GTF once (needed by Picard CollectRnaSeqMetrics)
    UCSC_GTFTOGENEPRED (
        ch_genes_gtf.map { [ [id: 'genes'], it ] }
    )
    ch_refflat = UCSC_GTFTOGENEPRED.out.refflat.map { _meta, refflat -> refflat }

    // Picard CollectRnaSeqMetrics for 3' bias and transcript-region composition
    // (PCT_CODING/UTR/INTRONIC/INTERGENIC/RIBOSOMAL, MEDIAN_3PRIME_BIAS, etc.)
    PICARD_COLLECTRNASEQMETRICS (
        ch_tagged_pos_sorted_bam_bai.map { meta, bam, _bai -> [meta, bam] },
        ch_refflat,
        fasta,
        []  // rrna_intervals — optional; can be added later if derived from GTF
    )
    ch_versions = ch_versions.mix(PICARD_COLLECTRNASEQMETRICS.out.versions.first())

    // Extract the parquet file from the channel (run-level file, same for all samples)
    cellstats_parquet = ch_cellstats_parquet.map { meta, parquet -> parquet }

    // BAM_TO_PARQUET no longer joins RawCellStats (Cell_X/Cell_Y/AreaUm/NuclearAreaUm):
    // those columns were unused downstream, and PROCESS_READ_ASSIGNMENTS re-joins
    // cellstats independently. Dropping the cellstats input lets this (and the
    // CATEGORIZE chain) run in parallel with CELLS2STATS instead of waiting on it.
    BAM_TO_PARQUET (
        ch_tagged_cell_sorted_bam,
        run_parameters_json,
    )
    ch_raw_polony_parquet = BAM_TO_PARQUET.out.raw_polony_parquet

    // Add feature_category column via strand-aware PolyAPos lookup against
    // intervals_metadata.tsv from GENERATE_FEATURE_SAF.
    CATEGORIZE_READ_ASSIGNMENTS (
        ch_raw_polony_parquet,
        params.f2p_3p_count_simple_multimapping_reads,
        ch_intervals_metadata,
        ch_hgnc_gene_groups,
    )
    ch_categorized_parquet = CATEGORIZE_READ_ASSIGNMENTS.out.polony_parquet

    // Optional post-alignment soft-clip filter (BINARY): APPLY_READ_FILTER runs only
    // when f2p_3p_read_filter_enabled is set, and then it ALWAYS enforces — nulls the
    // final target_name for softclip-failing reads so they leave the count matrix while
    // the row persists (X/Y QC), overwriting the NULL read_filter_* placeholders
    // CATEGORIZE emitted. Disabled (default) ⇒ the step is skipped and ch_polony_parquet
    // is the CATEGORIZE output unchanged (read_filter_* stay NULL). Soft-clip only —
    // base-quality PF is applied upstream in bases2fastq. Kept as an extensible home
    // for future post-alignment rules.
    if (params.f2p_3p_read_filter_enabled) {
        APPLY_READ_FILTER ( ch_categorized_parquet )
        ch_polony_parquet = APPLY_READ_FILTER.out.polony_parquet
        ch_versions = ch_versions.mix(APPLY_READ_FILTER.out.versions.first())
    } else {
        ch_polony_parquet = ch_categorized_parquet
    }

    // Write the per-read assignment decisions back into the coordinate-sorted BAM
    // as Z* SAM tags for genome-browser (IGV) QC, consuming the final CATEGORIZE
    // decisions. Always on — the Z*-tagged BAM is the canonical output BAM (a
    // superset of the position-sorted alignment BAM: + CB + featureCounts XT).
    ch_tag_bam_input = ch_tagged_pos_sorted_bam_bai
        .map { meta, bam, bai -> [ meta, bam ] }
        .join(ch_polony_parquet)
    TAG_BAM ( ch_tag_bam_input )
    ch_versions = ch_versions.mix(TAG_BAM.out.versions.first())

    // Process read assignments and generate QC metrics
    PROCESS_READ_ASSIGNMENTS (
        ch_polony_parquet,
        run_parameters_json,
        cellstats_parquet,
        ch_genes_gtf.map { [ [:], it ] },
        ch_intervals_metadata
    )

    // Identify filtered polonies and merge into final reads
    ch_filtered_summary = Channel.empty()
    if (params.enable_identify_filtered_polonies) {
        // Per-(well,batch) rawreads tile files derived from CELLS2STATS
        // rawreads_files glob-emit. Closure inspects Path strings only — no
        // submitter-side filesystem walk, safe on AWS Batch / Fusion / S3.
        ch_rawreads_by_sample = ch_c2s_rawreads_files
            .flatMap { meta, files ->
                // A glob path() emit yields a single Path (not a list) when exactly
                // one file matches; a bare Path is iterable over its name components,
                // which would make groupBy below walk path segments instead of files.
                // Normalise to a list so single- and multi-file emits behave the same.
                [files].flatten().groupBy { f ->
                    def parts = f.toString().split('/')
                    def i = parts.findIndexOf { it == 'Wells' }
                    def well  = parts[i + 1].replaceAll(/^Well/, '')
                    def batch = parts[i + 2]
                    "${well}_${batch}"
                }.collect { id, group ->
                    def parts = group[0].toString().split('/')
                    def i = parts.findIndexOf { it == 'Wells' }
                    def well  = parts[i + 1].replaceAll(/^Well/, '')
                    def batch = parts[i + 2]
                    [[id: id, well: well, batch: batch], group.sort()]
                }
            }

        // Join by sample id to ensure correct pairing (different source channels)
        ch_ifp_inputs = ch_polony_parquet
            .map { meta, parquet -> [meta.id, meta, parquet] }
            .join(ch_rawreads_by_sample.map { meta, files -> [meta.id, files] })
            .multiMap { id, meta, parquet, rawreads ->
                polony: [meta, parquet]
                rawreads: [meta, rawreads]
            }

        IDENTIFY_FILTERED_POLONIES (
            ch_ifp_inputs.polony,
            ch_ifp_inputs.rawreads
        )
        ch_filtered_summary = IDENTIFY_FILTERED_POLONIES.out.filtered_summary

        // Pair polony + filtered_parquet by sample id (different source channels)
        ch_merge_inputs = ch_polony_parquet
            .map { meta, parquet -> [meta.id, meta, parquet] }
            .join(IDENTIFY_FILTERED_POLONIES.out.filtered_parquet
                .map { meta, parquet -> [meta.id, parquet] })
            .multiMap { id, meta, polony, filtered ->
                polony:   [meta, polony]
                filtered: [meta, filtered]
            }

        MERGE_POLONY_PARQUETS (
            ch_merge_inputs.polony,
            ch_merge_inputs.filtered
        )
        ch_combined_for_sdo = MERGE_POLONY_PARQUETS.out.merged_parquet
    } else {
        ch_combined_for_sdo = ch_polony_parquet
    }

    // Split combined well×batch parquet into onboard Wells layout for SDO.
    // PROCESS/TAG/metrics keep the combined artifact above; only the SDO-bound
    // emit becomes Wells/Well{well}/{batch}/{tile_id}_reads.parquet.
    SPLIT_POLONY_PARQUETS ( ch_combined_for_sdo )
    ch_spatialdata_wells = SPLIT_POLONY_PARQUETS.out.wells_dir
    ch_versions = ch_versions.mix(SPLIT_POLONY_PARQUETS.out.versions.first())

    //
    // Stage 1: COLLECT_SAMPLE_METRICS - per-sample metric collection (parallel)
    //
    ch_sample_metrics_inputs = STAR_ALIGN.out.log_final                    // [meta, star_log]
        .join(SAMTOOLS_STATS.out.stats)                                    // [meta, star_log, samtools_stats]
        .join(PROCESS_READ_ASSIGNMENTS.out.basic_metrics_csv_gz)           // [meta, star_log, samtools_stats, basic_metrics]
        .join(PROCESS_READ_ASSIGNMENTS.out.cell_read_counts_summary_parquet) // [meta, ..., cell_counts_summary]
        .join(PICARD_COLLECTRNASEQMETRICS.out.metrics)                       // [meta, ..., rna_metrics (strand specificity)]

    if (params.enable_identify_filtered_polonies) {
        ch_sample_metrics_inputs = ch_sample_metrics_inputs
            .join(ch_filtered_summary)                                     // [meta, ..., filtered_summary]
    } else {
        // Tracked sentinel — a constructed file('NO_FILE') is not part of any
        // process output and won't stage reliably on AWS Batch / Fusion.
        def no_file = file("$projectDir/assets/NO_FILE", checkIfExists: true)
        ch_sample_metrics_inputs = ch_sample_metrics_inputs
            .map { it + [no_file] }                                        // [meta, ..., NO_FILE placeholder]
    }

    COLLECT_SAMPLE_METRICS (
        ch_sample_metrics_inputs
    )
    ch_versions = ch_versions.mix(COLLECT_SAMPLE_METRICS.out.versions.first())

    //
    // Stage 2: AGGREGATE_F2P_METRICS - run-level aggregation (once, after all samples)
    //
    ch_all_sample_metrics = COLLECT_SAMPLE_METRICS.out.metrics_json
        .map { meta, json -> json }
        .collect()

    AGGREGATE_F2P_METRICS (
        run_id,
        ch_all_sample_metrics,
        run_parameters_json,
        ch_provenance_json,
    )

    // Pipeline-emitted 3' annotation provenance (genes/gtf/) — folded into
    // F2P_METRICS_DIR below so --f2p-3p-dir is a single opaque dir, mirroring
    // CELLS2STATS / BASES2FASTQ. ref/ (STAR reference) is deliberately not
    // archived. Picard HS BED provenance and MultiQC artefacts are retired.
    ch_genes_gtf_provenance = GTF_PREPROCESSING.out.gtf_compressed
        .flatten()
        .mix(GTF_PREPROCESSING.out.log)
        .collect()
    ch_versions = ch_versions.mix(AGGREGATE_F2P_METRICS.out.versions)

    //
    // Assemble --f2p-3p-dir: RunStats.json + genes/{gtf,gene_metadata.tsv,
    // intervals_metadata.tsv}, filtered through the same glob + size-cap
    // pattern as CELLS2STATS / BASES2FASTQ. Single opaque metrics_dir output.
    //
    F2P_METRICS_DIR (
        AGGREGATE_F2P_METRICS.out.run_stats_json,
        ch_genes_gtf_provenance,
        ch_gene_metadata,
        ch_intervals_metadata,
    )

    emit:
    versions              = ch_versions
    polony_parquet        = ch_spatialdata_wells       // Wells/Well{well}/{batch}/{tile}_reads.parquet tree for SDO
    run_stats_json        = AGGREGATE_F2P_METRICS.out.run_stats_json     // fastq2parquet RunStats.json
    metrics_dir           = F2P_METRICS_DIR.out.metrics_dir              // curated --f2p-3p-dir (RunStats + genes/{gtf,gene_metadata.tsv,intervals_metadata.tsv})
    sample_metrics_json   = COLLECT_SAMPLE_METRICS.out.metrics_json      // per-sample [meta, json]
    // Always emitted when GENERATE_FEATURE_SAF runs — even if no 3' FASTQs /
    // F2P_METRICS_DIR never fired — so BUILD can still receive the catalog.
    intervals_metadata    = ch_intervals_metadata
}
