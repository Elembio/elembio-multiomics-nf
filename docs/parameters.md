# Parameter Reference

Complete reference for all elembio-multiomics-nf parameters.

---

## Input/Output Parameters

### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `run_dir` | Path | Path to AVITI run directory. Can be local filesystem or S3 path. Must contain `RunParameters.json`, `RunManifest.csv`, and `Panel.json`. |

### Optional

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id` | String | Auto-detected | Run identifier. If not set: analysis-path rule when `run_dir` matches `.../runs/<instrument>/<run_id>/analysis/<analysis_id>/...`, else last path segment of `run_dir`. |
| `outdir` | Path | `./results` | Output directory. |
| `run_parameters_json` | Path | `{run_dir}/RunParameters.json` | Path to RunParameters.json file. |
| `run_manifest_csv` | Path | `{run_dir}/RunManifest.csv` | Path to RunManifest.csv file. Resolved relative to run_dir (after stripping any `/analysis/` suffix). |
| `tca_manifest_csv` | Path | `null` | Shared Target Cell Assignment manifest CSV (SpecializedTargeted / OPS). Fans out to both cells2stats and bases2fastq unless a schema-hidden per-tool override is set. Production runs should use this parameter so both tools receive the same file. |

---

## Shared Filtering Parameters

These parameters apply to both cells2stats and bases2fastq, ensuring consistent data subsetting:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `filter_batch` | String | `null` | Restrict to specific batch(es), comma-delimited (e.g., `B01,B02,B03`). |
| `tile` | List | `[]` | Tile regex pattern(s) (e.g., `["L2R01C01S1"]`). Drives b2f `-i`, c2s `--tile`, and build_spatialdata `--tile-filter`. When set, b2f auto-excludes all tiles first so the include works correctly. |
| `segmentation_dir` | Path | `null` | Custom cell segmentation directory. Threaded into a **shared `ch_segmentation` channel** wired into both `CELLS2STATS_SUBWORKFLOW` and `BASES2FASTQ_SUBWORKFLOW`; surfaces as `--segmentation` on both tools (bases2fastq ≥ 3.0). |
| `analysis_region_dir` | Path | `null` | Custom AnalysisRegion directory. Threaded as a channel input — composed in `main.nf` as `ch_analysis_region` and wired into `BASES2FASTQ_SUBWORKFLOW` (`--analysis-region`, b2f >= 2.4.0-internal). The same parameter still drives BUILD_SPATIALDATA's `--analysis-region-dir` override for the overlap stitcher; on non-overlap runs the BUILD_SPATIALDATA override is ignored. |

---

## Reference Genome Parameters

### Genome Selection

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `genome` | String | `GRCh38` | Reference genome key. Selects the FASTA, STAR index and GENCODE GTF from `igenomes_base`. Only **GRCh38** is in the default map. `GRCh38_chr20` is a chromosome-20 smoke slice loaded from `conf/igenomes_smoke.config` via `conf/test.config` — not a production genome. |
| `igenomes_base` | Path | `s3://elembio-static-public-244107694630-us-west-2/igenomes` | Base path of the reference layout: the Element reference bucket (iGenomes layout with STAR 2.7 indexes and GENCODE GTFs, anonymous read). Point it at a mirror of that layout to avoid remote reads. |
| `igenomes_ignore` | Boolean | `false` | Set to `true` to ignore the genome map and supply `fasta`, `star_index` and `genes_gtf` together. |

### Custom References

`fasta` and `star_index` are used only with `igenomes_ignore = true`, and then `fasta`, `star_index` and `genes_gtf` are all required. Passing `fasta` or `star_index` alongside `--genome` is rejected, so a STAR index can never be paired with a different genome by accident. `genes_gtf` may also be passed alongside `--genome` to replace the genome's default annotation; it must be on the same assembly.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fasta` | Path | From `genome` | Reference genome FASTA file. |
| `fasta_fai` | Path | From `genome` | FASTA index file (.fai). |
| `star_index` | Path | From `genome` | STAR genome index directory, built with STAR ≥ 2.7.4a. |
| `genes_gtf` | Path | From `genome` (GENCODE v47) | GENCODE gene annotation GTF on the same assembly as the genome. Release 47 is validated; other releases from 31 on (consolidated `lncRNA` biotype) are expected to run but are not validated. Pin one release per analysis. NCBI and Ensembl GTFs are not valid. Overrides the genome's annotation; required with `igenomes_ignore`. |
| `genes_bed12` | Path | From `genome` | Gene annotation BED12 file. |

