//
// BASES2FASTQ: Convert base calls to FASTQ files
//
// This subworkflow handles the conversion of sequencing base calls
// (from Element AVITI instrument) into FASTQ format files.
//

include { BASES2FASTQ } from '../../../modules/elembio/bases2fastq/main'

workflow BASES2FASTQ_SUBWORKFLOW {

    take:
    ch_run_dir              // channel: [ [meta], run_dir ]
    run_manifest_csv        // file: RunManifest.csv
    ch_segmentation         // channel: CellSegmentation/ directory (optional; --segmentation, b2f >= 2.4.0-internal)
    ch_analysis_region      // channel: AnalysisRegion/ directory (optional; --analysis-region, b2f >= 2.4.0-internal)
    ch_panel                // channel: panel JSON (optional)
    ch_tca_manifest         // channel: TargetCellAssignmentManifest CSV (optional)

    main:

    ch_versions = Channel.empty()

    //
    // MODULE: BASES2FASTQ
    // Run bases2fastq to demultiplex and generate FASTQs
    //
    BASES2FASTQ (
        ch_run_dir,
        run_manifest_csv,
        ch_segmentation,
        ch_analysis_region,
        ch_panel,
        ch_tca_manifest
    )
    ch_versions = ch_versions.mix(BASES2FASTQ.out.versions)

    // Derive the bases2fastq output directory from the first FASTQ file
    // Path structure: .../Samples/WellX/sample.fastq.gz -> we need ../.. (bases2fastq root)
    ch_fastq_dir = BASES2FASTQ.out.sample_fastq
        .flatten()
        .first()
        .map { fastq -> fastq.parent.parent.parent.toString() }

    emit:
    sample_fastq     = BASES2FASTQ.out.sample_fastq        // channel: Samples/**.fastq.gz
    sample_fastq_gzi = BASES2FASTQ.out.sample_fastq_gzi   // channel: Samples/**.fastq.gz.gzi (block index)
    fastq_dir        = ch_fastq_dir                        // channel: bases2fastq output directory
    run_stats        = BASES2FASTQ.out.run_stats           // run-level RunStats.json
    b2f_log          = BASES2FASTQ.out.b2f_log             // channel: info/Bases2Fastq.log
    metrics_dir      = BASES2FASTQ.out.metrics_dir         // channel: dir — curated small-metadata (see module)
    versions         = ch_versions                         // channel: versions.yml
}
