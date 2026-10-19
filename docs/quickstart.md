# Quick Start Guide

This guide gets you from an AVITI run directory to a ready-to-analyze SpatialData Object (SDO) in as few steps as possible. It covers the default human (GRCh38) workflow.

---

## What elembio-multiomics-nf Does

elembio-multiomics-nf takes the output of an AVITI spatial run and produces a single `.zarr` SpatialData Object that links every sequenced RNA read to a physical location on the tissue. Under the hood it runs three things in parallel: it segments cells from the instrument's tile images to establish cell boundaries and XY spatial coordinates, it demultiplexes the raw base calls into per-sample FASTQ files, and it aligns those FASTQs to the human reference genome and assigns each read to a gene and a spatial position. The final step assembles all of that into one SDO. You provide a run directory and a genome; you get back an SDO.

---

## Before You Begin

**You will need:**

- The AVITI run directory (local path or S3 URI). It must contain `RunParameters.json`, `RunManifest.csv`, and `Panel.json`.
- [Nextflow](https://www.nextflow.io/) ≥ 25.04.0 (Java 17 or later). On Nextflow 26.04 or later, run `export NXF_SYNTAX_PARSER=v1` first: the workflow does not yet support the strict syntax parser that 26.04 enables by default.
- Docker, Singularity, or Apptainer

**References come from `--genome`.** `GRCh38` (the default) selects the genome FASTA, a STAR 2.7 index and the GENCODE v47 GTF from the Element reference bucket; no reference parameters are needed. For custom references see [Reference data](../README.md#reference-data). Container images default to the release's validated tags — see [Container images](../README.md#container-images).

---

## Launch Command

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/aviti_run \
    --outdir ./results \
    --genome GRCh38 \
    -profile docker
```

For data stored on S3, replace `--run_dir` with the S3 URI:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir s3://my-bucket/runs/20240101_AV123456_RUN-0001/ \
    --outdir s3://my-bucket/results/20240101_RUN-0001/ \
    --genome GRCh38 \
    -profile docker
```

---

## What Happens Step by Step

| Step | What it does | Runs in parallel with |
|------|---|---|
| **1 — Cell segmentation** | Reads the tile images from the instrument to find cell boundaries, assign XY spatial coordinates to each polony, and build cell segmentation masks | Step 2 |
| **2 — Demultiplexing** | Converts raw base calls into per-sample FASTQ files, one pair (R1/R2) per 3′ expression batch | Step 1 |
| **3 — Alignment & gene assignment** | Aligns each FASTQ to the human genome (GRCh38), assigns reads to genes, and links each read back to its spatial barcode. Runs in parallel across all samples | After step 2 |
| **4 — SDO assembly** | Combines cell coordinates, segmentation, and gene counts into a single SpatialData zarr store | After steps 1 & 3 |

---

## Key Options

Most runs need only `--run_dir` and `--outdir`. The options below cover the cases that commonly come up.

| Option | Default | When to use |
|--------|---------|-------------|
| `--outdir` | `./results` | Change where results are written |
| `--tile` | all tiles | Test on a subset — pass a tile ID as a regex in a params file (see [Usage Guide](usage.md#subset-by-tile)) |
| `--filter_batch` | all batches | Run only specific 3′ batches, e.g. `--filter_batch "B01,B02"` |
| `--segmentation_dir` | auto from run | Supply pre-computed cell segmentation output if cells2stats ran separately |

---

## What You Get

```
results/
├── spatialdata/
│   └── {run_id}.zarr/           ← The SpatialData Object — open this in Python
├── fastq2parquet_3prime/
│   ├── RunStats.json            ← Run-level alignment and assignment statistics
│   └── genes/                   ← GTF + selected interval/gene metadata
└── cells2stats/
    └── RunStats.json            ← Cell segmentation statistics
```

### Opening the SDO in Python

```python
import spatialdata as sd

sdata = sd.read_zarr("results/spatialdata/my_run_id.zarr")
print(sdata)
```

---

## Common Gotchas

- **`Panel.json` is required.** It tells the pipeline which batches contain 3′ expression data vs. imaging or barcoding. The file must be present in the run directory.
- **No `Bkg_RED` / `Bkg_GRN` ImagingTargets with cells2stats ≥1.4.0-rc8.** Panels whose ImagingTargets resolve to those base names (exact or with a measurement suffix such as `_Nuclear`) fail at launch — c2s synthesizes those columns itself. Rename them or pass a corrected file via `--c2s_panel_json`. Per-base names such as `Bkg_RED_A` / `Bkg_GRN_T` are fine.
- **S3 runs require AWS credentials.** Ensure `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION` are set in your environment before launching.
- **Resume a failed run** without restarting from scratch by adding `-resume` to the same command.

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/aviti_run \
    --outdir ./results \
    --genome GRCh38 \
    -profile docker \
    -resume
```

---

## Next Steps

- [Parameters reference](parameters.md) — full list of options
- [Usage guide](usage.md) — tile filtering, batch filtering, AWS Batch, and more
- [Outputs reference](outputs.md) — complete output directory layout
