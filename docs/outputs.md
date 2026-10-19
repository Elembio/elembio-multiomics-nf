# Pipeline Overview & Outputs

---

## What This Pipeline Does

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ELEMBIO-MULTIOMICS-NF WORKFLOW                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐                                                            │
│  │  AVITI Run  │  Raw sequencing data from Element AVITI instrument         │
│  │  Directory  │  (base calls, images, metadata)                            │
│  └──────┬──────┘                                                            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │  CELLS2STATS                                                      │      │
│  │  ─────────────────────────────────────────────────────────────── │      │
│  │  • Process imaging data to identify cell boundaries               │      │
│  │  • Generate cell segmentation masks                               │      │
│  │  • Extract spatial coordinates for each cell (X, Y, Z)            │      │
│  │  • Output: RawCellStats.parquet, Wells/, CellSegmentation/        │      │
│  └───────────────────────────────────────────────────────────────────┘      │
│         │                                                                   │
│         ▼                                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │  BASES2FASTQ                                                      │      │
│  │  ─────────────────────────────────────────────────────────────── │      │
│  │  • Demultiplex raw base calls                                     │      │
│  │  • Generate FASTQ files per sample/well/batch                     │      │
│  │  • Produce QC metrics and reports                                 │      │
│  │  • Output: Sample FASTQs organized by Well/Sample                 │      │
│  └───────────────────────────────────────────────────────────────────┘      │
│         │                                                                   │
│         │  FASTQs are routed by assay type (from Panel.json):               │
│         │  ├── ThreePrimeUntargeted → FASTQ2PARQUET_3PRIME                  │
│         │  ├── SpecializedTargeted  → (future subworkflow)                  │
│         │  ├── TargetedTranscriptomeProfiling → (future subworkflow)        │
│         │  └── Barcoding/Imaging    → not processed                         │
│         │                                                                   │
│         ▼                                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │  FASTQ2PARQUET_3PRIME                                             │      │
│  │  ─────────────────────────────────────────────────────────────── │      │
│  │                                                                   │      │
│  │  1. GTF_PREPROCESSING         → bgzip + tabix-index the GTF      │      │
│  │  2. GENERATE_FEATURE_SAF      → annotate-then-select counting SAF│      │
│  │  3. STAR_ALIGN                → Align reads to reference genome  │      │
│  │  4. TAG_CELL_BAM              → Add cell barcode (CB) tags to BAM│      │
│  │  5. FEATURECOUNTS_BAM         → Assign reads to SAF features     │      │
│  │  6. SAMTOOLS_SORT             → Sort BAM (cell barcode & pos)    │      │
│  │  7. SAMTOOLS_STATS            → BAM alignment statistics         │      │
│  │  8. PICARD_COLLECTRNASEQMETRICS → Strand / 3′ bias (RunStats)    │      │
│  │  9. BAM_TO_PARQUET            → Convert BAM records to parquet   │      │
│  │ 10. CATEGORIZE_READ_ASSIGNMENTS → Classify uniq/multi/counted    │      │
│  │ 11. IDENTIFY_FILTERED_POLONIES  → Anti-join instr vs pipeline    │      │
│  │ 12. MERGE_POLONY_PARQUETS       → Merge aligned + filtered       │      │
│  │ 13. PROCESS_READ_ASSIGNMENTS    → Cell-level counts + QC         │      │
│  │ 14. COLLECT_SAMPLE_METRICS      → Per-sample f2p_metrics.json    │      │
│  │ 15. AGGREGATE_F2P_METRICS       → Run-level RunStats.json        │      │
│  │ 16. F2P_METRICS_DIR             → Curated --f2p-3p-dir mirror    │      │
│  │                                                                   │      │
│  │  (Picard HS, FastQC, and f2p MultiQC retired in 1.10.0)          │      │
│  └───────────────────────────────────────────────────────────────────┘      │
│         │                                                                   │
│         ▼                                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │  BUILD_SPATIALDATA                                                │      │
│  │  ─────────────────────────────────────────────────────────────── │      │
│  │  • Combine spatial coordinates + gene expression parquets         │      │
│  │  • Merge across wells and batches into a single SpatialData store │      │
│  │  • Output: {run_id}.zarr/ or {run_id}.zarr.zip                    │      │
│  └───────────────────────────────────────────────────────────────────┘      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Output Directory Structure

