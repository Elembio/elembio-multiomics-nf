# Changelog

All notable changes to the public `elembio-multiomics-nf` releases are documented
in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0]

First stable release. No workflow changes since `2.0.0-rc7`.

### Changed
- Container images now have defaults: each release runs the cells2stats,
  bases2fastq, elembio-diss-tools and elembio-spatialdata-build images it was
  validated with, so no container parameters are needed at launch. Any url/tag
  can still be overridden (see [Container images](README.md#container-images)).

## [2.0.0-rc7]

### Changed
- Tools move to their stable releases: cells2stats `2.0.0`, bases2fastq `3.0.0`,
  elembio-diss-tools `1.0.0` and elembio-spatialdata-build `1.0.0`. No workflow
  changes.

## [2.0.0-rc6]

### Changed
- 3' read-to-parquet conversion no longer waits for cell segmentation
  (`cells2stats`) to finish — it now runs in parallel, speeding up runs where
  segmentation is slow (notably single-well runs). Per-cell spatial metrics are
  unchanged; they are still computed later from the authoritative cell-stats table.

## [2.0.0-rc5]

### Changed
- STAR alignment now scales its time limit across retries (3h on the first
  attempt, up to 12h over four attempts) instead of a fixed 2h, so large
  libraries that need longer are retried with more wall-clock rather than
  failing outright.

## [2.0.0-rc3]

### Fixed
- `-profile test` now provisions resources sized for a workstation smoke run, so
  the documented test can run outside the cloud environment.
