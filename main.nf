#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include { softwareVersionsToYAML } from './subworkflows/nf-core/utils_nfcore_pipeline'

// Subworkflows
include { FASTQ2PARQUET_3PRIME } from './subworkflows/local/fastq2parquet_3prime/main'
include { BUILD_SPATIALDATA_SUBWORKFLOW } from './subworkflows/local/build_spatialdata/main'
include { CELLS2STATS_SUBWORKFLOW } from './subworkflows/elembio/cells2stats/main'
include { BASES2FASTQ_SUBWORKFLOW } from './subworkflows/elembio/bases2fastq/main'


// FASTA and STAR index come from --genome as a pair; --genes_gtf may override the genome's annotation
def custom_refs = ['fasta', 'star_index', 'genes_gtf'].findAll { params.containsKey(it) && params[it] }
def custom_genome = custom_refs - ['genes_gtf']
if (!params.igenomes_ignore && custom_genome) {
    exit 1, "ERROR: ${custom_genome.collect { '--' + it }.join(', ')} cannot be combined with --genome '${params.genome}'. " +
            "The FASTA and STAR index are derived from --genome; for custom references set --igenomes_ignore true and supply --fasta, --star_index and --genes_gtf together."
}
if (params.igenomes_ignore && custom_refs.size() < 3) {
    exit 1, "ERROR: --igenomes_ignore requires --fasta, --star_index and --genes_gtf together. " +
            "Missing: ${(['fasta', 'star_index', 'genes_gtf'] - custom_refs).collect { '--' + it }.join(', ')}"
}

// Only genomes defined in conf/igenomes.config are supported
if (!params.igenomes_ignore && !params.genomes?.containsKey(params.genome)) {
    exit 1, "ERROR: --genome '${params.genome}' is not supported. Supported: ${params.genomes?.keySet()?.sort()?.join(', ')}."
}

// Pull in igenomes
params.fasta = WorkflowMain.getGenomeAttribute(params, 'fasta')
params.fasta_fai = WorkflowMain.getGenomeAttribute(params, 'fasta_fai')
params.genome_file = WorkflowMain.getGenomeAttribute(params, 'genome_file')
params.genome_dict = WorkflowMain.getGenomeAttribute(params, 'genome_dict')
params.chrom_sizes = WorkflowMain.getGenomeAttribute(params, 'chrom_sizes')

params.star_index = WorkflowMain.getGenomeAttribute(params, 'star')
params.gencode_gtf = WorkflowMain.getGenomeAttribute(params, 'gencode_gtf')
params.star_bed = WorkflowMain.getGenomeAttribute(params, 'bed12')

// A null igenomes_base renders the paths above as "null/Homo_sapiens/..." — catch it here.
if (!params.igenomes_ignore && !params.igenomes_base) {
    exit 1, "ERROR: 'params.igenomes_base' is unset. Keep the default reference bucket, " +
            "point it at a mirror, or set --igenomes_ignore and pass --fasta, --star_index and --genes_gtf."
}

// `params.run_dir` is required, but the strict checks happen inside `workflow {}`
// below so that `nextflow inspect` (which loads main.nf without params being set)
// can succeed during e.g. `nf-core modules update` container-config regeneration.
def run_dir = (params.run_dir ?: '').replaceAll(/\/$/, '')

// run_id extraction — keep in sync with bases2fastq-nf / cells2stats-nf main.nf
def analysisRunMatch = (run_dir =~ /.*\/runs\/[^\/]+\/([^\/]+)\/analysis\/[^\/]+(?:\/|$)/)
def run_id = params.id ?: (analysisRunMatch ? analysisRunMatch[0][1] : (run_dir ? file(run_dir).name : 'unset'))

// Warn and disable c2s_well — not supported in this workflow
// (b2f, c2s, and build_spatialdata must all process the same wells)
if (params.c2s_well) {
    log.warn "WARNING: --c2s_well is not supported in this workflow " +
             "(b2f, c2s, and build_spatialdata must process the same data). " +
             "Ignoring c2s_well=${params.c2s_well}."
    params.c2s_well = []
}