```
{outdir}/
├── cells2stats/
│   ├── RawCellStats.parquet              Per-cell spatial coordinates & metadata
│   ├── RawCellStats.csv                  CSV version of cell stats
│   ├── AverageNormWellStats.csv          Normalized well-level statistics
│   ├── RunStats.json                     Run-level statistics
│   ├── RunParameters.json                Instrument parameters (copy)
│   ├── Panel.json                        Assay panel configuration (copy)
│   ├── RunManifest.{json,csv}            Sample manifest (copy)
│   ├── Versions.json                     cells2stats tool versions
│   ├── multiqc_report.html               Optional cells2stats QC output (when emitted)
│   ├── qc/                               External CP QC (CELLS2STATS_GENERATE_QC_REPORT)
│   │   └── qc_report.html
│   ├── Wells/                            Per-well output directory
│   ├── CellSegmentation/                 Cell segmentation masks
│   ├── AnalysisRegion/                   Per-tile AnalysisRegion mask TIFFs (overlap runs only)
│   ├── Logs/                             Program logs (or Logs.tar.gz)
│   ├── SpatialData/                      c2s spatial data (only if c2s_publish_spatialdata=true)
│   ├── TargetCellAssignmentManifest.*    TCA manifest (SpecializedTargeted only)
│   ├── SpecializedTargetedCounts.json    Target counts (SpecializedTargeted; TargetCounts.json on pre-rc8 c2s)
│   └── visualization.zip                 Visualization data (optional)
│
├── bases2fastq/
│   ├── Samples/
│   │   └── {Well}/
│   │       ├── {Sample}_R1.fastq.gz      Read 1 FASTQ
│   │       ├── {Sample}_R2.fastq.gz      Read 2 FASTQ
│   │       └── {Sample}_stats.json       Per-sample statistics
│   ├── Metrics.csv                       Demux metrics
│   ├── RunStats.json                     Run statistics
│   ├── IndexAssignment.csv               Index assignment summary
│   ├── UnassignedSequences.csv           Unassigned sequence report
│   ├── *_QC.html                         QC report
│   └── info/Bases2Fastq.log              bases2fastq log
│
├── fastq2parquet_3prime/
│   ├── genes/
│   │   ├── gtf/*.gtf.gz{,.tbi}          Compressed & indexed GTF (IGV/tabix)
│   │   ├── intervals_metadata.tsv       Selected/countable ThreePrime catalog (`selected=1`)
│   │   └── gene_metadata.tsv            Per-gene biotype / HGNC / MANE metadata
│   │
│   ├── feature_set/                     IGV SAF ladder beds from GENERATE_FEATURE_SAF
│   │   ├── *.saf.bed{,.gz,.gz.tbi}
│   │   └── *.extensions_for_igv.bed
│   │
│   ├── Samples/{Sample}/
│   │   ├── alignment/
│   │   │   ├── star/                     *.star.bam, *.star.bam.bai
│   │   │   ├── chimera/                  *.star.chimeric.bam{,.bai}
│   │   │   ├── star_log/                 STAR alignment logs (*.out)
│   │   │   ├── star_counts/              STAR gene count tabs
│   │   │   ├── tagged/                   Tag logs
│   │   │   ├── featurecounts/            *.featureCounts.txt.gz, *.summary
│   │   │   ├── cell_sorted/              Cell-barcode-sorted BAM
│   │   │   └── tag_sorted/               Position-sorted BAM + index
│   │   ├── bedgraph/star/                *.bg.gz, *.bg.gz.tbi
│   │   ├── samtools/stats/               *.stats
│   │   ├── samtools/idxstats/            *.idxstats (per-chromosome mapped/unmapped reads)
│   │   ├── samtools/flagstat/            *.flagstat (summary alignment counts)
│   │   ├── picard/rna_metrics/           *.rna_metrics (RNA composition + 3' bias)
│   │   ├── polonies/
│   │   │   ├── reads/                    *_fastqreads.parquet (b2f/aligned, from CATEGORIZE)
│   │   │   │                             *_filteredreads.parquet (filtered only, when enabled)
│   │   │   │                             *_reads.parquet (combined well×batch; merged when IFP on)
│   │   │   ├── {sample_id}_Wells/        Per-tile tree for BUILD_SPATIALDATA (SPLIT)
│   │   │   │                             Well{well}/{batch}/{tile_id}_reads.parquet
│   │   │   ├── qc/                       *.polony-qc_reads.parquet
│   │   │   │                             *.cell-qc_reads.parquet
│   │   │   ├── summary/                  *.basic-metrics.csv.gz
│   │   │   │                             *.gene-names.csv.gz
│   │   │   │                             *.selected-genes.csv.gz
│   │   │   │                             *.cell_read_counts_summary.parquet
│   │   │   │                             *_filteredreads_summary.json (when enabled)
│   │   │   └── logs/                     Per-process log files
│   │   └── metrics/                      *.f2p_metrics.json (per-sample)
│   │
│   ├── RunStats.json                     Run-level aggregated QC statistics
│
├── spatialdata/
│   ├── {run_id}.zarr/                    SpatialData zarr store (default)
│   │   (or {run_id}.zarr.zip)            Zipped if avsd_zip_spatialdata=true
│   ├── cyto.viz                          Packaged cells2stats viz bundle (CELLS2STATS_SPATIALDATABUILD_VIZ; file_version 4.0.0)
│   ├── points-zarr.zip                   Points store for CytoCanvas (CELLS2STATS_SPATIALDATABUILD_VIZ)
│   ├── cell-shapes-zarr.zip              Cell shape store (CELLS2STATS_SPATIALDATABUILD_VIZ)
│   ├── nuclear-shapes-zarr.zip           Nuclear shape store (CELLS2STATS_SPATIALDATABUILD_VIZ)
│   ├── *zarr-index.bin                   ZX02 indexes for points/shapes/images (CELLS2STATS_SPATIALDATABUILD_VIZ)
│   └── logs/                             build-spatialdata / visualize logs
│
└── pipeline_info/
    ├── Provenance.json                   Workflow + container url:tag + resolved params
    ├── software_versions.yml             Aggregated per-tool semver from every module
    ├── execution_trace.txt               Task-level trace
    └── execution_report.html             Interactive execution report
```

