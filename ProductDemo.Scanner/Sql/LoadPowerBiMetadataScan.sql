CREATE OR ALTER PROCEDURE dbo.LoadPowerBiMetadataScan
    @Payload nvarchar(max),
    @EnvironmentName nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @EnvironmentName = NULLIF(LTRIM(RTRIM(@EnvironmentName)), N'');

    IF @EnvironmentName IS NULL
        THROW 50001, 'The scan environment is required.', 1;

    IF ISJSON(@Payload) <> 1
        THROW 50002, 'The scan payload must be valid JSON.', 1;

    IF NOT EXISTS (SELECT 1 FROM OPENJSON(@Payload, '$.workspaces'))
        THROW 50003, 'The scan payload must contain at least one workspace.', 1;

    DECLARE @ScanDate date = CONVERT(date, SYSUTCDATETIME());
    DECLARE @LoadedAtUtc datetime2(0) = SYSUTCDATETIME();
    DECLARE @DateKey int = CONVERT(int, CONVERT(char(8), @ScanDate, 112));
    DECLARE @ScanRunId bigint;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT DISTINCT
            JSON_VALUE(workspace.value, '$.id') AS WorkspaceId,
            COALESCE(JSON_VALUE(workspace.value, '$.name'), N'') AS WorkspaceName
        INTO #Workspaces
        FROM OPENJSON(@Payload, '$.workspaces') AS workspace
        WHERE JSON_VALUE(workspace.value, '$.id') IS NOT NULL;

        SELECT
            workspace.WorkspaceId,
            JSON_VALUE(dataset.value, '$.id') AS DatasetId,
            COALESCE(JSON_VALUE(dataset.value, '$.name'), N'') AS DatasetName,
            dataset.value AS DatasetJson,
            mapping.ComparisonModelKey
        INTO #Datasets
        FROM OPENJSON(@Payload, '$.workspaces') AS workspaceJson
        CROSS APPLY
        (
            SELECT JSON_VALUE(workspaceJson.value, '$.id') AS WorkspaceId
        ) AS workspace
        CROSS APPLY OPENJSON(workspaceJson.value, '$.datasets') AS dataset
        LEFT JOIN dbo.ModelEnvironmentMapping AS mapping
            ON mapping.EnvironmentName = @EnvironmentName
           AND mapping.WorkspaceId = workspace.WorkspaceId
           AND mapping.DatasetId = JSON_VALUE(dataset.value, '$.id')
        WHERE workspace.WorkspaceId IS NOT NULL
          AND JSON_VALUE(dataset.value, '$.id') IS NOT NULL;

        IF NOT EXISTS (SELECT 1 FROM #Datasets)
            THROW 50004, 'The scan payload contains no datasets to load.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM #Datasets
            GROUP BY WorkspaceId, DatasetId
            HAVING COUNT_BIG(*) > 1
        )
            THROW 50006, 'The scan payload contains duplicate dataset IDs within a workspace.', 1;

        IF EXISTS (SELECT 1 FROM #Datasets WHERE ComparisonModelKey IS NULL)
            THROW 50005, 'Every scanned workspace and dataset must have a ModelEnvironmentMapping entry for this environment.', 1;

        INSERT dbo.ScanRun (EnvironmentName, ScanDate, LoadedAtUtc, Payload)
        VALUES (@EnvironmentName, @ScanDate, @LoadedAtUtc, @Payload);
        SET @ScanRunId = SCOPE_IDENTITY();

        TRUNCATE TABLE dbo.ScanLanding;
        INSERT dbo.ScanLanding (LandingId, Payload, LoadedAtUtc)
        VALUES (1, @Payload, @LoadedAtUtc);

        IF NOT EXISTS (SELECT 1 FROM dbo.DimDate WHERE DateKey = @DateKey)
            INSERT dbo.DimDate (DateKey, DateValue) VALUES (@DateKey, @ScanDate);

        UPDATE target
        SET WorkspaceName = source.WorkspaceName
        FROM dbo.DimWorkspace AS target
        INNER JOIN #Workspaces AS source
            ON source.WorkspaceId = target.WorkspaceId
        WHERE target.EnvironmentName = @EnvironmentName;

        INSERT dbo.DimWorkspace (WorkspaceId, WorkspaceName, EnvironmentName)
        SELECT source.WorkspaceId, source.WorkspaceName, @EnvironmentName
        FROM #Workspaces AS source
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.DimWorkspace AS target
            WHERE target.EnvironmentName = @EnvironmentName
              AND target.WorkspaceId = source.WorkspaceId
        );

        UPDATE target
        SET DatasetName = source.DatasetName
        FROM dbo.DimDataset AS target
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.WorkspaceKey = target.WorkspaceKey
        INNER JOIN #Datasets AS source
            ON source.WorkspaceId = workspace.WorkspaceId
           AND source.DatasetId = target.DatasetId
        WHERE workspace.EnvironmentName = @EnvironmentName;

        INSERT dbo.DimDataset (DatasetId, WorkspaceKey, DatasetName)
        SELECT source.DatasetId, workspace.WorkspaceKey, source.DatasetName
        FROM #Datasets AS source
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.EnvironmentName = @EnvironmentName
           AND workspace.WorkspaceId = source.WorkspaceId
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.DimDataset AS target
            WHERE target.WorkspaceKey = workspace.WorkspaceKey
              AND target.DatasetId = source.DatasetId
        );

        SELECT
            source.WorkspaceId,
            source.DatasetId,
            source.ComparisonModelKey,
            source.DatasetJson,
            (SELECT COUNT_BIG(*) FROM OPENJSON(source.DatasetJson, '$.tables')) AS TableCount,
            (
                SELECT COUNT_BIG(*)
                FROM OPENJSON(source.DatasetJson, '$.tables') AS modelTable
                CROSS APPLY OPENJSON(modelTable.value, '$.columns') AS modelColumn
            ) AS ColumnCount,
            (
                SELECT COUNT_BIG(*)
                FROM OPENJSON(source.DatasetJson, '$.tables') AS modelTable
                CROSS APPLY OPENJSON(modelTable.value, '$.measures') AS modelMeasure
            ) AS MeasureCount
        INTO #DatasetCounts
        FROM #Datasets AS source;

        INSERT dbo.FactDatasetScan
            (ScanRunId, ComparisonModelKey, DateKey, WorkspaceKey, DatasetKey,
             TableCount, ColumnCount, MeasureCount)
        SELECT
            @ScanRunId,
            counts.ComparisonModelKey,
            @DateKey,
            workspace.WorkspaceKey,
            dataset.DatasetKey,
            counts.TableCount,
            counts.ColumnCount,
            counts.MeasureCount
        FROM #DatasetCounts AS counts
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.EnvironmentName = @EnvironmentName
           AND workspace.WorkspaceId = counts.WorkspaceId
        INNER JOIN dbo.DimDataset AS dataset
            ON dataset.WorkspaceKey = workspace.WorkspaceKey
           AND dataset.DatasetId = counts.DatasetId;

        INSERT dbo.ModelTableSnapshot (ScanRunId, DatasetKey, TableName, MetadataJson)
        SELECT
            @ScanRunId,
            dataset.DatasetKey,
            JSON_VALUE(modelTable.value, '$.name'),
            JSON_MODIFY(
                JSON_MODIFY(modelTable.value, '$.columns', NULL),
                '$.measures',
                NULL)
        FROM #Datasets AS source
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.EnvironmentName = @EnvironmentName
           AND workspace.WorkspaceId = source.WorkspaceId
        INNER JOIN dbo.DimDataset AS dataset
            ON dataset.WorkspaceKey = workspace.WorkspaceKey
           AND dataset.DatasetId = source.DatasetId
        CROSS APPLY OPENJSON(source.DatasetJson, '$.tables') AS modelTable
        WHERE JSON_VALUE(modelTable.value, '$.name') IS NOT NULL;

        INSERT dbo.ModelColumnSnapshot
            (ScanRunId, DatasetKey, TableName, ColumnName, MetadataJson)
        SELECT
            @ScanRunId,
            dataset.DatasetKey,
            JSON_VALUE(modelTable.value, '$.name'),
            JSON_VALUE(modelColumn.value, '$.name'),
            modelColumn.value
        FROM #Datasets AS source
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.EnvironmentName = @EnvironmentName
           AND workspace.WorkspaceId = source.WorkspaceId
        INNER JOIN dbo.DimDataset AS dataset
            ON dataset.WorkspaceKey = workspace.WorkspaceKey
           AND dataset.DatasetId = source.DatasetId
        CROSS APPLY OPENJSON(source.DatasetJson, '$.tables') AS modelTable
        CROSS APPLY OPENJSON(modelTable.value, '$.columns') AS modelColumn
        WHERE JSON_VALUE(modelTable.value, '$.name') IS NOT NULL
          AND JSON_VALUE(modelColumn.value, '$.name') IS NOT NULL;

        INSERT dbo.ModelMeasureSnapshot
            (ScanRunId, DatasetKey, TableName, MeasureName, MetadataJson)
        SELECT
            @ScanRunId,
            dataset.DatasetKey,
            JSON_VALUE(modelTable.value, '$.name'),
            JSON_VALUE(modelMeasure.value, '$.name'),
            modelMeasure.value
        FROM #Datasets AS source
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.EnvironmentName = @EnvironmentName
           AND workspace.WorkspaceId = source.WorkspaceId
        INNER JOIN dbo.DimDataset AS dataset
            ON dataset.WorkspaceKey = workspace.WorkspaceKey
           AND dataset.DatasetId = source.DatasetId
        CROSS APPLY OPENJSON(source.DatasetJson, '$.tables') AS modelTable
        CROSS APPLY OPENJSON(modelTable.value, '$.measures') AS modelMeasure
        WHERE JSON_VALUE(modelTable.value, '$.name') IS NOT NULL
          AND JSON_VALUE(modelMeasure.value, '$.name') IS NOT NULL;

        INSERT dbo.ModelExpressionSnapshot
            (ScanRunId, DatasetKey, ExpressionName, MetadataJson)
        SELECT
            @ScanRunId,
            dataset.DatasetKey,
            JSON_VALUE(modelExpression.value, '$.name'),
            modelExpression.value
        FROM #Datasets AS source
        INNER JOIN dbo.DimWorkspace AS workspace
            ON workspace.EnvironmentName = @EnvironmentName
           AND workspace.WorkspaceId = source.WorkspaceId
        INNER JOIN dbo.DimDataset AS dataset
            ON dataset.WorkspaceKey = workspace.WorkspaceKey
           AND dataset.DatasetId = source.DatasetId
        CROSS APPLY OPENJSON(source.DatasetJson, '$.expressions') AS modelExpression
        WHERE JSON_VALUE(modelExpression.value, '$.name') IS NOT NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