if (params.tca_manifest_csv && params.c2s_tca_manifest_csv) {
    log.warn "WARNING: --c2s_tca_manifest_csv overrides shared --tca_manifest_csv for cells2stats. " +
             "bases2fastq will continue to use the shared TCA unless --b2f_tca_manifest_csv is also set."
}
if (params.tca_manifest_csv && params.b2f_tca_manifest_csv) {
    log.warn "WARNING: --b2f_tca_manifest_csv overrides shared --tca_manifest_csv for bases2fastq. " +
             "cells2stats will continue to use the shared TCA unless --c2s_tca_manifest_csv is also set."
}

// Validate reference genome inputs (resolved from iGenomes or user-provided)
if (!params.fasta) {
    exit 1, "ERROR: Reference genome FASTA not found. Check --genome '${params.genome}'."
}
if (!params.star_index) {
    exit 1, "ERROR: STAR index not found. Check --genome '${params.genome}'."
}
def star_modes = (params.star_profiles instanceof Map) ? params.star_profiles.keySet() as List : ['star_default']
if (!(params.star_mode?.toString() in star_modes)) {
    exit 1, """\
ERROR: unknown --star_mode '${params.star_mode}'.
  Expected one of: ${star_modes.sort().join(', ')}
  Or compose -profile star_default / star_relaxed / …"""
}
[params.fasta, params.star_index].findAll { it }.each { path ->
    if (!file(path).exists()) { exit 1, "ERROR: Required file does not exist: ${path}" }
}

// Run-dir-dependent file staging + Panel.json parsing.
// Guarded on params.run_dir so `nextflow inspect` (which loads main.nf without
// run_dir being set) can succeed; the workflow{} block re-validates run_dir
// presence + on-disk existence before execution.
def run_parameters_json     = null
def run_manifest_csv        = null
def genes_gtf               = (params.genes_gtf ?: params.gencode_gtf) ? file(params.genes_gtf ?: params.gencode_gtf, checkIfExists: true) : null
def genes_bed12             = params.genes_bed12 ? file(params.genes_bed12, checkIfExists: true) : params.star_bed
def batch_assay_map         = [:]
def has_sequencing_batches  = false