---

## Output Details

### cells2stats

| Output | Description |
|--------|-------------|
| `RawCellStats.parquet` | Per-cell table with spatial coordinates (X, Y, Z), barcodes, and metadata. Primary input for downstream read-to-cell assignment. |
| `RunStats.json` | Run-level QC statistics produced by the `cells2stats` tool. Schema is defined by cells2stats (not documented here). This file is also staged into `cyto_dir/` for BUILD_SPATIALDATA. |
| `Wells/` | Per-well subdirectories with well-level outputs. |
| `CellSegmentation/` | Cell boundary masks used by BUILD_SPATIALDATA. |
| `AnalysisRegion/` | Per-tile AnalysisRegion mask TIFFs used by BUILD_SPATIALDATA's overlap stitcher (overlap runs only). |
| `SpatialData/` | c2s-internal Zarr-format spatial data. Not published by default; set `c2s_publish_spatialdata=true` to opt in. The canonical SpatialData store is produced separately by `BUILD_SPATIALDATA` at `spatialdata/{run_id}.zarr`. |
| `Logs/` | Program logs directory (or `Logs.tar.gz` when `c2s_tar_program_logs=true`). |

### bases2fastq

| Output | Description |
|--------|-------------|
| `Samples/{Well}/*.fastq.gz` | Demultiplexed FASTQ files organized by well. R1 and R2 per sample. |
| `Samples/{Well}/*_stats.json` | Per-sample statistics from bases2fastq. |
| `Metrics.csv` | Demultiplexing metrics (reads per sample, index quality). |
| `RunStats.json` | Run-level statistics produced by the `bases2fastq` tool. Schema is defined by bases2fastq (not documented here). |
| `*_QC.html` | Interactive QC report from bases2fastq. |

> **Three `RunStats.json` files:** The pipeline produces three separate `RunStats.json` files,
> each from a different tool with a different schema:
> `cells2stats/RunStats.json` (cell segmentation metrics),
> `bases2fastq/RunStats.json` (demux metrics), and
> `fastq2parquet_3prime/RunStats.json` (alignment/assignment metrics — documented below).

### fastq2parquet_3prime — Alignment & Feature Assignment

