# elembio-multiomics-nf

Nextflow workflow for Element Biosciences AVITI24 multiomics secondary analysis — from a raw AVITI24 run directory to a spatially resolved [SpatialData](https://spatialdata.scverse.org/) store combining cytoprofiling, imaging and 3′ untargeted RNA counts.

---

## Quick Start

```bash
# Minimal run (Docker, GRCh38 references from the default bucket, default container images)
nextflow run Elembio/elembio-multiomics-nf -r <version> \
    --run_dir /path/to/aviti/run/directory \
    --outdir ./results \
    -profile AVITI24,docker
```

The only required input is `--run_dir` — an AVITI24 run directory (local or S3) containing `RunParameters.json`, `RunManifest.csv`, and `Panel.json`. References (genome FASTA, STAR index, GENCODE GTF) are selected by `--genome`. `-r <version>` pins a release and is recommended for reproducible results; without it Nextflow runs the latest version. `--outdir` defaults to `./results`.

Each release sets its container images by default — see [Container images](#container-images).

---

## Pipeline Overview

```
AVITI24 Run Directory
        │
        ├──► CELLS2STATS          Cell segmentation, spatial coordinates, QC
        │
        ├──► BASES2FASTQ          Demultiplex base calls → FASTQ per sample/well/batch
        │
        │    FASTQs routed by assay type (from Panel.json):
        │    └── ThreePrimeUntargeted ──►
        │
        ├──► FASTQ2PARQUET_3PRIME
        │    ├── GTF_PREPROCESSING   Annotate + select the countable gene universe
        │    ├── GENERATE_FEATURE_SAF Build the counting SAF from selected features
        │    ├── STAR_ALIGN          Align to reference genome
        │    ├── TAG_CELL_BAM        Add cell barcode tags
        │    ├── FEATURECOUNTS_BAM   Assign reads to genes/features
        │    ├── BAM_TO_PARQUET      Convert BAM → parquet
        │    ├── CATEGORIZE_READ_ASSIGNMENTS  Assign reads to gene/feature tiers
        │    ├── PROCESS_READ_ASSIGNMENTS    Generate cell×gene count matrices
        │    └── COLLECT_SAMPLE_METRICS      Per-sample SAF on-target metrics
        │
        └──► BUILD_SPATIALDATA      Combine spatial + expression into SpatialData (.zarr)
```

---

## Requirements

- **Nextflow** >= 25.04.0 (Java 17+). On Nextflow 26.04 or later, run `export NXF_SYNTAX_PARSER=v1` first: the workflow does not yet support the strict syntax parser that 26.04 enables by default.
- **Docker** or **Singularity/Apptainer**
- Pull access to the container images (see below)

### Reference data

| Input | Requirement |
|-------|-------------|
| Default | `--genome GRCh38` selects the genome FASTA and index files, a STAR index built with STAR 2.7.11b, and the GENCODE v47 GTF from the Element reference bucket (`--igenomes_base`, default `s3://elembio-static-public-244107694630-us-west-2/igenomes`, anonymous read). Point `--igenomes_base` at a mirror of that layout to avoid remote reads. |
| Custom annotation | `--genes_gtf` alongside `--genome` replaces the genome's GENCODE v47 GTF with another GENCODE release on the same assembly. |
| Custom references | `--igenomes_ignore true` with `--fasta`, `--star_index` and `--genes_gtf` together. The STAR index must be built with **STAR ≥ 2.7.4a** from that FASTA, and the annotation must be a **GENCODE**-format GTF, which in practice means human or mouse. Passing `--fasta` or `--star_index` alongside `--genome` is rejected. |

GENCODE human release 47 is the validated annotation. Other GENCODE releases use the same format and are expected to run; release 31 is the minimum, because earlier releases split the `lncRNA` biotype that the default gene filter selects. Counts from other releases are not validated.

Pin one GTF release per analysis: `gene_name` is the count unit and symbols change between releases, so count matrices built against different GTF versions are not directly comparable.

---

## Parameters

### Required

| Parameter | Description |
|-----------|-------------|
| `--run_dir` | Path to the AVITI24 run directory (local or S3). Must contain `RunParameters.json`, `RunManifest.csv`, and `Panel.json`. |
| `--*_container_url` / `--*_container_tag` | The eight container image parameters (no defaults ship). |

### Key Optional

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--id` | Auto-detected | Run identifier. Extracted from `run_dir` path if not provided. |
| `--genome` | `GRCh38` | Reference genome key; selects the FASTA, STAR index and GENCODE GTF. |
| `--outdir` | `./results` | Output directory. |
| `--tile` | `[]` | Tile regex pattern(s) as a list. Restricts processing to matching tiles across b2f, c2s, and build_spatialdata. |
| `--filter_batch` | `null` | Restrict to specific batches, comma-delimited (e.g., `B01,B02`). |

For the full parameter reference — including 3′ feature-tier selection (`--f2p_3p_features`, e.g. add `intron` to count introns; `--f2p_3p_unique_only_tiers` to count chosen tiers unique-only) — see [docs/parameters.md](docs/parameters.md).

---

## Container images

Each release defaults to the image tags it was validated with:

| Tool | Default image |
|------|---------------|
| cells2stats | `904220683607.dkr.ecr.us-west-2.amazonaws.com/cells2stats-release:2.0.0` |
| bases2fastq | `904220683607.dkr.ecr.us-west-2.amazonaws.com/bases2fastq-release:3.0.0` |
| elembio-diss-tools | `904220683607.dkr.ecr.us-west-2.amazonaws.com/elembio-diss-tools-release:1.0.0` |
| elembio-spatialdata-build | `904220683607.dkr.ecr.us-west-2.amazonaws.com/elembio-spatialdata-build-release:1.0.0` |

To use other images, override any of the eight url/tag parameters at launch via `-params-file` (or individually on the command line). A run with any of them unset stops immediately with a message listing them.

```json
{
  "c2s_container_url": "<registry>/cells2stats",
  "c2s_container_tag": "<tag>"
}
```

Docker Hub images must be spelled with the registry (`docker.io/elembio/...`) because the workflow sets `docker.registry = 'quay.io'` for the bare biocontainer names of the public tools (STAR, samtools, featureCounts, Picard, UCSC).

---

## Output Structure

```
{outdir}/
├── cells2stats/                       Cell segmentation, spatial coordinates
│   ├── RawCellStats.parquet
│   ├── Wells/
│   ├── CellSegmentation/
│   └── Logs/
│
├── bases2fastq/                       Demultiplexed FASTQs, run metrics
│   ├── Samples/{Well}/*.fastq.gz
│   ├── Metrics.csv
│   └── RunStats.json
│
├── fastq2parquet_3prime/
│   ├── genes/                         GTF + selected interval/gene metadata
│   ├── Samples/{Sample}/
│   │   ├── alignment/                 STAR BAMs, featureCounts, cell-sorted BAMs
│   │   ├── picard/                    RNA metrics
│   │   ├── polonies/                  combined reads/, per-tile {id}_Wells/, QC & summaries
│   │   └── metrics/                   *.f2p_metrics.json (per-sample)
│   └── RunStats.json                  Run-level aggregated QC statistics
│
├── spatialdata/                       {run_id}.zarr/ (or .zarr.zip)
│
└── pipeline_info/
    ├── Provenance.json                 Workflow + container url:tag + resolved params
    ├── software_versions.yml           Per-tool semver aggregated from every module
    ├── execution_trace.txt
    └── execution_report.html
```

For detailed output descriptions, see [docs/outputs.md](docs/outputs.md).

---

## Documentation

This repository is the source of truth for the workflow's documentation: the full parameter, usage and output references live here and are regenerated into the public repository at each release. The ElemBio online help carries the conceptual and getting-started pages and links here for the references.

| Document | Description |
|----------|-------------|
| [docs/quickstart.md](docs/quickstart.md) | From run directory to SpatialData store in the fewest steps |
| [docs/overview.md](docs/overview.md) | Pipeline architecture, data flow diagram, subworkflow summaries |
| [docs/parameters.md](docs/parameters.md) | Complete parameter reference |
| [docs/usage.md](docs/usage.md) | Practical usage examples and configuration guides |
| [docs/outputs.md](docs/outputs.md) | Output directory structure and file descriptions |
| [CITATIONS.md](CITATIONS.md) | Tools and references to cite |

---

## Configuration Profiles

| Profile | Description |
|---------|-------------|
| `docker` | Run with Docker containers |
| `AVITI24` | Per-process CPU/memory/time allocations for full AVITI24 runs (`AVITI` is an alias) |
| `test` | Smoke run: one tile, chr20 references, and resources sized for them (8 CPU / 28 GB ceiling) |
| `local` | Execute on a single machine: disables `scratch` staging. No resource opinion |

A profile sets either the **scale** of the run or **where** it executes, so the two
compose:

| Invocation | Use |
|---|---|
| `-profile docker,test` | smoke run, any executor |
| `-profile docker,test,local` | smoke run on one machine |
| `-profile docker,AVITI24,local` | full run on one large machine |
| `-profile docker,AVITI24` | full run on a cloud executor (add your own queue config) |

`AVITI24` sets only CPU, memory and time, so it is executor-agnostic — it describes a
full AVITI24 run, not any particular infrastructure. Adjust the `resourceLimits` block
in `conf/test.config` (smoke) or the per-process values in `conf/AVITI24.config` (full
run) for your hardware.

**Always pair `local` with a scale profile.** On its own it sets no resources, so a run
falls back to the generic tiers in `conf/base.config` — `process_high` asks for
12 CPU / 72 GB under a 48 CPU / 180 GB ceiling, which will not fit a workstation. For
your own run directory on one machine, use `-profile docker,AVITI24,local` on hardware
that can meet those allocations, or supply your own resources with `-c my.config`.

Compute queues and cloud settings come from your executor configuration (e.g. a Seqera Platform compute environment or a `-c` overlay). Institutional configs from [Elembio/configs](https://github.com/Elembio/configs) are loaded automatically when `--custom_config_base` is set (the default) and the machine is online.

---

## Authors

- Bryan R. Lajoie
- Carlos Ruiz
- Andrew Altomare

## License

See [LICENSE](LICENSE) file.