if (params.run_dir) {
    def default_run_parameters_json = "${run_dir}/RunParameters.json"
    run_parameters_json = file(params.run_parameters_json ?: default_run_parameters_json, checkIfExists: true)

    def default_run_manifest_csv = "${run_dir.replaceAll('/analysis/.*\$', '')}/RunManifest.csv"
    run_manifest_csv = file(params.run_manifest_csv ?: default_run_manifest_csv, checkIfExists: true)

    if (!genes_gtf) {
        exit 1, "ERROR: GENCODE GTF not found. Check --genome '${params.genome}' (genome entry needs a gencode_gtf)."
    }

    // Parse Panel.json to get batch -> AssayType mapping
    // This maps batch names (e.g., B01, B02) to their assay types (e.g., ThreePrimeUntargeted)
    def panel_json_path = params.c2s_panel_json ?: "${run_dir.replaceAll('/analysis/.*\$', '')}/Panel.json"
    def panel_json_file = file(panel_json_path, checkIfExists: true)
    def panel_json = new groovy.json.JsonSlurper().parse(panel_json_file)

    // cells2stats 1.4.0-rc8+ synthesizes per-batch Bkg_RED/Bkg_GRN intensity features.
    // A panel target that resolves to one of those base names (exact or with a
    // measurement suffix) duplicates a RawCellStats column and fails SpatialData
    // build (polars DuplicateError). Per-base background panels (Bkg_RED_A,
    // Bkg_GRN_T, ...) do not collide and are allowed. Suffix list mirrors
    // elembio-spatialdata-build `_BASE_FEATURE_SUFFIXES` (longest-first).
    def bkg_suffixes = [
        '_MeanIntensityOfFractionAboveThreshold_Cytoplasmic',
        '_MeanIntensityOfFractionAboveThreshold_Nuclear',
        '_FractionAboveThreshold_Cytoplasmic',
        '_FractionAboveThreshold_Nuclear',
        '_MeanIntensityOfFractionAboveThreshold',
        '_FractionAboveThreshold',
        '_Cytoplasmic',
        '_NuclearRatio',
        '_Nuclear',
    ]
    def bkg_imaging_targets = (panel_json.ImagingTargets ?: []).findAll { t ->
        def name = t?.Target?.toString() ?: ''
        def suffix = bkg_suffixes.find { name.endsWith(it) } ?: ''
        def base = suffix ? name[0..<(name.length() - suffix.length())] : name
        base == 'Bkg_RED' || base == 'Bkg_GRN'
    }.collect { it.Target }.unique()
    if (bkg_imaging_targets) {
        exit 1, """\
ERROR: Panel.json lists ImagingTargets that collide with cells2stats ${params.c2s_container_tag} synthesized backgrounds:
  ${bkg_imaging_targets.join(', ')}
Panel: ${panel_json_path}

c2s emits Bkg_RED/Bkg_GRN columns itself. Rename those targets so they do not
resolve to base name Bkg_RED or Bkg_GRN (exact or with a measurement suffix),
or pass a corrected panel via --c2s_panel_json. Per-base names such as
Bkg_RED_A / Bkg_GRN_T are fine. See --disable-per-batch-background to turn off
the synthesized background features instead."""
    }

    panel_json.DISSPrimerTubes?.each { tube ->
        if (tube.BatchName && tube.AssayType) {
            batch_assay_map[tube.BatchName] = tube.AssayType
        }
    }

    panel_json.BarcodingPrimerTubes?.each { tube ->
        if (tube.BatchName) {
            batch_assay_map[tube.BatchName] = "Barcoding"
        }
    }

    panel_json.ImagingPrimerTubes?.each { tube ->
        if (tube.BatchName) {
            batch_assay_map[tube.BatchName] = tube.Type ?: "Imaging"
        }
    }

    // AVITI runs that are e.g. imaging-only have no sequencing batches in
    // RunParameters.json; bases2fastq aborts with "BaseCalling/BaseCalls/
    // directory missing from primary analysis" if invoked. Skip the whole
    // bases2fastq subworkflow in that case.
    def rp_json = new groovy.json.JsonSlurper().parse(run_parameters_json)
    def sequencing_batch_types = ['BarcodingBatch', 'DirectInSampleSequencingBatch'] as Set
    has_sequencing_batches = (rp_json.Batches ?: []).any { b ->
        b?.Type in sequencing_batch_types && b?.Name
    }
}

// Nextflow unwraps single-element JSON arrays to a scalar; guard before list operations
def asList = { value -> value instanceof List ? value : (value ? [value] : []) }

// Parse assay type category lists (which types map to which channel)
def three_prime_types = asList(params.f2p_three_prime_types)
def specialized_types = asList(params.f2p_specialized_types)
def targeted_tx_types = asList(params.f2p_targeted_tx_types)

def has_three_prime_batches = batch_assay_map.values().any { three_prime_types.contains(it) }
if (has_three_prime_batches && !genes_gtf) {
    exit 1, """\
ERROR: a GENCODE GTF is required when the run has 3' untargeted batches.

The 3' SAF builder requires a GENCODE GTF (gene rows with gene_type, UTR/exon
features, gene_name). It is derived from --genome (gencode_gtf in the genome
entry); with --igenomes_ignore pass --genes_gtf (GENCODE release 31 or later)."""
}

// Build formatted batch info for logging - show which channel each batch maps to
def batch_info_lines = batch_assay_map.collect { batch, assay_type ->
    def channel = "other"
    if (three_prime_types.contains(assay_type)) channel = "3prime"
    else if (specialized_types.contains(assay_type)) channel = "specialized"
    else if (targeted_tx_types.contains(assay_type)) channel = "targeted_tx"
    def marker = (channel == "other") ? "─" : "▸"
    "   ${marker} ${batch.padRight(5)} ${assay_type.padRight(30)} → ${channel}"
}.join('\n')