| Output | Description |
|--------|-------------|
| `star/*.star.bam` | Genome-aligned BAM from STAR. |
| `featurecounts/*.featureCounts.txt.gz` | Read-to-gene assignment summary from subread featureCounts. |
| `samtools/stats/*.stats` | Alignment statistics (mapped %, duplicates, insert sizes). |
| `samtools/idxstats/*.idxstats` | Per-chromosome mapped/unmapped read counts from the BAM index (one row per reference: `chrom`, `length`, `mapped_reads`, `unmapped_reads`). |
| `samtools/flagstat/*.flagstat` | Summary alignment counts (total/primary/secondary/supplementary/duplicates, mapped %, paired-read breakdowns). Complements `samtools stats`. |
| `picard/rna_metrics/*.rna_metrics` | Picard `CollectRnaSeqMetrics` output — transcript-region composition (`PCT_CODING_BASES`, `PCT_UTR_BASES`, `PCT_INTRONIC_BASES`, `PCT_INTERGENIC_BASES`, `PCT_RIBOSOMAL_BASES`, `PCT_MRNA_BASES`) and 3' bias (`MEDIAN_3PRIME_BIAS`, `MEDIAN_5PRIME_TO_3PRIME_BIAS`), plus a `NORMALIZED_COVERAGE` histogram over normalized gene body position. |

> Picard `CollectHsMetrics` (`picard/hs_metrics*`) and f2p MultiQC were
> retired in 1.10.0. On-target KPIs are SAF `(Unique + MultiSimple) / Mapped`.

### fastq2parquet_3prime — Read Parquets (elembio-diss-tools)

These are the core spatially-resolved gene expression outputs:

| Output | Description |
|--------|-------------|
| `*.raw_reads.parquet` | Raw per-read records extracted from BAM — read ID, cell barcode, gene assignment, alignment quality, spatial coordinates. |
| `reads/*_reads.parquet` | Combined well×batch categorized reads (`IsMappedUnique`, `IsAssigned`, `IsCounted`, …). PROCESS / TAG / metrics still use this file. When IFP is on it is the MERGE of aligned + filtered rows. |
| `{sample_id}_Wells/Well{well}/{batch}/{tile_id}_reads.parquet` | Same rows as the combined file, one parquet per tile. BUILD_SPATIALDATA reads this tree (`is_combined=False`). The `{sample_id}_Wells` prefix avoids Nextflow basename clashes when collecting many samples. |
| `*.polony-qc_reads.parquet` | Subsampled reads for QC visualization. |
| `*.cell-qc_reads.parquet` | Per-cell subsampled reads for QC. |
| `*.basic-metrics.csv.gz` | Summary alignment and assignment metrics per sample. |
| `*.gene-names.csv.gz` | All gene names from the GTF annotation. |
| `*.selected-genes.csv.gz` | Gene names that can collect counts (`protein_coding`/`lncRNA` and selected tiers; `intervals_metadata.selected=1`). Same directory as `gene-names.csv.gz`. |
| `*.cell_read_counts_summary.parquet` | Per-cell count summaries (total reads, counted reads, genes detected). |

### fastq2parquet_3prime — Gene catalog (run-level)

| Output | Description |
|--------|-------------|
| `genes/intervals_metadata.tsv` | Full annotate-then-select interval catalog. Rows with `selected=1` are the authoritative ThreePrime countable gene axis for BUILD_SPATIALDATA. |
| `genes/gene_metadata.tsv` | Per-gene biotype / HGNC / MANE metadata from GENERATE_FEATURE_SAF. |
| `genes/gtf/*.gtf.gz{,.tbi}` | Preprocessed GTF used for annotation / IGV. |

`F2P_METRICS_DIR` stages the same two TSVs into the in-band `--f2p-3p-dir` and **fails the run** if either is missing or empty.

### fastq2parquet_3prime — Metrics (two-stage aggregation)

The pipeline collects QC metrics from multiple tools (STAR, Picard, samtools, elembio-diss-tools)
into structured JSON via a two-stage process:

1. **Stage 1 — Per-sample:** `COLLECT_SAMPLE_METRICS` produces one `*.f2p_metrics.json` per sample
2. **Stage 2 — Run-level:** `AGGREGATE_F2P_METRICS` combines all per-sample JSONs into a single `RunStats.json`

Both stages use the `elembio_diss_rna2counts` CLI from the elembio-diss-tools container.

