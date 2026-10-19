//
// BUILD_SPATIALDATA_SUBWORKFLOW: Build SpatialData .zarr from polony parquets, genes GTF, and cells2stats outputs
//

include { BUILD_SPATIALDATA } from '../../../modules/local/aviti-spatial/build_spatialdata/main.nf'
include { CELLS2STATS_SPATIALDATABUILD_VIZ } from '../../../modules/elembio/cells2stats_spatialdatabuild_viz/main.nf'
include { CELLS2STATS_GENERATE_QC_REPORT } from '../../../modules/elembio/cells2stats_generate_qc_report/main.nf'
include { SPATIALDATA_QC_REPORT } from '../../../modules/local/aviti-spatial/spatialdata_qc_report/main.nf'

workflow BUILD_SPATIALDATA_SUBWORKFLOW {

    take:
    run_id                      // val: run identifier
    run_dir                     // val: run directory path (handles S3 internally)
    run_parameters_json         // val: resolved RunParameters.json (file) — used for tile-regex resolution
    ch_polony_parquets          // channel: [ [meta], Wells/ ] - per-sample Wells trees from F2P SPLIT
    ch_genes_gtf                // channel: raw GTF file (only flowed when 3' batches are present)
    ch_cellstats_parquet        // channel: [ [meta], parquet ] from CELLS2STATS
    ch_c2s_wells_dir            // channel: [ [meta], dir ] Wells/ from CELLS2STATS
    ch_c2s_cell_segmentation    // channel: [ [meta], dir ] CellSegmentation/ from CELLS2STATS
    ch_c2s_analysis_region      // channel: [ [meta], dir ] AnalysisRegion/ from CELLS2STATS (overlap runs only)
    ch_c2s_metrics_dir          // channel: [ [meta], dir ] curated small-metadata mirror from CELLS2STATS
    ch_b2f_metrics_dir          // channel: path curated small-metadata mirror from BASES2FASTQ (optional)
    ch_f2p_metrics_dir          // channel: path curated small-metadata mirror from FASTQ2PARQUET_3PRIME (optional)
    ch_intervals_metadata       // channel: intervals_metadata.tsv from GENERATE_FEATURE_SAF (optional; always when 3')
    ch_provenance_json          // channel: pipeline_info/Provenance.json (pipeline-level provenance, optional)

    main:

    ch_versions = Channel.empty()

    // Collect per-sample Wells trees from F2P SPLIT_POLONY_PARQUETS.
    // Layout under each Wells dir: Well{well}/{batch}/{tile_id}_reads.parquet
    // ifEmpty ensures BUILD_SPATIALDATA still fires on runs with no 3' batches
    ch_polony_files = ch_polony_parquets
        .map { meta, wells -> wells }
        .collect()
        .ifEmpty([])

    // Extract the parquet file from the channel (run-level file, same for all samples)
    cellstats_parquet = ch_cellstats_parquet.map { meta, parquet -> parquet }

    // Extract paths from cells2stats tuple channels (strip meta)
    // Wells/ may be emitted as an empty directory by cells2stats on imaging-only
    // runs; empty dirs don't survive scratch→S3 on AWS Batch, so the channel is
    // populated locally but empty on cloud. ifEmpty([]) lets BUILD_SPATIALDATA
    // fire in both cases; the module script mkdirs c2s_dir/Wells defensively.
    c2s_wells = ch_c2s_wells_dir.map { meta, dir -> dir }.ifEmpty([])
    c2s_cell_seg = ch_c2s_cell_segmentation.map { meta, dir -> dir }
    // AnalysisRegion is overlap-only; empty tuple on non-overlap runs, guard with ifEmpty
    c2s_analysis_region = ch_c2s_analysis_region.map { meta, dir -> dir }.ifEmpty([])
    c2s_metrics = ch_c2s_metrics_dir.map { meta, dir -> dir }

    // Resolve tile regex patterns against RunParameters.json tile list.
    // RunParameters.json is resolved at the workflow-entry scope (main.nf) — Wave 4
    // no longer relies on the CELLS2STATS output copy, so no channel .map is needed.
    // Nextflow unwraps single-element JSON arrays to a scalar; guard before .any.
    def asList = { value -> value instanceof List ? value : (value ? [value] : []) }
    def tile_patterns = asList(params.tile)
    def matched = []
    def tile_args = ''
    if (tile_patterns) {
        def text = run_parameters_json.text
        if (text?.trim()) {
            def rp = new groovy.json.JsonSlurper().parseText(text)
            def all_tiles = rp.Tiles ?: []
            matched = all_tiles.findAll { tid -> tile_patterns.any { pat -> tid ==~ pat } }
            if (matched.isEmpty()) {
                error "No tiles in RunParameters.json matched patterns ${tile_patterns} (available: ${all_tiles.take(5)}...)"
            }
            log.info "BUILD_SPATIALDATA tile filter: ${tile_patterns} → ${matched.size()} of ${all_tiles.size()} tiles"
            tile_args = matched.collect { "--tile-filter ${it}" }.join(' ')
        }
    }

    // ifEmpty ensures BUILD_SPATIALDATA still fires when no 3' GTF annotation is available
    ch_genes_gtf_safe = ch_genes_gtf.ifEmpty([])

    // Optional tool-dir inputs — stage empty when not produced upstream.
    b2f_metrics = ch_b2f_metrics_dir.ifEmpty([])
    f2p_metrics = ch_f2p_metrics_dir.ifEmpty([])
    // Catalog may arrive even when f2p_metrics_dir is empty (no 3' FASTQs).
    intervals_metadata = ch_intervals_metadata.ifEmpty([])

    // Canonical config files: previously synced inside the BUILD_SPATIALDATA
    // script via aws s3 cp; now NF-staged. Two of four live at run_dir, two at
    // run_dir_base (= run_dir minus /analysis/...). All optional — checkIfExists:false
    // + ifEmpty([]) preserves today's soft-failure behavior on missing files.
    def run_dir_base = run_dir.replaceAll('/analysis/.*$', '').replaceAll('/$', '')
    ch_run_params    = Channel.fromPath("${run_dir}/RunParameters.json",   checkIfExists: false).ifEmpty([])
    ch_panel_json    = Channel.fromPath("${run_dir_base}/Panel.json",      checkIfExists: false).ifEmpty([])
    ch_manifest_csv  = Channel.fromPath("${run_dir_base}/RunManifest.csv", checkIfExists: false).ifEmpty([])
    // RunManifest.json may live at either location; prefer run_dir, fall back to run_dir_base.
    ch_manifest_json = Channel
        .fromPath("${run_dir}/RunManifest.json", checkIfExists: false)
        .mix(Channel.fromPath("${run_dir_base}/RunManifest.json", checkIfExists: false))
        .first()
        .ifEmpty([])

    // Projection is synced in-script by BUILD_SPATIALDATA (aws s3 sync), NOT
    // NF-staged. build-spatialdata's image resolver requires the source layout
    // Projection/Well<X>/<batch>_<tile>_<target>.tif; NF flat-glob staging
    // (stageAs "run/Projection/*") dropped the Well<X>/ parent, so the builder
    // found 0 images. aws s3 sync preserves the tree. proj_tiles = resolved
    // tile IDs for the sync's --include filter (literals, not the user's regex
    // patterns); empty => sync the whole Projection tree.
    def proj_tiles = matched ? matched.join(' ') : ''

    BUILD_SPATIALDATA (
        run_id,
        run_dir,
        tile_args,
        ch_polony_files,
        ch_genes_gtf_safe,
        cellstats_parquet,
        c2s_wells,
        c2s_cell_seg,
        c2s_analysis_region,
        c2s_metrics,
        b2f_metrics,
        f2p_metrics,
        intervals_metadata,
        ch_run_params,
        ch_panel_json,
        ch_manifest_csv,
        ch_manifest_json,
        ch_provenance_json.ifEmpty([]),
        proj_tiles
    )
    ch_versions = ch_versions.mix(BUILD_SPATIALDATA.out.versions)

    // CELLS2STATS_SPATIALDATABUILD_VIZ is gated by params.enable_c2s_viz (default true).
    // When disabled, viz emits fall back to empty channels so downstream consumers
    // (none today) and the emit: block remain wired.
    def viz_cell_shapes_ch    = Channel.empty()
    def viz_nuclear_shapes_ch = Channel.empty()
    def viz_points_ch         = Channel.empty()
    def viz_cyto_ch           = Channel.empty()
    def viz_sdo_index_ch      = Channel.empty()

    if (params.enable_c2s_viz) {
        // visualize requires the .zarr.zip; reject configurations that
        // turned the zip off — there's no path to viz without it.
        if (!params.avsd_zip_spatialdata) {
            error "CELLS2STATS_SPATIALDATABUILD_VIZ (visualize) requires avsd_zip_spatialdata=true (the .zarr.zip is the input)."
        }
        ch_sdo = BUILD_SPATIALDATA.out.spatialdata_zip.map { zip -> [[id: run_id], zip] }
        CELLS2STATS_SPATIALDATABUILD_VIZ ( ch_sdo )
        ch_versions           = ch_versions.mix(CELLS2STATS_SPATIALDATABUILD_VIZ.out.versions)
        viz_cell_shapes_ch    = CELLS2STATS_SPATIALDATABUILD_VIZ.out.cell_shapes
        viz_nuclear_shapes_ch = CELLS2STATS_SPATIALDATABUILD_VIZ.out.nuclear_shapes
        viz_points_ch         = CELLS2STATS_SPATIALDATABUILD_VIZ.out.points
        viz_cyto_ch           = CELLS2STATS_SPATIALDATABUILD_VIZ.out.cyto_viz
        viz_sdo_index_ch      = CELLS2STATS_SPATIALDATABUILD_VIZ.out.sdo_index
    } else {
        log.info "BUILD_SPATIALDATA_SUBWORKFLOW: skipping CELLS2STATS_SPATIALDATABUILD_VIZ (enable_c2s_viz=false)"
    }

    // CELLS2STATS_GENERATE_QC_REPORT — external Cell Painting QC
    // (cells2stats generate_qc_report → qc_report.html under cells2stats/qc/).
    // Distinct from SPATIALDATA_QC_REPORT below (internal run-quality-report →
    // <run_id>.qc.* under spatialdata/qc/). Gated by enable_c2s_qc_report.
    def c2s_qc_report_ch = Channel.empty()

    if (params.enable_c2s_qc_report) {
        if (!params.avsd_zip_spatialdata) {
            error "CELLS2STATS_GENERATE_QC_REPORT requires avsd_zip_spatialdata=true (the .zarr.zip is the input)."
        }
        ch_sdo_for_c2s_qc = BUILD_SPATIALDATA.out.spatialdata_zip.map { zip -> [[id: run_id], zip] }
        CELLS2STATS_GENERATE_QC_REPORT ( ch_sdo_for_c2s_qc )
        ch_versions      = ch_versions.mix(CELLS2STATS_GENERATE_QC_REPORT.out.versions)
        c2s_qc_report_ch = CELLS2STATS_GENERATE_QC_REPORT.out.qc_report
    } else {
        log.info "BUILD_SPATIALDATA_SUBWORKFLOW: skipping CELLS2STATS_GENERATE_QC_REPORT (enable_c2s_qc_report=false)"
    }

    // SPATIALDATA_QC_REPORT is gated by params.avsd_qc_enabled (default false;
    // needs spatialdata_analysis_container_url/_tag). When disabled, QC emits fall back to empty
    // channels so the emit: block remains wired regardless of toggle state.
    def qc_html_ch         = Channel.empty()
    def qc_summary_tsv_ch  = Channel.empty()
    def qc_summary_json_ch = Channel.empty()

    if (params.avsd_qc_enabled) {
        // run-quality-report consumes the .zarr.zip; reject configurations that
        // turned the zip off — there's no path to QC without it.
        if (!params.avsd_zip_spatialdata) {
            error "SPATIALDATA_QC_REPORT requires avsd_zip_spatialdata=true (the .zarr.zip is the input)."
        }
        if (!params.spatialdata_analysis_container_url || !params.spatialdata_analysis_container_tag) {
            error "SPATIALDATA_QC_REPORT: avsd_qc_enabled=true but spatialdata_analysis_container_url/_tag are unset. Set both (the report image is not part of the public release) or disable avsd_qc_enabled."
        }
        ch_sdo_for_qc = BUILD_SPATIALDATA.out.spatialdata_zip.map { zip -> [[id: run_id], zip] }
        SPATIALDATA_QC_REPORT ( ch_sdo_for_qc )
        ch_versions        = ch_versions.mix(SPATIALDATA_QC_REPORT.out.versions)
        qc_html_ch         = SPATIALDATA_QC_REPORT.out.qc_html
        qc_summary_tsv_ch  = SPATIALDATA_QC_REPORT.out.summary_tsv
        qc_summary_json_ch = SPATIALDATA_QC_REPORT.out.summary_json
    } else {
        log.info "BUILD_SPATIALDATA_SUBWORKFLOW: skipping SPATIALDATA_QC_REPORT (avsd_qc_enabled=false)"
    }

    emit:
    versions          = ch_versions
    spatialdata_zip   = BUILD_SPATIALDATA.out.spatialdata_zip
    spatialdata_zarr  = BUILD_SPATIALDATA.out.spatialdata_zarr
    viz_cell_shapes    = viz_cell_shapes_ch
    viz_nuclear_shapes = viz_nuclear_shapes_ch
    viz_points         = viz_points_ch
    viz_cyto           = viz_cyto_ch
    viz_sdo_index      = viz_sdo_index_ch
    c2s_qc_report      = c2s_qc_report_ch
    qc_html            = qc_html_ch
    qc_summary_tsv     = qc_summary_tsv_ch
    qc_summary_json    = qc_summary_json_ch
}
