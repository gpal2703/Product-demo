-- Keep these mappings aligned with the workspace and dataset IDs in each environment.
BEGIN TRANSACTION;

IF EXISTS
(
    SELECT 1 FROM dbo.ModelEnvironmentMapping
    WHERE EnvironmentName = N'Dev'
      AND WorkspaceId = N'9c6e9213-3e19-4d3d-a33a-4f1e9ad76758'
      AND DatasetId = N'690d225c-3f7d-49b1-8466-b74e24e0c6cf'
)
    UPDATE dbo.ModelEnvironmentMapping
    SET ComparisonModelKey = N'Lumina_WBR'
    WHERE EnvironmentName = N'Dev'
      AND WorkspaceId = N'9c6e9213-3e19-4d3d-a33a-4f1e9ad76758'
      AND DatasetId = N'690d225c-3f7d-49b1-8466-b74e24e0c6cf';
ELSE
    INSERT dbo.ModelEnvironmentMapping
        (EnvironmentName, WorkspaceId, DatasetId, ComparisonModelKey)
    VALUES
        (N'Dev', N'9c6e9213-3e19-4d3d-a33a-4f1e9ad76758',
         N'690d225c-3f7d-49b1-8466-b74e24e0c6cf', N'Lumina_WBR');

IF EXISTS
(
    SELECT 1 FROM dbo.ModelEnvironmentMapping
    WHERE EnvironmentName = N'Prod'
      AND WorkspaceId = N'beacb2dd-51db-4aa0-9a06-1f0eea1ced09'
      AND DatasetId = N'91e47f4a-c7d1-4999-be14-880227d96d23'
)
    UPDATE dbo.ModelEnvironmentMapping
    SET ComparisonModelKey = N'Lumina_WBR'
    WHERE EnvironmentName = N'Prod'
      AND WorkspaceId = N'beacb2dd-51db-4aa0-9a06-1f0eea1ced09'
      AND DatasetId = N'91e47f4a-c7d1-4999-be14-880227d96d23';
ELSE
    INSERT dbo.ModelEnvironmentMapping
        (EnvironmentName, WorkspaceId, DatasetId, ComparisonModelKey)
    VALUES
        (N'Prod', N'beacb2dd-51db-4aa0-9a06-1f0eea1ced09',
         N'91e47f4a-c7d1-4999-be14-880227d96d23', N'Lumina_WBR');

COMMIT TRANSACTION;

SELECT TOP (10) * FROM dbo.ScanRun ORDER BY ScanRunId DESC;
SELECT TOP (10) * FROM dbo.DimWorkspace ORDER BY EnvironmentName, WorkspaceName;
SELECT TOP (10) * FROM dbo.DimDataset ORDER BY DatasetName;
SELECT TOP (10) * FROM dbo.FactDatasetScan ORDER BY ScanRunId DESC;
SELECT TOP (10) * FROM dbo.vwModelMetadataSnapshot
ORDER BY ScanDate DESC, ComparisonModelKey, EnvironmentName, MetadataType, TableName, ObjectName;
SELECT TOP (10) * FROM dbo.ModelEnvironmentMapping
ORDER BY EnvironmentName, ComparisonModelKey;

-- Compare the latest scan from each environment for the selected UTC date.
-- Set @ScanDate to a date present in both environments.
DECLARE @ScanDate date = CONVERT(date, SYSUTCDATETIME());

WITH RankedRuns AS
(
    SELECT
        run.ScanRunId,
        run.EnvironmentName,
        run.ScanDate,
        fact.ComparisonModelKey,
        ROW_NUMBER() OVER
        (
            PARTITION BY run.EnvironmentName, fact.ComparisonModelKey, run.ScanDate
            ORDER BY run.LoadedAtUtc DESC, run.ScanRunId DESC
        ) AS RunRank
    FROM dbo.ScanRun AS run
    INNER JOIN dbo.FactDatasetScan AS fact ON fact.ScanRunId = run.ScanRunId
    WHERE run.ScanDate = @ScanDate
),
DevSnapshot AS
(
    SELECT metadata.*
    FROM RankedRuns AS run
    INNER JOIN dbo.vwModelMetadataSnapshot AS metadata
        ON metadata.ScanRunId = run.ScanRunId
       AND metadata.EnvironmentName = run.EnvironmentName
       AND metadata.ComparisonModelKey = run.ComparisonModelKey
    WHERE run.EnvironmentName = N'Dev'
      AND run.RunRank = 1
),
ProdSnapshot AS
(
    SELECT metadata.*
    FROM RankedRuns AS run
    INNER JOIN dbo.vwModelMetadataSnapshot AS metadata
        ON metadata.ScanRunId = run.ScanRunId
       AND metadata.EnvironmentName = run.EnvironmentName
       AND metadata.ComparisonModelKey = run.ComparisonModelKey
    WHERE run.EnvironmentName = N'Prod'
      AND run.RunRank = 1
)
SELECT
    COALESCE(dev.ComparisonModelKey, prod.ComparisonModelKey) AS ComparisonModelKey,
    COALESCE(dev.MetadataType, prod.MetadataType) AS MetadataType,
    COALESCE(dev.TableName, prod.TableName) AS TableName,
    COALESCE(dev.ObjectName, prod.ObjectName) AS ObjectName,
    CASE
        WHEN dev.ScanRunId IS NULL THEN N'Only in Prod'
        WHEN prod.ScanRunId IS NULL THEN N'Only in Dev'
        WHEN dev.MetadataJson <> prod.MetadataJson THEN N'Different'
        ELSE N'Same'
    END AS ComparisonResult,
    dev.MetadataJson AS DevMetadata,
    prod.MetadataJson AS ProdMetadata
FROM DevSnapshot AS dev
FULL OUTER JOIN ProdSnapshot AS prod
    ON prod.ComparisonModelKey = dev.ComparisonModelKey
   AND prod.MetadataType = dev.MetadataType
   AND ISNULL(prod.TableName, N'') = ISNULL(dev.TableName, N'')
   AND prod.ObjectName = dev.ObjectName
ORDER BY ComparisonModelKey, MetadataType, TableName, ObjectName;