> **Note:** This `RunStats.json` (under `fastq2parquet_3prime/`) is distinct from the
> `RunStats.json` files produced by cells2stats and bases2fastq. Each tool produces its
> own `RunStats.json` with a different schema in its own output directory.

#### Per-sample metrics (`*.f2p_metrics.json`)

**Location:** `fastq2parquet_3prime/Samples/{Sample}/metrics/{Sample}.f2p_metrics.json`

Each per-sample JSON groups metrics into logical sections. The top-level keys are:

| Key | Type | Description |
|-----|------|-------------|
| `SampleID` | string | Sample identifier (e.g., `A1_B01`) |
| `WellLocation` | string | Well position (e.g., `A1`) |
| `BatchName` | string | Batch name (e.g., `B01`) |
| `AssayType` | string | Assay type from Panel.json (e.g., `ThreePrimeUntargeted`) |
| `Alignment` | object | STAR alignment summary |
| `OnTarget` | object | SAF read-level on-target metrics over mapped reads |
| `Samtools` | object | samtools stats summary |
| `Genes` | object | Gene detection counts |
| `Reads` | object | Read totals and in-cell/out-of-cell breakdown |
| `Mapping` | object | Detailed mapping classification (unique, multi, unmapped) |
| `Assignment` | object | Feature assignment classification (assigned, unassigned, counted) |
| `ReadQC` | object | Read quality breakdown (perfect, softclipped, edits) |
| `CellMetrics` | object | Per-cell density metrics (in-cell and out-of-cell) |
| `FilteredPolonies` | object | Filtered polony counts (only present when `IDENTIFY_FILTERED_POLONIES` ran) |

**`Alignment`** — derived from STAR `Log.final.out`:

| Key | Type | Description |
|-----|------|-------------|
| `TotalReads` | int | Total input reads to STAR |
| `UniquelyMappedReadsPct` | float | Percent of reads uniquely mapped |
| `PctReadsMapped` | float | Percent of reads mapped (unique + multi) |
| `MismatchRatePerBasePct` | float | Mismatch rate per base, percent |
| `AverageMappedLength` | float | Average mapped read length |

**`OnTarget`** — SAF read-level, mapped-denominated (diss-tools `0.35.0`+):

| Key | Type | Description |
|-----|------|-------------|
| `TotalReadsMapped` | int | Mapped-read denominator |
| `PctOnTarget` | float | % of mapped reads that are unique or multi-simple (gene-resolved selected hit). Multi-complex is off-target. |
| `PctOffTargetMapped` | float | `100 - PctOnTarget` |

**`Samtools`** — derived from samtools stats:

| Key | Type | Description |
|-----|------|-------------|
| `RawTotalSequences` | int | Total sequences in the BAM |
| `ReadsMapped` | int | Number of mapped reads |
| `ReadsUnmapped` | int | Number of unmapped reads |
| `ErrorRate` | float | Overall error rate |
| `AverageQuality` | float | Average base quality |
| `PctReadsMapped` | float | Percent of reads mapped |

**`Genes`** — derived from basic-metrics.csv.gz:

| Key | Type | Description |
|-----|------|-------------|
| `TotalGenesInGTF` | int | Total genes in the reference GTF |
| `TotalGenesWithCounts` | int | Genes with at least one counted read |
| `TotalGenesInCell` | int | Genes detected in-cell |
| `TotalGenesOutOfCell` | int | Genes detected out-of-cell |
| `TotalGenesOnlyInCell` | int | Genes detected exclusively in-cell |
| `TotalGenesOnlyOutOfCell` | int | Genes detected exclusively out-of-cell |
| `TotalGenesInAndOut` | int | Genes detected both in-cell and out-of-cell |

**`Reads`** — derived from basic-metrics.csv.gz:

| Key | Type | Description |
|-----|------|-------------|
| `TotalReads` | int | Total reads in the sample |
| `TotalRecords` | int | Total records (reads + supplementary) |
| `TotalReadsInCell` | int | Reads assigned to a cell |
| `TotalReadsOutOfCell` | int | Reads not assigned to any cell |
| `TotalCellsInBAM` | int | Number of distinct cells in the BAM |
| `pct_assigned` | float | Percent of reads assigned to a gene |
| `pct_in_cell` | float | Percent of reads inside a cell boundary |

**`Mapping`** — derived from basic-metrics.csv.gz:

| Key | Type | Description |
|-----|------|-------------|
| `TotalReadsMapped` | int | Total mapped reads |
| `TotalReadsMappedInCell` | int | Mapped reads in-cell |
| `TotalReadsMappedOutOfCell` | int | Mapped reads out-of-cell |
| `TotalReadsMappedUnique` | int | Uniquely mapped reads |
| `TotalReadsMappedUniqueInCell` | int | Uniquely mapped, in-cell |
| `TotalReadsMappedUniqueOutOfCell` | int | Uniquely mapped, out-of-cell |
| `TotalReadsMappedMulti` | int | Multi-mapped reads |
| `TotalReadsMappedMultiInCell` | int | Multi-mapped, in-cell |
| `TotalReadsMappedMultiOutOfCell` | int | Multi-mapped, out-of-cell |
| `TotalReadsUnmapped` | int | Unmapped reads |
| `TotalReadsUnmappedInCell` | int | Unmapped, in-cell |
| `TotalReadsUnmappedOutOfCell` | int | Unmapped, out-of-cell |

**`Assignment`** — derived from basic-metrics.csv.gz:

| Key | Type | Description |
|-----|------|-------------|
| `TotalReadsAssigned` | int | Reads assigned to a feature |
| `TotalReadsAssignedInCell` | int | Assigned, in-cell |
| `TotalReadsAssignedOutOfCell` | int | Assigned, out-of-cell |
| `TotalReadsAssignedUnique` | int | Assigned via unique mapping |
| `TotalReadsAssignedUniqueInCell` | int | Assigned unique, in-cell |
| `TotalReadsAssignedUniqueOutOfCell` | int | Assigned unique, out-of-cell |
| `TotalReadsAssignedMulti` | int | Assigned via multi-mapping |
| `TotalReadsAssignedMultiInCell` | int | Assigned multi, in-cell |
| `TotalReadsAssignedMultiOutOfCell` | int | Assigned multi, out-of-cell |
| `TotalReadsAssignedMultiSimple` | int | Assigned multi-simple (all overlapping same gene) |
| `TotalReadsAssignedMultiSimpleInCell` | int | Assigned multi-simple, in-cell |
| `TotalReadsAssignedMultiSimpleOutOfCell` | int | Assigned multi-simple, out-of-cell |
| `TotalReadsAssignedMultiComplex` | int | Assigned multi-complex (overlapping different genes) |
| `TotalReadsAssignedMultiComplexInCell` | int | Assigned multi-complex, in-cell |
| `TotalReadsAssignedMultiComplexOutOfCell` | int | Assigned multi-complex, out-of-cell |
| `TotalReadsIsCounted` | int | Reads included in final count matrix |
| `TotalReadsIsCountedInCell` | int | Counted, in-cell |
| `TotalReadsIsCountedOutOfCell` | int | Counted, out-of-cell |
| `TotalReadsUnassigned` | int | Reads not assigned to any feature |
| `TotalReadsUnassignedInCell` | int | Unassigned, in-cell |
| `TotalReadsUnassignedOutOfCell` | int | Unassigned, out-of-cell |
| `TotalReadsUnassignedNoFeature` | int | Unassigned — no overlapping feature |
| `TotalReadsUnassignedNoFeatureInCell` | int | Unassigned no-feature, in-cell |
| `TotalReadsUnassignedNoFeatureOutOfCell` | int | Unassigned no-feature, out-of-cell |
| `TotalReadsUnassignedUnmapped` | int | Unassigned — read was unmapped |
| `TotalReadsUnassignedUnmappedInCell` | int | Unassigned unmapped, in-cell |
| `TotalReadsUnassignedUnmappedOutOfCell` | int | Unassigned unmapped, out-of-cell |

**`ReadQC`** — derived from basic-metrics.csv.gz:

| Key | Type | Description |
|-----|------|-------------|
| `TotalReadsMappedPerfect` | int | Mapped with no mismatches |
| `TotalReadsMappedPerfectInCell` | int | Perfect, in-cell |
| `TotalReadsMappedPerfectOutOfCell` | int | Perfect, out-of-cell |
| `TotalReadsMappedPerfectNoSoftclip` | int | Perfect with no softclipping |
| `TotalReadsMappedPerfectNoSoftclipInCell` | int | Perfect no-softclip, in-cell |
| `TotalReadsMappedPerfectNoSoftclipOutOfCell` | int | Perfect no-softclip, out-of-cell |
| `TotalReadsMappedSoftclipped` | int | Mapped with softclipping |
| `TotalReadsMappedSoftclippedInCell` | int | Softclipped, in-cell |
| `TotalReadsMappedSoftclippedOutOfCell` | int | Softclipped, out-of-cell |
| `TotalReadsMappedWithEdits` | int | Mapped with mismatches or indels |
| `TotalReadsMappedWithEditsInCell` | int | With edits, in-cell |
| `TotalReadsMappedWithEditsOutOfCell` | int | With edits, out-of-cell |

