CREATE OR ALTER VIEW dbo.vwPowerBIReportScanHistory
AS
SELECT
    CONCAT(CONVERT(varchar(20), fact.ScanRunId), ':',
           CONVERT(varchar(20), fact.DatasetKey)) AS ScanDatasetKey,
    fact.ScanRunId,
    run.EnvironmentName,
    run.ScanDate,
    run.LoadedAtUtc,
    fact.ComparisonModelKey,
    workspace.WorkspaceId,
    workspace.WorkspaceName,
    dataset.DatasetId,
    dataset.DatasetName,
    fact.TableCount,
    fact.ColumnCount,
    fact.MeasureCount,
    expressionCounts.ExpressionCount
FROM dbo.FactDatasetScan AS fact
INNER JOIN dbo.ScanRun AS run
    ON run.ScanRunId = fact.ScanRunId
INNER JOIN dbo.DimWorkspace AS workspace
    ON workspace.WorkspaceKey = fact.WorkspaceKey
INNER JOIN dbo.DimDataset AS dataset
    ON dataset.DatasetKey = fact.DatasetKey
OUTER APPLY
(
    SELECT COUNT_BIG(*) AS ExpressionCount
    FROM dbo.ModelExpressionSnapshot AS expression
    WHERE expression.ScanRunId = fact.ScanRunId
      AND expression.DatasetKey = fact.DatasetKey
) AS expressionCounts;
GO

CREATE OR ALTER VIEW dbo.vwPowerBIReportLatestScanSummary
AS
WITH RankedScans AS
(
    SELECT
        history.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY history.EnvironmentName, history.ComparisonModelKey
            ORDER BY history.LoadedAtUtc DESC, history.ScanRunId DESC
        ) AS ModelScanRank
    FROM dbo.vwPowerBIReportScanHistory AS history
)
SELECT
    ScanDatasetKey,
    ScanRunId,
    EnvironmentName,
    ScanDate,
    LoadedAtUtc,
    ComparisonModelKey,
    WorkspaceId,
    WorkspaceName,
    DatasetId,
    DatasetName,
    TableCount,
    ColumnCount,
    MeasureCount,
    ExpressionCount
FROM RankedScans
WHERE ModelScanRank = 1;
GO

CREATE OR ALTER VIEW dbo.vwPowerBIReportLatestModelObject
AS
WITH RankedModelScans AS
(
    SELECT
        fact.ScanRunId,
        fact.DatasetKey,
        fact.ComparisonModelKey,
        run.EnvironmentName,
        run.ScanDate,
        run.LoadedAtUtc,
        ROW_NUMBER() OVER
        (
            PARTITION BY run.EnvironmentName, fact.ComparisonModelKey
            ORDER BY run.LoadedAtUtc DESC, fact.ScanRunId DESC
        ) AS ModelScanRank
    FROM dbo.FactDatasetScan AS fact
    INNER JOIN dbo.ScanRun AS run
        ON run.ScanRunId = fact.ScanRunId
)
SELECT
    CONCAT(CONVERT(varchar(20), ranked.ScanRunId), ':',
           CONVERT(varchar(20), ranked.DatasetKey)) AS ScanDatasetKey,
    ranked.ScanRunId,
    ranked.EnvironmentName,
    ranked.ScanDate,
    ranked.LoadedAtUtc,
    ranked.ComparisonModelKey,
    metadata.MetadataType,
    metadata.TableName,
    metadata.ObjectName,
    properties.DaxExpression,
    properties.FormatString,
    properties.Description,
    properties.DisplayFolder,
    properties.DataType,
    properties.IsHidden,
    metadata.MetadataJson
FROM RankedModelScans AS ranked
INNER JOIN dbo.vwModelMetadataSnapshot AS metadata
    ON metadata.ScanRunId = ranked.ScanRunId
   AND metadata.EnvironmentName = ranked.EnvironmentName
   AND metadata.ComparisonModelKey = ranked.ComparisonModelKey
OUTER APPLY OPENJSON(metadata.MetadataJson)
WITH
(
    DaxExpression nvarchar(max) '$.expression',
    FormatString nvarchar(4000) '$.formatString',
    Description nvarchar(4000) '$.description',
    DisplayFolder nvarchar(4000) '$.displayFolder',
    DataType nvarchar(100) '$.dataType',
    IsHidden bit '$.isHidden'
) AS properties
WHERE ranked.ModelScanRank = 1;
GO

CREATE OR ALTER VIEW dbo.vwPowerBIReportLatestMeasureCatalog
AS
SELECT
    ScanDatasetKey,
    ScanRunId,
    EnvironmentName,
    ScanDate,
    LoadedAtUtc,
    ComparisonModelKey,
    TableName,
    ObjectName AS MeasureName,
    DaxExpression,
    FormatString,
    Description,
    DisplayFolder,
    DataType,
    IsHidden
FROM dbo.vwPowerBIReportLatestModelObject
WHERE MetadataType = N'Measure';
GO