---

## cells2stats (c2s) Parameters

### General Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_panel_json` | Path | `null` | Path to custom Panel.json. Passed to cells2stats via a **channel input** (`ch_c2s_panel`), not as a CLI string — the module composes `--panel {path}` from the staged file. Also used for the launch-time check that ImagingTargets do not resolve to base name `Bkg_RED` / `Bkg_GRN`. |
| `c2s_run_manifest` | Path | `null` | Path to custom run manifest (.csv or .json). Passed as a **channel input** (`ch_c2s_run_manifest`) — the module composes `--run-manifest {path}` from the staged file. |
| `c2s_tca_manifest_csv` | Path | `null` | Advanced: cells2stats-only TCA override. Prefer `tca_manifest_csv`. Schema-hidden; resolution is `c2s_tca_manifest_csv` → `tca_manifest_csv` → unset. |

### Processing Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_error_on_missing` | Boolean | `false` | Terminate on missing files. |
| `c2s_no_error_on_invalid` | Boolean | `false` | Skip invalid files instead of erroring. |
| `c2s_skip_cellprofiler` | Boolean | `false` | Skip CellProfiler execution. |
| `c2s_skip_qc_report` | Boolean | `true` | Skip cells2stats analyze QC report generation (`--skip-qc-report`). |
| `c2s_tar_program_logs` | Boolean | `true` | Tar/gz the Logs directory; when false, publish as directory. |
| `c2s_publish_spatialdata` | Boolean | `false` | Publish the c2s-internal `SpatialData/` to `cells2stats/SpatialData/`. Off by default; the canonical SpatialData is the one built by `BUILD_SPATIALDATA` at `spatialdata/{run_id}.zarr`. |
| `c2s_max_unassigned` | Integer | `1000` | Maximum unassigned sequences to report (1-10000). |
| `c2s_log_level` | String | `info` | Log level: debug, info, warning, error. |
| `c2s_static_overlap_stitching` | Boolean | `false` | Use default stitching for overlapping-tile runs (`--static-overlap-stitching`). |
| `c2s_disable_per_batch_background` | Boolean | `false` | Skip c2s-synthesized per-batch background features Bkg_RED/Bkg_GRN (`--disable-per-batch-background`). Does **not** allow panels whose ImagingTargets resolve to base name `Bkg_RED` / `Bkg_GRN` (exact or with a measurement suffix) — those fail at launch. Per-base names such as `Bkg_RED_A` are allowed. |
| `c2s_process_imaging_targets` | Boolean | `false` | Reprocess `_Raw` projections into corrected `Projection/` TIFFs before analysis (`--process-imaging-targets`). |
| `c2s_enable_illumination_correction` | Boolean | `false` | Force illumination correction on for every imaging target and enabled background (`--enable-illumination-correction`). Requires `c2s_process_imaging_targets`. Mutually exclusive with `c2s_disable_illumination_correction`. When both are `false`, panel `Analyses` / `RecipeValues` decide per target. |
| `c2s_disable_illumination_correction` | Boolean | `false` | Force illumination correction off for every target (`--disable-illumination-correction`). Requires `c2s_process_imaging_targets`. Mutually exclusive with `c2s_enable_illumination_correction`. When both are `false`, panel `Analyses` / `RecipeValues` decide per target. |