**`CellMetrics`** — derived from cell_read_counts_summary.parquet. Contains two sub-objects:

`CellMetrics.InCell`:

| Key | Type | Description |
|-----|------|-------------|
| `CellCounts` | int | Number of cells |
| `TotalAreaUm2` | float | Total cell area in µm² |
| `Reads` | object | `{Counts, CountsPerMm2, CountsPerCell}` — total read counts and densities |
| `IsMapped` | object | `{Counts, CountsPerMm2, CountsPerCell}` — mapped read counts and densities |
| `IsAssigned` | object | `{Counts, CountsPerMm2, CountsPerCell}` — assigned read counts and densities |

`CellMetrics.OutOfCell`:

| Key | Type | Description |
|-----|------|-------------|
| `TotalAreaUm2` | float | Total out-of-cell area in µm² |
| `Reads` | object | `{Counts, CountsPerMm2, CountsPerCell}` — `CountsPerCell` is always `null` |

**`FilteredPolonies`** — derived from `*_filteredreads_summary.json` (only present when
`IDENTIFY_FILTERED_POLONIES` ran for the sample):

| Key | Type | Description |
|-----|------|-------------|
| `TotalInstrumentReads` | int | Total reads reported by the instrument |
| `TotalPipelineReads` | int | Total reads entering the pipeline (after b2f filtering) |
| `TotalFilteredPolonies` | int | Number of filtered polonies recovered |
| `PctFilteredOfInstrument` | float | Percent of instrument reads that were filtered |
| `TotalTiles` | int | Number of tiles processed |

#### Run-level aggregated metrics (`RunStats.json`)

**Location:** `fastq2parquet_3prime/RunStats.json`

Produced by `AGGREGATE_F2P_METRICS`, which combines all per-sample `*.f2p_metrics.json`
files into a single run-level summary. The top-level structure is:

| Key | Type | Description |
|-----|------|-------------|
| `AnalysisID` | string | Deterministic ID: `f2p.<md5>` where the MD5 is computed from the sorted list of input per-sample JSON file paths |
| `AnalysisVersion` | string | `elembio_diss_tools` package version at runtime |
| `FileVersion` | string | Schema version (currently `1.0.0`) |
| `RunID` | string | Run identifier (from `--run-id`) |
| `RunName` | string | From `RunParameters.json` |
| `FlowCellID` | string | From `RunParameters.json` |
| `RunSummary` | object | Aggregated statistics across all samples (see below) |
| `Samples` | array | Array of per-sample objects, each with the same schema as `*.f2p_metrics.json` (see above) |
| `Tools` | object | Container `url:tag` triples for the four pipeline-level containers (cells2stats, bases2fastq, elembio-diss-tools, elembio-spatialdata-build). Copied verbatim from the `.Tools` sub-object of `pipeline_info/Provenance.json` — see "pipeline_info" section below. |

**`RunSummary`** — mean/total statistics computed across all samples:

| Key | Type | Description |
|-----|------|-------------|
| `TotalSamples` | int | Number of samples in the run |
| `TotalReads` | int | Sum of reads across all samples |
| `MeanUniquelyMappedPct` | float | Mean of `Alignment.UniquelyMappedReadsPct` |
| `MeanPctReadsMapped` | float | Mean of `Alignment.PctReadsMapped` |
| `MeanMismatchRatePerBasePct` | float | Mean of `Alignment.MismatchRatePerBasePct` |
| `MeanPctAssigned` | float | Mean of `Reads.pct_assigned` |
| `MeanPctInCell` | float | Mean of `Reads.pct_in_cell` |
| `MeanPctOnTarget` | float | Mean of per-sample `OnTarget.PctOnTarget` (unique + multi-simple / mapped) |
| `MeanPctOffTargetMapped` | float | Mean of `OnTarget.PctOffTargetMapped` (`100 - PctOnTarget`) |
| `MeanSamtoolsErrorRate` | float | Mean of `Samtools.ErrorRate` |
| `MeanSamtoolsAverageQuality` | float | Mean of `Samtools.AverageQuality` |
| `MeanGenesDetected` | float | Mean of `Genes.TotalGenesWithCounts` |
| `MeanGenesInCell` | float | Mean of `Genes.TotalGenesInCell` |
| `MeanCellsPerSample` | float | Mean of `CellMetrics.InCell.CellCounts` |
| `MeanInCellReadsPerMm2` | float | Mean of `CellMetrics.InCell.Reads.CountsPerMm2` |
| `MeanInCellReadsPerCell` | float | Mean of `CellMetrics.InCell.Reads.CountsPerCell` |
| `MeanUniqueGenesPerCell` | float | Mean of `CellMetrics.InCell.UniqueGenes.CountsPerCell` (distinct counted genes / segmented cell, zeros included) |
| `MeanPctFilteredOfInstrument` | float | Mean of `FilteredPolonies.PctFilteredOfInstrument` |
| `TotalFilteredPolonies` | int | Sum of `FilteredPolonies.TotalFilteredPolonies` |

### spatialdata (BUILD_SPATIALDATA) — top-level output

The `spatialdata/` directory is at the top level of the output directory (sibling to `fastq2parquet_3prime/`, `cells2stats/`, `bases2fastq/`).

| Output | Description |
|--------|-------------|
| `{run_id}.zarr/` | [SpatialData](https://spatialdata.scverse.org/) zarr store combining spatial coordinates, cell segmentation, and gene expression across all wells and batches. Default output format. |
| `{run_id}.zarr.zip` | Zipped version (when `avsd_zip_spatialdata=true`). |
| `cyto.viz` | CytoCanvas session manifest (`file_version` `4.0.0`). Produced by CELLS2STATS_SPATIALDATABUILD_VIZ via `cells2stats visualize` (rc12+). |
| `points-zarr.zip` | Points store for CytoCanvas (replaces rc11 `points_global.parquet`). |
| `cell-shapes-zarr.zip` | Cell shape store (replaces rc11 `cell_shapes_global.parquet`). |
| `nuclear-shapes-zarr.zip` | Nuclear shape store (replaces rc11 `nuclear_shapes_global.parquet`). |
| `*zarr-index.bin` | ZX02 indexes: `{run}.points-zarr-index.bin`, `{run}.cell-shapes-zarr-index.bin`, `{run}.nuclear-shapes-zarr-index.bin`, and `{run}.zarr-index.bin` (images subtree). Replaces rc11 `*-index.json.gz`. |

### pipeline_info — workflow-level provenance

Always produced, including runs with no 3′ RNA batches (FASTQ2PARQUET_3PRIME skipped). `Provenance.json` has three top-level sections — `Workflow` (name, version, nextflowVersion, runName, sessionId, commandLine with the `-params-file` value redacted, profile, and commitId/revision when launched from a git source), `Tools` (one `{image, url, tag}` entry per pinned container; entries with an empty url or tag are omitted) and `Params` (the full resolved parameter map as a flat `name: value` object). `software_versions.yml` lists the runtime-reported version of every tool, one entry per module.

| Output | Description |
|--------|-------------|
| `Provenance.json` | Three sections: `Workflow` (manifest, runName, sessionId, commandLine, profile, commitId/revision when launched from a git source), `Tools` (the four pipeline-level container `image / url / tag` triples — cells2stats, bases2fastq, elembio-diss-tools, elembio-spatialdata-build), and `Params` (the full resolved parameter map — a flat `name: value` object including defaults as well as launch overrides; not grouped by schema section). The `.Tools` and `.Params` sub-objects are also embedded into `fastq2parquet_3prime/RunStats.json` for f2p runs. |
| `software_versions.yml` | Aggregated per-tool semver from every module's `versions.yml` (e.g. `cells2stats: 1.4.0-rc10`, STAR/samtools/picard versions parsed at runtime). Complements `Provenance.json` — different provenance axis: what was *inside* each container vs. which image was *pulled*. |
| `execution_trace.txt` | Nextflow task-level execution trace. |
| `execution_report.html` | Interactive Nextflow execution report. |
