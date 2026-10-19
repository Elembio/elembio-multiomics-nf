# Usage Guide

This guide provides practical examples for running the elembio-multiomics-nf pipeline.

---

## Prerequisites

### Software Requirements

1. **Nextflow** (>= 24.0.0)
   ```bash
   curl -s https://get.nextflow.io | bash
   # Or via conda
   conda install -c bioconda nextflow
   ```

2. **Container Runtime** (one of):
   - Docker
   - Singularity/Apptainer
   - Podman

### Data Requirements

The pipeline expects an AVITI run directory with the following structure:

```
run_directory/
├── RunParameters.json      # Instrument parameters
├── analysis/
│   └── ...
└── ../
    ├── RunManifest.csv     # Sample manifest
    └── Panel.json          # Assay panel configuration
```

---

## Basic Usage

### Local Run with Docker

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/aviti/run/directory \
    -profile docker
```

### AWS S3 Data

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir s3://bucket/runs/AV123456/20240101_AV123456_RUN-0001/ \
    -profile docker
```

---

## Test Run

Run with a minimal test dataset to verify installation:

```bash
# Clone the repository
git clone https://github.com/Elembio/elembio-multiomics-nf.git
cd elembio-multiomics-nf

# Run test profile
nextflow run . -profile test,docker
```

The test profile:
- Uses a single tile (`L1R01C01S1`) for fast execution
- Uses chromosome 20 only for reduced memory
- Outputs to `results/` directory

---

## Production Runs

### Full Run (All Tiles)

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir s3://bucket/runs/AV123456/20240101_AV123456_RUN-0001/ \
    --genome GRCh38 \
    -profile AVITI24
```

### Subset by Tile

Process only specific tiles (useful for testing or failed tile recovery). The `tile` parameter is a list of regex patterns set via a config file or params file:

```groovy
// In a config file — single tile
params.tile = ["L2R01C01S1"]

// Multiple patterns (e.g., all tiles in a well)
params.tile = ["L.R0[579]C0[24]S.", "L.R1[258]C0[24]S."]
```

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    -params-file params.json \
    -profile docker
```

### Subset by Well

Select all tiles belonging to a well using tile regex patterns (tile-to-well mapping is in `RunParameters.json`):

```groovy
// Example: all tiles in well A1
params.tile = ["L.R0[579]C0[24]S.", "L.R1[258]C0[24]S."]
```

### Subset by Batch

Process only specific batches (experimental batches, not compute batches):

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --filter_batch "B01,B02" \
    -profile docker
```

---

## Custom References

References are selected by `--genome` (default `GRCh38`): the genome FASTA,
a STAR 2.7 index and the GENCODE v47 GTF all come from the same genome entry
under `--igenomes_base`.

To count against a different annotation on the same assembly (for example
another GENCODE release), pass `--genes_gtf` alongside `--genome`:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --genes_gtf /path/to/gencode.v48.annotation.gtf \
    -profile docker
```

To use your own genome, ignore the genome map and supply the FASTA, STAR index
and GTF together; passing `--fasta` or `--star_index` alongside `--genome` is
rejected. The annotation must be GENCODE-format, which in practice means human
or mouse.

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --igenomes_ignore true \
    --fasta /path/to/genome.fa \
    --star_index /path/to/star_index_directory \
    --genes_gtf /path/to/gencode.v47.annotation.gtf \
    -profile docker
```

The STAR index must be built with STAR ≥ 2.7.4a from the same FASTA. The GTF
must be GENCODE-format (`gene` rows with `gene_type`, `UTR`/`exon` features);
annotation-content validation occurs in `GENERATE_FEATURE_SAF`, and NCBI or
Ensembl GTFs fail it. GENCODE human release 47 is validated; other releases from
31 on (consolidated `lncRNA` biotype) are expected to run but are not validated.

---

## Feature Assignment Options

### SAF construction (annotate-then-select)

Counting uses `GENERATE_FEATURE_SAF` with `--annotate-then-select`. Tune the
selected set with `f2p_3p_features` / `f2p_3p_include_gene_types` / slop params
(see [parameters.md](parameters.md)). On-target KPIs are SAF
`(Unique + MultiSimple) / Mapped` — there is no custom targets BED or
`f2p_3p_ontarget_featuretypes` knob anymore (Picard HS retired in 1.10.0).

### Including simple multimapping reads

Same-gene multi-mappers count by default. Unresolved multi-complex reads
(no winning gene) are always dropped. To count simple multi-mappers except on
unique-only tiers:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --f2p_3p_count_simple_multimapping_reads true \
    -profile docker
```

### Adjusting SAF Slop

Change how far SAF annotation intervals extend around selected features:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --f2p_3p_slop_5p_bp 0 \
    --f2p_3p_slop_3p_bp 0 \
    -profile docker
```

---

## Output Customization

### Custom Output Directory

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --outdir /path/to/output \
    -profile docker
```

---

## AWS Batch Execution

### Using Seqera Tower (Platform)

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir s3://bucket/runs/AV123456/run_id/ \
    -profile AVITI24 \
    -with-tower