### OPS / SpecializedTargeted

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_target_mismatch_threshold` | Integer | `null` | Override OPS mismatch threshold for all sites (`--target-mismatch-threshold`, 0–4). |
| `c2s_specialized_targeted_min_query_length` | Integer | `null` | Minimum query-length gate for OPS alignments (`--specialized-targeted-min-query-length`, ≥12). |
| `c2s_generate_specialized_targeted_bams` | Boolean | `false` | Emit concatenated OPS BAMs (`--generate-specialized-targeted-bams`). |

### Targeted transcriptome

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_targeted_transcriptome_min_query_length` | Integer | `null` | Minimum query-length gate for targeted transcriptome (`--targeted-transcriptome-min-query-length`, ≥12). |
| `c2s_targeted_transcriptome_mismatch_threshold` | Integer | `null` | Override mismatch threshold (`--targeted-transcriptome-mismatch-threshold`, 0–10). |
| `c2s_targeted_transcriptome_min_insert_aligned` | Integer | `null` | Minimum insert bases for assignment (`--targeted-transcriptome-min-insert-aligned`; default 9 when unset by CLI). |
| `c2s_generate_targeted_transcriptome_bams` | Boolean | `false` | Emit concatenated targeted-transcriptome BAMs (`--generate-targeted-transcriptome-bams`). |

### Visualization / external QC orchestration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enable_c2s_viz` | Boolean | `true` | Run `CELLS2STATS_SPATIALDATABUILD_VIZ` (`cells2stats visualize`). Set `false` to skip. |
| `enable_c2s_qc_report` | Boolean | `true` | Run `CELLS2STATS_GENERATE_QC_REPORT` (`cells2stats generate_qc_report` → `cells2stats/qc/qc_report.html`). External CP report; distinct from the internal `avsd_qc_enabled` report. |
| `c2s_visualization_workers` | Integer | `null` | `--visualization-workers` for visualize (Stage A scan / Stage B encode); defaults to task CPUs. Requires cells2stats ≥1.4.0-rc12. |
| `c2s_viz_shape_smoothing_workers` | Integer | `null` | `--viz-shape-smoothing-workers` for visualize; defaults to `max(1, 2 * task.cpus / 3)`. Requires cells2stats ≥1.4.0-rc12. |

### Custom Arguments

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `c2s_args` | String | `""` | **DEPRECATED** catch-all string appended to the cells2stats CLI. Prefer overriding `withName: CELLS2STATS { ext.args = { ... } }` in a `-c custom.config` overlay; see [`conf/modules.config`](../conf/modules.config) for the canonical closure. Will be removed in a future release. |

---

## QC reports

| Report | Process | Toggle | Default | Publish | Notes |
|--------|---------|--------|---------|---------|-------|
| cells2stats QC | `CELLS2STATS_GENERATE_QC_REPORT` | `enable_c2s_qc_report` | `true` | `cells2stats/qc/qc_report.html` | `cells2stats generate_qc_report` |
| Run-quality report | `SPATIALDATA_QC_REPORT` | `avsd_qc_enabled` | `false` | `spatialdata/qc/<run_id>.qc.{html,tsv,json}` | Optional. Requires `spatialdata_analysis_container_url/_tag`; that image is not part of the public release. |
## bases2fastq (b2f) Parameters

### General Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `b2f_demux_only` | Boolean | `false` | Only demultiplex, skip FASTQ generation. |
| `b2f_detect_adapters` | Boolean | `false` | Detect and trim adapters. |
| `b2f_qc_only` | Boolean | `false` | Generate QC metrics only, no FASTQs. |
| `b2f_legacy_fastq` | Boolean | `false` | Use legacy naming: `SampleName_S1_L001_R1_001.fastq.gz` |
| `b2f_no_projects` | Boolean | `true` | Disable project directories (flat structure). |
| `b2f_split_lanes` | Boolean | `false` | Split output by lane. |
| `b2f_group_fastq` | Boolean | `false` | Group FASTQs by sample. |
| `b2f_force_index_orientation` | Boolean | `false` | Force index orientation. |
| `b2f_force_detect_index_orientation` | Boolean | `false` | Force re-detection of index orientation, ignoring any cached result (bases2fastq ≥ 3.0). |
| `b2f_log_level` | String | `INFO` | Log level: DEBUG, INFO, WARNING, ERROR. |

### Tile Exclusion

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `b2f_exclude_tile` | String | `null` | Regex for tiles to EXCLUDE. Auto-set to `L.R..C..S.` when `tile` is used, so includes work correctly. Override to customize. |

