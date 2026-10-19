CREATE OR ALTER VIEW dbo.vwModelMetadataSnapshot
AS
WITH ModelRuns AS
(
    SELECT
        run.ScanRunId,
        run.EnvironmentName,
        run.ScanDate,
        fact.ComparisonModelKey,
        fact.DatasetKey
    FROM dbo.ScanRun AS run
    INNER JOIN dbo.FactDatasetScan AS fact ON fact.ScanRunId = run.ScanRunId
)
SELECT
    run.EnvironmentName,
    run.ComparisonModelKey,
    run.ScanRunId,
    run.ScanDate,
    N'Table' AS MetadataType,
    CAST(NULL AS nvarchar(256)) AS TableName,
    snapshot.TableName AS ObjectName,
    snapshot.MetadataJson
FROM ModelRuns AS run
INNER JOIN dbo.ModelTableSnapshot AS snapshot
    ON snapshot.ScanRunId = run.ScanRunId
   AND snapshot.DatasetKey = run.DatasetKey
UNION ALL
SELECT
    run.EnvironmentName,
    run.ComparisonModelKey,
    run.ScanRunId,
    run.ScanDate,
    N'Column',
    snapshot.TableName,
    snapshot.ColumnName,
    snapshot.MetadataJson
FROM ModelRuns AS run
INNER JOIN dbo.ModelColumnSnapshot AS snapshot
    ON snapshot.ScanRunId = run.ScanRunId
   AND snapshot.DatasetKey = run.DatasetKey
UNION ALL
SELECT
    run.EnvironmentName,
    run.ComparisonModelKey,
    run.ScanRunId,
    run.ScanDate,
    N'Measure',
    snapshot.TableName,
    snapshot.MeasureName,
    snapshot.MetadataJson
FROM ModelRuns AS run
INNER JOIN dbo.ModelMeasureSnapshot AS snapshot
    ON snapshot.ScanRunId = run.ScanRunId
   AND snapshot.DatasetKey = run.DatasetKey
UNION ALL
SELECT
    run.EnvironmentName,
    run.ComparisonModelKey,
    run.ScanRunId,
    run.ScanDate,
    N'Expression',
    CAST(NULL AS nvarchar(256)),
    snapshot.ExpressionName,
    snapshot.MetadataJson
FROM ModelRuns AS run
INNER JOIN dbo.ModelExpressionSnapshot AS snapshot
    ON snapshot.ScanRunId = run.ScanRunId
   AND snapshot.DatasetKey = run.DatasetKey;
GO

CREATE OR ALTER VIEW dbo.vwLatestModelTableSnapshot
AS
WITH RankedRuns AS
(
    SELECT
        run.ScanRunId,
        run.EnvironmentName,
        run.ScanDate,
        fact.ComparisonModelKey,
        fact.DatasetKey,
        ROW_NUMBER() OVER
        (
            PARTITION BY run.EnvironmentName, fact.ComparisonModelKey
            ORDER BY run.LoadedAtUtc DESC, run.ScanRunId DESC
        ) AS RunRank
    FROM dbo.ScanRun AS run
    INNER JOIN dbo.FactDatasetScan AS fact ON fact.ScanRunId = run.ScanRunId
)
SELECT
    ranked.EnvironmentName,
    ranked.ComparisonModelKey,
    ranked.ScanRunId,
    ranked.ScanDate,
    snapshot.TableName,
    snapshot.MetadataJson
FROM RankedRuns AS ranked
INNER JOIN dbo.ModelTableSnapshot AS snapshot
    ON snapshot.ScanRunId = ranked.ScanRunId
   AND snapshot.DatasetKey = ranked.DatasetKey
WHERE ranked.RunRank = 1;
GO

CREATE OR ALTER VIEW dbo.vwLatestModelColumnSnapshot
AS
WITH RankedRuns AS
(
    SELECT
        run.ScanRunId,
        run.EnvironmentName,
        run.ScanDate,
        fact.ComparisonModelKey,
        fact.DatasetKey,
        ROW_NUMBER() OVER
        (
            PARTITION BY run.EnvironmentName, fact.ComparisonModelKey
            ORDER BY run.LoadedAtUtc DESC, run.ScanRunId DESC
        ) AS RunRank
    FROM dbo.ScanRun AS run
    INNER JOIN dbo.FactDatasetScan AS fact ON fact.ScanRunId = run.ScanRunId
)
SELECT
    ranked.EnvironmentName,
    ranked.ComparisonModelKey,
    ranked.ScanRunId,
    ranked.ScanDate,
    snapshot.TableName,
    snapshot.ColumnName,
    snapshot.MetadataJson
FROM RankedRuns AS ranked
INNER JOIN dbo.ModelColumnSnapshot AS snapshot
    ON snapshot.ScanRunId = ranked.ScanRunId
   AND snapshot.DatasetKey = ranked.DatasetKey
WHERE ranked.RunRank = 1;
GO

CREATE OR ALTER VIEW dbo.vwLatestModelMeasureSnapshot
AS
WITH RankedRuns AS
(
    SELECT
        run.ScanRunId,
        run.EnvironmentName,
        run.ScanDate,
        fact.ComparisonModelKey,
        fact.DatasetKey,
        ROW_NUMBER() OVER
        (
            PARTITION BY run.EnvironmentName, fact.ComparisonModelKey
            ORDER BY run.LoadedAtUtc DESC, run.ScanRunId DESC
        ) AS RunRank
    FROM dbo.ScanRun AS run
    INNER JOIN dbo.FactDatasetScan AS fact ON fact.ScanRunId = run.ScanRunId
)
SELECT
    ranked.EnvironmentName,
    ranked.ComparisonModelKey,
    ranked.ScanRunId,
    ranked.ScanDate,
    snapshot.TableName,
    snapshot.MeasureName,
    snapshot.MetadataJson
FROM RankedRuns AS ranked
INNER JOIN dbo.ModelMeasureSnapshot AS snapshot
    ON snapshot.ScanRunId = ranked.ScanRunId
   AND snapshot.DatasetKey = ranked.DatasetKey
WHERE ranked.RunRank = 1;
GO

CREATE OR ALTER VIEW dbo.vwLatestModelExpressionSnapshot
AS
WITH RankedRuns AS
(
    SELECT
        run.ScanRunId,
        run.EnvironmentName,
        run.ScanDate,
        fact.ComparisonModelKey,
        fact.DatasetKey,
        ROW_NUMBER() OVER
        (
            PARTITION BY run.EnvironmentName, fact.ComparisonModelKey
            ORDER BY run.LoadedAtUtc DESC, run.ScanRunId DESC
        ) AS RunRank
    FROM dbo.ScanRun AS run
    INNER JOIN dbo.FactDatasetScan AS fact ON fact.ScanRunId = run.ScanRunId
)
SELECT
    ranked.EnvironmentName,
    ranked.ComparisonModelKey,
    ranked.ScanRunId,
    ranked.ScanDate,
    snapshot.ExpressionName,
    snapshot.MetadataJson
FROM RankedRuns AS ranked
INNER JOIN dbo.ModelExpressionSnapshot AS snapshot
    ON snapshot.ScanRunId = ranked.ScanRunId
   AND snapshot.DatasetKey = ranked.DatasetKey
WHERE ranked.RunRank = 1;
GO