```

### Manual AWS Batch

Create a custom config:

```groovy
// aws_batch.config
process {
    executor = 'awsbatch'
    queue = 'my-batch-queue'
}

aws {
    region = 'us-west-2'
    batch {
        cliPath = '/home/ec2-user/miniconda/bin/aws'
    }
}
```

Run with custom config:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir s3://bucket/runs/run_id/ \
    -c aws_batch.config \
    -profile docker
```

---

## Resume Failed Runs

Nextflow automatically caches completed tasks. To resume a failed run:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    -profile docker \
    -resume
```

---

## Resource Configuration

### Override Process Resources

Create a custom config file:

```groovy
// custom_resources.config
process {
    withName: 'STAR_ALIGN' {
        cpus = 16
        memory = '64.GB'
        time = '6.h'
    }
    
    withName: 'BAM_TO_PARQUET' {
        cpus = 8
        memory = '32.GB'
    }
}
```

Run with custom resources:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    -c custom_resources.config \
    -profile docker
```

### Global Resource Limits

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --max_memory 128.GB \
    --max_cpus 48 \
    --max_time 72.h \
    -profile docker
```

---

## Module CLI Overrides (`ext.args`)

The `CELLS2STATS`, `BASES2FASTQ`, and `CELLS2STATS_SPATIALDATABUILD_VIZ` modules
follow the **nf-core `task.ext.args` convention** — their CLI flag composition
lives in [`conf/modules.config`](../conf/modules.config) as a `withName:`
closure rather than inside the module's script block. To override or extend a
flag without forking, drop a `-c custom.config` overlay that fully replaces the
`ext.args` closure for that process. Closures are *replaced*, not merged, so the
new closure must emit every flag you want — copy the baseline from
`conf/modules.config` and edit.

Example — add an extra bases2fastq `--settings` override on top of the existing
closure:

```groovy
// custom_b2f.config
process {
    withName: BASES2FASTQ {
        ext.args = {
            def asList = { v -> v instanceof List ? v : (v ? [v] : []) }
            [
                params.b2f_log_level ? "-l ${params.b2f_log_level}" : '-l INFO',
                params.b2f_demux_only ? '--demux-only' : '',
                // ... (copy the rest of the baseline closure from conf/modules.config) ...
                asList(params.b2f_settings).collect { "--settings '${it}'" }.join(' '),
                "--settings 'I1Cycles,8'",     // your extra override
            ].findAll().join(' ')
        }
    }
}
```

Run with:

```bash
nextflow run . --run_dir /path/to/run -c custom_b2f.config -profile docker
```

For most one-off tweaks, however, the **first preference is to set the
underlying parameter** — the baseline closures already read every supported flag
from `params.*`, so e.g. `--b2f_force_detect_index_orientation true` is enough
to emit `--force-detect-index-orientation` without writing a custom config.

> **Deprecated:** `--c2s_args "<extra>"` and `--b2f_args "<extra>"` still work
> (the closures append them verbatim to the CLI) but are scheduled for removal.
> Use the `ext.args` overlay above for anything you would have otherwise put in
> these catch-alls.

---

## Debugging

### View Execution Report

After completion, check pipeline reports in `{outdir}/pipeline_info/`:
- `execution_report.html` - Interactive execution report
- `execution_timeline.html` - Task timeline
- `execution_trace.txt` - Detailed task trace

### Enable Detailed Logging

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    -profile docker \
    -with-report \
    -with-timeline \
    -with-trace \
    -with-dag pipeline_dag.svg
```

### Debug Mode

For troubleshooting, keep work directories:

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    -profile docker \
    -resume \
    --cleanup false
```

---

## Common Issues

### Out of Memory

Increase memory for specific processes:

```groovy
// memory_fix.config
process {
    withName: 'STAR_ALIGN' {
        memory = { 64.GB * task.attempt }
        maxRetries = 3
    }
}
```

### Docker Permission Issues

Ensure Docker has appropriate permissions:

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Or run with sudo
sudo nextflow run Elembio/elembio-multiomics-nf ...
```

### S3 Access Issues

Configure AWS credentials:

```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_DEFAULT_REGION=us-west-2
```

Or use AWS CLI profile:

```bash
aws configure --profile myprofile
export AWS_PROFILE=myprofile
```

---

## Example Workflows

### Complete 3' Spatial Transcriptomics Analysis

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir s3://bucket/runs/AV123456/20240101_AV123456_RUN-0001/ \
    --genome GRCh38 \
    --f2p_3p_count_simple_multimapping_reads true \
    --outdir s3://bucket/results/20240101_RUN-0001/ \
    -profile AVITI24 \
    -with-tower
```

### Quick QC Run (Single Tile)

```groovy
// qc_tile.config
params.tile = ["L2R01C01S1"]
```

```bash
nextflow run Elembio/elembio-multiomics-nf \
    --run_dir /path/to/run \
    --outdir ./qc_test/ \
    -c qc_tile.config \
    -profile docker
```