### Error Handling

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `b2f_error_on_missing` | Boolean | `false` | Error on missing files. |
| `b2f_no_error_on_invalid` | Boolean | `false` | Skip invalid files. |
| `b2f_num_unassigned` | Integer | `30` | Maximum unassigned sequences to report. |

### QC/Reporting

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `b2f_skip_multi_qc` | Boolean | `false` | Skip MultiQC report. |
| `b2f_skip_qc_report` | Boolean | `false` | Skip QC report generation. |
| `b2f_skip_empty_fq_files` | Boolean | `false` | Skip emission of empty FASTQ files (bases2fastq ≥ 3.0). |

### Cyto-FASTQ Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `b2f_cyto_fastq_mask` | String | `null` | Cycle mask for cyto FASTQ generation. |
| `b2f_panel_json` | Path | `null` | Path to Panel.json. Passed as a **channel input** (`ch_b2f_panel`) — the module composes `--panel {path}` from the staged file. |
| `b2f_per_target_fastq` | Boolean | `false` | Create per-target FASTQ for each cell assignment target. |
| `b2f_tca_manifest_csv` | Path | `null` | Advanced: bases2fastq-only TCA override (OPS / per-target FASTQ). Prefer `tca_manifest_csv`. Schema-hidden; resolution is `b2f_tca_manifest_csv` → `tca_manifest_csv` → unset. |

### Custom Arguments

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `b2f_args` | String | `""` | **DEPRECATED** catch-all string appended to the bases2fastq CLI. Prefer overriding `withName: BASES2FASTQ { ext.args = { ... } }` in a `-c custom.config` overlay; see [`conf/modules.config`](../conf/modules.config) for the canonical closure. Will be removed in a future release. |

---

## Assay Type Channel Mapping

Control how samples from `Panel.json` are routed to analysis subworkflows:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_three_prime_types` | List | `["ThreePrimeUntargeted", "Transcript"]` | Assay types routed to FASTQ2PARQUET_3PRIME. |
| `f2p_specialized_types` | List | `["SpecializedTargeted"]` | Assay types routed to specialized workflow (future). |
| `f2p_targeted_tx_types` | List | `["TargetedTranscriptomeProfiling"]` | Assay types routed to targeted workflow (future). |

Other assay types (e.g., `Barcoding`, `Imaging`) are not processed by any subworkflow.

---

## Sample Filtering

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ignore_samples` | List | `["Unassigned", "PhiX", "phiX", "CBPhiX", "Undetermined"]` | Sample names to exclude (case-insensitive partial match). |

---

## STAR Alignment Parameters

### Named stringency (`star_mode`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `star_mode` | String | `star_default` | Named STAR stringency for 3′ `STAR_ALIGN` (same names as RNA2counts `star_mode`). `star_default`: MatchNmin 0, score/match 0.66/0.66, multimapping 5. `relaxed`: pre-1.10.0 DiSS set (15 / 0.2 / 0.1, multimapping 10). Also `diss_strict` / `diss_balanced` / `diss_sensitive` / `diss_permissive`. Select with `--star_mode` or `-profile star_default` / `star_relaxed` / …. |

`STAR_ALIGN` reads `star_profiles[star_mode]`. Non-null individual knobs below
override the selected mode, preserving custom nfparams without changing the
named profiles.

### Alignment Stringency Overrides

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `star_outFilterMultimapNmax` | Integer | `null` | Override the selected mode's maximum mapping loci. |
| `star_outSAMmultNmax` | Integer | `null` | Override the selected mode's maximum alignments per read. |
| `star_outFilterMatchNmin` | Integer | `null` | Override the selected mode's minimum matched bases. |
| `star_outFilterScoreMinOverLread` | Float | `null` | Override the selected mode's minimum score/read-length ratio. |
| `star_outFilterMatchNminOverLread` | Float | `null` | Override the selected mode's minimum matched-bases/read-length ratio. |