log.info """\
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   E L E M B I O - M U L T I O M I C S - N F
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 ▸ Run Info
 ──────────────────────────────────────────────────────────────────────
   run_dir:  ${run_dir}
   run_id:   ${run_id}
   outdir:   ${params.outdir}

 ▸ Data Filtering (shared by c2s & b2f)
 ──────────────────────────────────────────────────────────────────────
   filter_batch: ${params.filter_batch ?: '*'}
   tile:         ${params.tile ? params.tile : '*'}

 ▸ Assay Type Channel Mapping
 ──────────────────────────────────────────────────────────────────────
   3prime:       ${three_prime_types}
   specialized:  ${specialized_types}
   targeted_tx:  ${targeted_tx_types}

 ▸ Panel.json Batches
 ──────────────────────────────────────────────────────────────────────
${batch_info_lines}
   has_three_prime: ${batch_assay_map.values().any { three_prime_types.contains(it) }}

 ▸ cells2stats (c2s analyze)
 ──────────────────────────────────────────────────────────────────────
   container:           ${params.c2s_container_url}:${params.c2s_container_tag}
   tca_manifest_csv:    ${params.tca_manifest_csv ?: 'N/A'}  (shared; fans out to b2f+c2s)
   c2s_run_manifest:    ${params.c2s_run_manifest ?: 'N/A'}
   c2s_panel_json:      ${params.c2s_panel_json ?: 'N/A'}
   c2s_tca_manifest:    ${params.c2s_tca_manifest_csv ?: params.tca_manifest_csv ?: 'N/A'}
   c2s_log_level:       ${params.c2s_log_level ?: 'info'}
   c2s_tar_program_logs: ${params.c2s_tar_program_logs}
   c2s_static_overlap_stitching: ${params.c2s_static_overlap_stitching}
   c2s_disable_per_batch_background: ${params.c2s_disable_per_batch_background}
   c2s_process_imaging_targets: ${params.c2s_process_imaging_targets}
   c2s_enable_illumination_correction: ${params.c2s_enable_illumination_correction}
   c2s_disable_illumination_correction: ${params.c2s_disable_illumination_correction}
   c2s_args:            ${params.c2s_args ? "${params.c2s_args} (deprecated; use ext.args in conf/modules.config)" : 'N/A'}

 ▸ cells2stats visualize
 ──────────────────────────────────────────────────────────────────────
   container:           ${params.c2s_container_url}:${params.c2s_container_tag}
   enable_c2s_viz:      ${params.enable_c2s_viz}  ${params.enable_c2s_viz ? '(viz process WILL run)' : '(gated off via ext.when; viz process SKIPPED)'}

 ▸ cells2stats generate_qc_report (external CP QC)
 ──────────────────────────────────────────────────────────────────────
   container:           ${params.c2s_container_url}:${params.c2s_container_tag}
   enable_c2s_qc_report: ${params.enable_c2s_qc_report}  ${params.enable_c2s_qc_report ? '(WILL run → cells2stats/qc/qc_report.html)' : '(SKIPPED)'}

 ▸ spatialdata QC report (run-quality report)
 ──────────────────────────────────────────────────────────────────────
   container:           ${params.spatialdata_analysis_container_url}:${params.spatialdata_analysis_container_tag}
   avsd_qc_enabled:     ${params.avsd_qc_enabled}  ${params.avsd_qc_enabled ? '(WILL run → spatialdata/qc/*.qc.html)' : '(SKIPPED; needs avsd_qc_enabled + spatialdata_analysis_container_url/_tag)'}

 ▸ bases2fastq (b2f)
 ──────────────────────────────────────────────────────────────────────
   container:           ${params.b2f_container_url}:${params.b2f_container_tag}
   has_sequencing_batches: ${has_sequencing_batches}  ${has_sequencing_batches ? '(b2f subworkflow WILL run)' : '(b2f subworkflow SKIPPED — no Batches of sequencing type in RunParameters.json)'}
   run_manifest_csv:    ${run_manifest_csv}
   segmentation_dir:    ${params.segmentation_dir ?: 'N/A'}
   analysis_region_dir: ${params.analysis_region_dir ?: 'N/A'}
   b2f_panel_json:      ${params.b2f_panel_json ?: 'N/A'}
   b2f_tca_manifest:    ${params.b2f_tca_manifest_csv ?: params.tca_manifest_csv ?: 'N/A'}
   b2f_log_level:       ${params.b2f_log_level ?: 'INFO'}
   b2f_args:            ${params.b2f_args ? "${params.b2f_args} (deprecated; use ext.args in conf/modules.config)" : 'N/A'}

 ▸ fastq2parquet_3prime (f2p_3p)
 ──────────────────────────────────────────────────────────────────────
   container: ${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}
   genome: ${params.igenomes_ignore ? 'custom (--igenomes_ignore)' : params.genome}
   fasta: ${params.fasta}
   star_index: ${params.star_index}
   star_mode: ${params.star_mode}
   genes_gtf: ${genes_gtf}
   genes_bed12: ${genes_bed12}
   run_parameters_json: ${run_parameters_json}
   slop_5p_bp: ${params.f2p_3p_slop_5p_bp}
   slop_3p_bp: ${params.f2p_3p_slop_3p_bp}
   include_gene_types: ${params.f2p_3p_include_gene_types}
   ignore_samples: ${params.ignore_samples}

 ▸ Config
 ──────────────────────────────────────────────────────────────────────
   custom_config_version: ${params.custom_config_version}
   custom_config_base: ${params.custom_config_base}
   igenomes_base: ${params.igenomes_base}
   igenomes_ignore: ${params.igenomes_ignore}
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 """

