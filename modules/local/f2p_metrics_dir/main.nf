process F2P_METRICS_DIR {
    tag "f2p_metrics_dir"
    label 'process_single'

    container "${params.elembiodisstools_container_url}:${params.elembiodisstools_container_tag}"

    input:
    path run_stats_json                             // AGGREGATE_F2P_METRICS.out.run_stats_json
    path genes_gtf_files, stageAs: "genes/gtf/*"    // GTF_PREPROCESSING outputs + log
    path gene_metadata, stageAs: "gene_metadata_in/*" // GENERATE_FEATURE_SAF gene_metadata.tsv (run-level)
    path intervals_metadata, stageAs: "intervals_metadata_in/*" // GENERATE_FEATURE_SAF intervals_metadata.tsv (run-level)

    output:
    path "metrics", emit: metrics_dir

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    set -euo pipefail

    # Curated small-metadata mirror for build-spatialdata --f2p-3p-dir.
    # Same shape as CELLS2STATS / BASES2FASTQ: denylist known-bulk
    # extensions, cap at 100 MB, let build-spatialdata be the final
    # authority. Plus the pipeline-emitted genes/gtf provenance and
    # run-level gene/interval metadata from GENERATE_FEATURE_SAF.
    mkdir -p metrics metrics/genes/gtf

    for f in *; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *.parquet|*.bam|*.bai|*.cram|*.crai|*.sam|*.fastq.gz|*.fq.gz|*.fastq|*.fq) continue ;;
        esac
        size=\$(stat -c%s "\$f" 2>/dev/null || echo 0)
        [ "\$size" -gt 104857600 ] && continue
        ln -sf "../\$f" "metrics/\$f"
    done

    for f in genes/gtf/*; do
        [ -e "\$f" ] && ln -sf "../../../\$f" "metrics/genes/gtf/\$(basename \$f)"
    done

    # Fail-closed: ThreePrime .var is defined by intervals_metadata.selected=1.
    # Soft-skipping here would let BUILD_SPATIALDATA see an f2p_3p_dir without
    # the catalog and either error late or (on older pins) fall back silently.
    shopt -s nullglob
    gene_meta_files=(gene_metadata_in/*)
    intervals_files=(intervals_metadata_in/*)
    if [ \${#gene_meta_files[@]} -ne 1 ] || [ ! -s "\${gene_meta_files[0]}" ]; then
        echo "ERROR: F2P_METRICS_DIR requires a non-empty gene_metadata.tsv from GENERATE_FEATURE_SAF (got: \${gene_meta_files[*]:-none})" >&2
        exit 1
    fi
    if [ \${#intervals_files[@]} -ne 1 ] || [ ! -s "\${intervals_files[0]}" ]; then
        echo "ERROR: F2P_METRICS_DIR requires a non-empty intervals_metadata.tsv from GENERATE_FEATURE_SAF (got: \${intervals_files[*]:-none})" >&2
        exit 1
    fi
    ln -sf "../../\${gene_meta_files[0]}" "metrics/genes/gene_metadata.tsv"
    ln -sf "../../\${intervals_files[0]}" "metrics/genes/intervals_metadata.tsv"
    """

    stub:
    """
    mkdir -p metrics metrics/genes/gtf
    touch metrics/genes/gene_metadata.tsv
    touch metrics/genes/intervals_metadata.tsv
    """
}