### Splice Junction Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `star_alignSJoverhangMin` | Integer | `null` | Override the selected mode's minimum annotated splice-junction overhang. |
| `star_chimSegmentMin` | Integer | `null` | Override the selected mode's minimum chimeric segment length. |

### General Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `star_ignore_sjdbgtf` | Boolean | `true` | Ignore GTF for splice junction database. |
| `star_twopassmode` | String | `Basic` | Two-pass mode: `Basic`, `None`, or `null`. |
| `star_align_ends_type` | String | `Local` | Alignment ends type: `Local`, `EndToEnd`, `Extend5pOfRead1`, `Extend5pOfReads12`. |

---

## Feature Assignment Parameters (FASTQ2PARQUET_3PRIME)

### Feature Types

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_3p_strandedness` | String | `reverse` | Library strandedness for assignment (matches featureCounts `-s 2`). |

### SAF Construction (gen-feature-bed)

The SAF is built by `gen-feature-bed` (elembio-diss-tools) with slop baked into the annotation rows, so featureCounts `--readExtension5/3` are no longer used.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_3p_features` | String | `utr,exon,chrm` | **Single source of truth** for feature tier-group selection (comma-sep). Exon-union model: 3'UTR tiers + exon (catches UTR-less genes; synthetic dropped) + chrM umbrella. To count introns, add the tier: `utr,exon,intron,chrm`. (1.8.2 removed the additive `include_intron`/`include_chrm_umbrella` booleans.) |
| `f2p_3p_unique_only_tiers` | String | `intron` | Feature tiers counted unique-only (their simple multimappers dropped) via diss-tools `--unique-only-categories`. Comma-sep; inert unless the tier is included. |
| `f2p_3p_include_gene_types` | String | `protein_coding,lncRNA` | Gene biotypes retained when building the SAF (comma-sep; requires the full GTF). |
| `f2p_3p_exclude_gene_types` | String | `` (empty) | Gene biotypes excluded when building the SAF (comma-sep; empty = none). |
| `f2p_3p_slop_5p_bp` | Integer | `200` | bp a feature is extended in the 5' direction into the CDS. |
| `f2p_3p_slop_3p_bp` | Integer | `100` | bp a feature is extended downstream past the gene's 3' terminus (3'UTR end for UTR-having genes; terminal-exon end for UTR-less genes). |

---

## Read Counting Parameters (FASTQ2PARQUET_3PRIME)

### Multimapping Strategy

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_3p_count_multimapping_reads` | Boolean | `true` | Include multimapping reads in featureCounts. |
| `f2p_3p_count_overlapping_reads` | Boolean | `true` | Count reads overlapping multiple features. |
| `f2p_3p_count_simple_multimapping_reads` | Boolean | `true` | Count reads multimapping within a single gene. |

Unresolved multi-complex reads are always dropped (no winning gene). Family rescue (`f2p_3p_rescue_gene_family`) is the path to resolve some of those ties before counting.

### Assignment Engine (featureCounts + rank)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_3p_rescue_gene_family` | Boolean | `false` | Enable HGNC gene-family rescue in the rank collapse (needs `f2p_3p_hgnc_gene_groups`). |
| `f2p_3p_hgnc_gene_groups` | Path | `null` | Path to the HGNC gene-groups TSV used for family rescue. |
| `f2p_3p_resolver_metrics` | Boolean | `true` | Emit the assignment-engine all-records aggregate metrics TSV. |

### Full-Annotation Diagnostic (retired)

`f2p_3p_full_annotation_summary` / `f2p_3p_full_annotation_downsample` are **removed**
in 1.10.0. Exact `TotalReadsUnassignedUnselected` / `TotalReadsUnassignedNoOverlap`
come from the primary polony parquet (`IsAnnotated` ∧ ¬`IsAssigned`). Tower
nfparams that still set those keys are ignored (schema no longer lists them).

### Read filter

Optional post-alignment soft-clip filter. BINARY: `APPLY_READ_FILTER` runs only when
`f2p_3p_read_filter_enabled` is set, and then it always enforces (nulls `target_name`
for softclip-failing reads). Disabled (default) ⇒ the step is skipped and the matrix
is unchanged. Soft-clip only — base-quality PF is applied upstream in bases2fastq.
The always-on `read_quality` soft-clip distribution (`ReadQualitySoftclipOver*`) is
emitted regardless. Kept as an extensible home for future post-alignment rules.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_3p_read_filter_enabled` | Boolean | `false` | Run + enforce the soft-clip filter (nulls `target_name` for failing reads). Default off = step skipped, matrix unchanged. |
| `f2p_3p_read_filter_softclip_max` | Integer | `50` | Max `read_min_softclip` (%) allowed to pass the soft-clip rule. |

### Filtered Polonies

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enable_identify_filtered_polonies` | Boolean | `true` | Run IDENTIFY_FILTERED_POLONIES + MERGE_POLONY_PARQUETS. When false, SPLIT still runs on the aligned-only parquet; BUILD never reads the combined well×batch file. |

---

## BUILD_SPATIALDATA (avsd) Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `avsd_zip_spatialdata` | Boolean | `true` | Zip the `.zarr` directory into `.zarr.zip`. When false, only the directory is produced. |
| `avsd_merge_strategy_protein` | String | `expand_features` | Merge strategy for protein assays. |
| `avsd_merge_strategy_transcript` | String | `expand_features` | Merge strategy for transcript assays. |
| `avsd_merge_strategy_ops` | String | `independent_features` | Merge strategy for OPS assays. |
| `avsd_merge_strategy_three_prime_untargeted` | String | `aggregate_features` | Merge strategy for 3' untargeted assays. |
| `avsd_fail_on_missing_batches` | Boolean | `false` | Pass `--fail-on-missing-batches` to `build-spatialdata`. Raise only when a Panel-declared count batch has no points parquets at all. Present-but-unaligned batches are unaffected. Default: warn, record under `uns['missing_batches']`, and continue. |

---

## Fastq2Parquet Shared Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `f2p_batch_size` | Integer | `100000` | Parquet row-group / batch size for processing. |
| `f2p_qc_sample_size` | Integer | `250000` | Number of reads to sample for QC parquet. |
| `f2p_qc_cell_sample_size` | Integer | `500` | Number of cells to sample for QC cell parquet. |

---

## Container Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `elembiodisstools_container_url` | String | `904220683607.dkr.ecr.us-west-2.amazonaws.com/elembio-diss-tools-release` | elembio-diss-tools image repository (see [Container images](../README.md#container-images)). |
| `elembiodisstools_container_tag` | String | `1.0.0` | elembio-diss-tools image tag. |
| `b2f_container_url` | String | `904220683607.dkr.ecr.us-west-2.amazonaws.com/bases2fastq-release` | bases2fastq image repository. |
| `b2f_container_tag` | String | `3.0.0` | bases2fastq image tag. |
| `c2s_container_url` | String | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release` | cells2stats image repository. |
| `c2s_container_tag` | String | `2.0.0` | cells2stats image tag. |
| `spatialdata_build_container_url` | String | `904220683607.dkr.ecr.us-west-2.amazonaws.com/elembio-spatialdata-build-release` | elembio-spatialdata-build image repository. |
| `spatialdata_build_container_tag` | String | `1.0.0` | elembio-spatialdata-build image tag. |
| `spatialdata_analysis_container_url` | String | `''` | Run-quality report image repository (optional; param name retained for a minimal migration diff). Empty in the base config; set it only if you have the report image. |
| `spatialdata_analysis_container_tag` | String | `''` | Run-quality report image tag (optional). `avsd_qc_enabled=true` with either value empty is an error. |

---

## Resource Limits

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_memory` | String | `180.GB` | Maximum memory per process. |
| `max_cpus` | Integer | `48` | Maximum CPUs per process. |
| `max_time` | String | `48.h` | Maximum time per process. |

---

## Publishing Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `publish_dir_mode` | String | `copy` | How to publish output files: `copy`, `symlink`, `move`, etc. |
| `tracedir` | Path | `{outdir}/pipeline_info` | Directory for Nextflow trace/timeline/report files (used with `-with-trace`, `-with-timeline`, `-with-report`). |