workflow {

    if (!params.run_dir) {
        exit 1, "ERROR: 'params.run_dir' must be set."
    }
    if (!file(params.run_dir).exists()) {
        exit 1, "ERROR: Specified 'params.run_dir' does not exist: ${params.run_dir}"
    }

    // Container defaults ship in nextflow.config; a launch can still null them.
    // Fail here, before any task, instead of at the first container pull.
    def container_params = [
        'c2s_container_url', 'c2s_container_tag',
        'b2f_container_url', 'b2f_container_tag',
        'elembiodisstools_container_url', 'elembiodisstools_container_tag',
        'spatialdata_build_container_url', 'spatialdata_build_container_tag',
    ]
    def unset_containers = container_params.findAll { !params[it] }
    if (unset_containers) {
        exit 1, "ERROR: container parameters are not set: ${unset_containers.join(', ')}. " +
                "Set each url/tag at launch (--<param> or -params-file) or compose a profile " +
                "that sets them."
    }

    ch_versions = Channel.empty()

    //
    // Provenance — workflow manifest + four container url:tag pairs + full resolved param map
    // Static value (known at workflow load); collectFile publishes pipeline_info/Provenance.json.
    // .Tools + .Params are also fed into AGGREGATE_F2P_METRICS for in-place embedding into RunStats.json.
    //
    // jsonSafe recursively stringifies non-primitive leaves so JsonOutput doesn't recurse
    // infinitely on java.nio.file.Path values in `params` (Path implements
    // Iterable<Path>; JsonOutput would iterate its segments, each a Path, ad infinitum).
    //
    Closure jsonSafe
    jsonSafe = { obj ->
        if (obj == null)                                       return null
        if (obj instanceof Map)                                return obj.collectEntries { k, v -> [(k.toString()): jsonSafe(v)] }
        if (obj instanceof Collection)                         return obj.collect { jsonSafe(it) }
        if (obj instanceof Number || obj instanceof Boolean)   return obj
        return obj.toString()
    }

    def provenance_map = [
        // Launch-environment fields (launchDir/projectDir/workDir/userName) are
        // deliberately omitted: nothing downstream reads them and they describe
        // the launcher, not the run. The -params-file value is redacted because
        // Seqera supplies tokenized ephemeral URLs there.
        Workflow: [
            name:            workflow.manifest.name,
            version:         workflow.manifest.version,
            nextflowVersion: workflow.nextflow.version,
            runName:         workflow.runName,
            sessionId:       workflow.sessionId,
            commandLine:     workflow.commandLine?.replaceAll(/-params-file[=\s]+\S+/, '-params-file <redacted>'),
            profile:         workflow.profile,
            commitId:        workflow.commitId,
            revision:        workflow.revision,
        ].findAll { _k, v -> v != null },
        // Tools with an empty url or tag are omitted rather than rendered as "null:null".
        Tools: [
            'cells2stats':               [ params.c2s_container_url,               params.c2s_container_tag ],
            'bases2fastq':               [ params.b2f_container_url,               params.b2f_container_tag ],
            'elembio-diss-tools':        [ params.elembiodisstools_container_url, params.elembiodisstools_container_tag ],
            'elembio-spatialdata-build': [ params.spatialdata_build_container_url,       params.spatialdata_build_container_tag ],
        ].findAll { _k, v -> v[0] && v[1] }.collectEntries { k, v -> [ (k): [ image: "${v[0]}:${v[1]}", url: v[0], tag: v[1] ] ] },
        // Full resolved param map (flat) — NOT paramsSummaryMap, which emits only
        // non-default, schema-grouped params (so f2p_3p_* defaults would be dropped and
        // the QC report couldn't read them).  jsonSafe stringifies any Path leaves.
        Params: params,
    ]

    ch_provenance_json = Channel.of(groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(jsonSafe(provenance_map))))
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:     'Provenance.json',
            newLine:  false,
        )

    //
    // Prepare common inputs
    //
    ch_genome = [params.fasta, params.fasta_fai, params.genome_file, params.chrom_sizes, params.genome_dict]
        
    ch_star_index = Channel.value(params.star_index)
    ch_genes_gtf = Channel.value(genes_gtf)
    ch_genes_bed12 = Channel.value(genes_bed12)

    //
    // SUBWORKFLOW: CELLS2STATS_SUBWORKFLOW
    // Generate cell-level statistics from AVITI run directory
    //
    def meta = [id: run_id]
    ch_run_dir = Channel.value([meta, run_dir])

    // c2s channel inputs (4 optional file paths)
    // Shared tca_manifest_csv fans out to b2f + c2s unless a per-tool override is set
    // (production TCA should be identical for both tools).
    def c2s_tca_manifest_path = params.c2s_tca_manifest_csv ?: params.tca_manifest_csv
    def b2f_tca_manifest_path = params.b2f_tca_manifest_csv ?: params.tca_manifest_csv

    ch_c2s_panel        = params.c2s_panel_json        ? Channel.value(file(params.c2s_panel_json,        checkIfExists: true)) : Channel.value([])
    ch_c2s_run_manifest = params.c2s_run_manifest      ? Channel.value(file(params.c2s_run_manifest,      checkIfExists: true)) : Channel.value([])
    ch_segmentation     = params.segmentation_dir      ? Channel.value(file(params.segmentation_dir,      checkIfExists: true)) : Channel.value([])
    ch_c2s_tca_manifest = c2s_tca_manifest_path        ? Channel.value(file(c2s_tca_manifest_path,        checkIfExists: true)) : Channel.value([])

    CELLS2STATS_SUBWORKFLOW (
        ch_run_dir,
        ch_c2s_panel,
        ch_c2s_run_manifest,
        ch_segmentation,
        ch_c2s_tca_manifest,
    )
    ch_versions = ch_versions.mix(CELLS2STATS_SUBWORKFLOW.out.versions)

    //
    // SUBWORKFLOW: BASES2FASTQ_SUBWORKFLOW
    // Convert base calls to FASTQ files
    //

    // b2f channel inputs (4 optional file paths; segmentation + analysis_region
    // are shared with c2s/build-spatialdata, container 2.4.0-internal+ accepts both)
    ch_analysis_region  = params.analysis_region_dir   ? Channel.value(file(params.analysis_region_dir,   checkIfExists: true)) : Channel.value([])
    ch_b2f_panel        = params.b2f_panel_json        ? Channel.value(file(params.b2f_panel_json,        checkIfExists: true)) : Channel.value([])
    ch_b2f_tca_manifest = b2f_tca_manifest_path        ? Channel.value(file(b2f_tca_manifest_path,        checkIfExists: true)) : Channel.value([])

    if (has_sequencing_batches) {
        BASES2FASTQ_SUBWORKFLOW (
            ch_run_dir,
            run_manifest_csv,
            ch_segmentation,
            ch_analysis_region,
            ch_b2f_panel,
            ch_b2f_tca_manifest,
        )
        ch_b2f_sample_fastq = BASES2FASTQ_SUBWORKFLOW.out.sample_fastq
        ch_b2f_metrics_dir  = BASES2FASTQ_SUBWORKFLOW.out.metrics_dir.ifEmpty([])
        ch_versions         = ch_versions.mix(BASES2FASTQ_SUBWORKFLOW.out.versions)
    } else {
        log.info "Skipping BASES2FASTQ_SUBWORKFLOW: no sequencing batches in RunParameters.json"
        ch_b2f_sample_fastq = Channel.empty()
        ch_b2f_metrics_dir  = Channel.value([])
    }

    //
    // Parse BASES2FASTQ_SUBWORKFLOW output to create FASTQ sample channels
    // FASTQ files are structured as: Samples/WellXX/SampleName_R1.fastq.gz
    // Sample names contain batch info: A1_B05 -> batch is B05
    //
    ch_fastq_all = ch_b2f_sample_fastq
        .flatten()
        .map { fastq ->
            // Extract sample name from filename (remove _R1/_R2 and .fastq.gz)
            def sample_id = fastq.name.replaceAll(/_R[12]\.fastq\.gz$/, '')
            // Parent directory is the well; bases2fastq prefixes with "Well" (e.g. "WellA1")
            def well = fastq.parent.name.replaceAll(/^Well/, '')
            // Extract batch from sample name (e.g., "A1_B05" or "B1_B05" -> "B05")
            // Must match underscore followed by B and digits to avoid matching well names like "B1"
            def batch_match = (sample_id =~ /_B(\d+)/)
            def batch = batch_match ? "B${batch_match[0][1]}" : "Unknown"
            // Look up assay type from Panel.json mapping
            def assay_type = batch_assay_map[batch] ?: "Other"
            def is_r1 = fastq.name.contains('_R1')
            [sample_id, well, batch, assay_type, is_r1, fastq]
        }
        .groupTuple(by: [0, 1, 2, 3])  // Group by sample_id, well, batch, assay_type
        .map { sample_id, well, batch, assay_type, is_r1_list, files ->
            def r1 = files.find { it.name.contains('_R1') }
            def r2 = files.find { it.name.contains('_R2') }
            def single_end = (r2 == null)
            def sample_meta = [
                id: sample_id,
                sample: sample_id,
                well: well,
                batch: batch,
                assay_type: assay_type,
                single_end: single_end
            ]
            single_end ? [sample_meta, [r1]] : [sample_meta, [r1, r2]]
        }
        .filter { sample_meta, files -> 
            // Filter out ignored samples (case-insensitive partial match)
            !asList(params.ignore_samples).any { ignore -> 
                sample_meta.sample.toLowerCase().contains(ignore.toLowerCase()) 
            }
        }
        
    // Branch FASTQs by assay type category into named channels
    // Uses configurable type lists (e.g., "Transcript" can be mapped to three_prime)
    ch_fastq_branched = ch_fastq_all.branch {
        sample_meta, files ->
            three_prime:    three_prime_types.contains(sample_meta.assay_type)
            specialized:    specialized_types.contains(sample_meta.assay_type)
            targeted_tx:    targeted_tx_types.contains(sample_meta.assay_type)
            other: true     // Catch-all for Barcoding, Imaging, etc.
    }

    // Named channels for each assay type category
    ch_fastq_three_prime   = ch_fastq_branched.three_prime       // -> FASTQ2PARQUET_3PRIME
    ch_fastq_specialized   = ch_fastq_branched.specialized       // -> future subworkflow
    ch_fastq_targeted_tx   = ch_fastq_branched.targeted_tx       // -> future subworkflow
    ch_fastq_other         = ch_fastq_branched.other             // not processed

    //
    // SUBWORKFLOW: FASTQ2PARQUET_3PRIME
    // Align 3' untargeted FASTQ reads, assign to features, and generate polony parquets
    //
    def has_three_prime = batch_assay_map.values().any { three_prime_types.contains(it) }

    if (has_three_prime) {
        FASTQ2PARQUET_3PRIME (
            ch_fastq_three_prime,
            ch_star_index,
            ch_genes_gtf,
            ch_genes_bed12,
            ch_genome,
            run_parameters_json,
            CELLS2STATS_SUBWORKFLOW.out.raw_cell_stats_parquet,
            CELLS2STATS_SUBWORKFLOW.out.rawreads_files,
            run_id,
            ch_provenance_json
        )
        ch_f2p_polony_parquet = FASTQ2PARQUET_3PRIME.out.polony_parquet
        ch_f2p_genes_gtf      = ch_genes_gtf                           // raw GTF reused downstream (build-spatialdata parses it)
        ch_f2p_metrics_dir    = FASTQ2PARQUET_3PRIME.out.metrics_dir   // single opaque --f2p-3p-dir (RunStats + genes/{gtf,metadata})
        // Catalog always available from GENERATE_FEATURE_SAF even when no 3' FASTQs /
        // F2P_METRICS_DIR never ran — BUILD uses it as --threeprime-intervals-metadata-path.
        ch_f2p_intervals_metadata = FASTQ2PARQUET_3PRIME.out.intervals_metadata
        ch_versions = ch_versions.mix(FASTQ2PARQUET_3PRIME.out.versions)
    } else {
        ch_f2p_polony_parquet = Channel.empty()
        ch_f2p_genes_gtf      = Channel.empty()
        ch_f2p_metrics_dir    = Channel.empty()
        ch_f2p_intervals_metadata = Channel.empty()
    }

    //
    // SUBWORKFLOW: BUILD_SPATIALDATA_SUBWORKFLOW
    // Build SpatialData .zarr from polony parquets, genes, and cells2stats outputs
    //

    // Per-tool curated small-metadata mirrors (Wave 4 tool-dir inputs). c2s
    // always runs and emits a [meta, dir] tuple; b2f/f2p_3p emit plain path
    // channels and may be absent — the subworkflow guards both with .ifEmpty([])
    // so BUILD_SPATIALDATA still fires. ch_b2f_metrics_dir is set above in the
    // BASES2FASTQ_SUBWORKFLOW if/else (Channel.value([]) when b2f is skipped).

    BUILD_SPATIALDATA_SUBWORKFLOW (
        run_id,
        run_dir,
        run_parameters_json,
        ch_f2p_polony_parquet,
        ch_f2p_genes_gtf,
        CELLS2STATS_SUBWORKFLOW.out.raw_cell_stats_parquet,
        CELLS2STATS_SUBWORKFLOW.out.wells_dir,
        CELLS2STATS_SUBWORKFLOW.out.cell_segmentation,
        CELLS2STATS_SUBWORKFLOW.out.analysis_region,
        CELLS2STATS_SUBWORKFLOW.out.metrics_dir,
        ch_b2f_metrics_dir,
        ch_f2p_metrics_dir,
        ch_f2p_intervals_metadata,
        ch_provenance_json
    )
    ch_versions = ch_versions.mix(BUILD_SPATIALDATA_SUBWORKFLOW.out.versions)

    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:     'software_versions.yml',
            sort:     true,
            newLine:  true,
        )

    //
    // Future: Workflow-level MultiQC aggregating all subworkflows
    // BUILD_SPATIALDATA consumes CELLS2STATS / BASES2FASTQ / FASTQ2PARQUET
    // curated metrics dirs; the internal run-quality HTML report is the
    // customer-facing QC surface (f2p MultiQC retired with Picard HS).
    //

}
