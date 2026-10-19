SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'dbo.DimWorkspace', N'EnvironmentName') IS NULL
    BEGIN
        ALTER TABLE dbo.DimWorkspace
            ADD EnvironmentName nvarchar(50) NOT NULL
                CONSTRAINT DF_DimWorkspace_EnvironmentName DEFAULT (N'Unassigned');
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.key_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.DimWorkspace')
          AND name = N'UQ_DimWorkspace_WorkspaceId'
    )
    BEGIN
        ALTER TABLE dbo.DimWorkspace DROP CONSTRAINT UQ_DimWorkspace_WorkspaceId;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.DimWorkspace')
          AND name = N'UQ_DimWorkspace_Environment_WorkspaceId'
    )
    BEGIN
        CREATE UNIQUE INDEX UQ_DimWorkspace_Environment_WorkspaceId
            ON dbo.DimWorkspace (EnvironmentName, WorkspaceId);
    END;

    IF OBJECT_ID(N'dbo.ModelEnvironmentMapping', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ModelEnvironmentMapping
        (
            EnvironmentName nvarchar(50) NOT NULL,
            WorkspaceId nvarchar(100) NOT NULL,
            DatasetId nvarchar(100) NOT NULL,
            ComparisonModelKey nvarchar(256) NOT NULL,
            CONSTRAINT PK_ModelEnvironmentMapping
                PRIMARY KEY (EnvironmentName, WorkspaceId, DatasetId),
            CONSTRAINT UQ_ModelEnvironmentMapping_Environment_Model
                UNIQUE (EnvironmentName, ComparisonModelKey),
            CONSTRAINT CK_ModelEnvironmentMapping_Values_NotBlank
                CHECK
                (
                    LEN(LTRIM(RTRIM(EnvironmentName))) > 0
                    AND LEN(LTRIM(RTRIM(WorkspaceId))) > 0
                    AND LEN(LTRIM(RTRIM(DatasetId))) > 0
                    AND LEN(LTRIM(RTRIM(ComparisonModelKey))) > 0
                )
        );
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.ModelEnvironmentMapping')
          AND name = N'CK_ModelEnvironmentMapping_Values_NotBlank'
    )
    BEGIN
        ALTER TABLE dbo.ModelEnvironmentMapping
            ADD CONSTRAINT CK_ModelEnvironmentMapping_Values_NotBlank
            CHECK
            (
                LEN(LTRIM(RTRIM(EnvironmentName))) > 0
                AND LEN(LTRIM(RTRIM(WorkspaceId))) > 0
                AND LEN(LTRIM(RTRIM(DatasetId))) > 0
                AND LEN(LTRIM(RTRIM(ComparisonModelKey))) > 0
            );
    END;

    IF OBJECT_ID(N'dbo.ScanRun', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ScanRun
        (
            ScanRunId bigint IDENTITY(1,1) NOT NULL,
            EnvironmentName nvarchar(50) NOT NULL,
            ScanDate date NOT NULL,
            LoadedAtUtc datetime2(0) NOT NULL,
            Payload nvarchar(max) NOT NULL,
            CONSTRAINT PK_ScanRun PRIMARY KEY (ScanRunId),
            CONSTRAINT CK_ScanRun_Payload_IsJson CHECK (ISJSON(Payload) = 1)
        );

        CREATE INDEX IX_ScanRun_Environment_ScanDate
            ON dbo.ScanRun (EnvironmentName, ScanDate, LoadedAtUtc DESC);
    END;

    IF COL_LENGTH(N'dbo.FactDatasetScan', N'ScanRunId') IS NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.FactDatasetScan)
            THROW 50010, 'FactDatasetScan contains rows; migrate existing facts to ScanRun before applying this schema.', 1;

        ALTER TABLE dbo.FactDatasetScan
            ADD ScanRunId bigint NOT NULL;
    END;

    IF COL_LENGTH(N'dbo.FactDatasetScan', N'ComparisonModelKey') IS NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.FactDatasetScan)
            THROW 50011, 'FactDatasetScan contains rows; assign comparison model keys before applying this schema.', 1;

        ALTER TABLE dbo.FactDatasetScan
            ADD ComparisonModelKey nvarchar(256) NOT NULL
                CONSTRAINT DF_FactDatasetScan_ComparisonModelKey DEFAULT (N'Unassigned');
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.key_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.FactDatasetScan')
          AND name = N'UQ_FactDatasetScan_Date_Dataset'
    )
    BEGIN
        ALTER TABLE dbo.FactDatasetScan
            DROP CONSTRAINT UQ_FactDatasetScan_Date_Dataset;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID(N'dbo.FactDatasetScan')
          AND name = N'FK_FactDatasetScan_ScanRun'
    )
    BEGIN
        ALTER TABLE dbo.FactDatasetScan
            ADD CONSTRAINT FK_FactDatasetScan_ScanRun
                FOREIGN KEY (ScanRunId) REFERENCES dbo.ScanRun (ScanRunId);
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.FactDatasetScan')
          AND name = N'UQ_FactDatasetScan_Run_Dataset'
    )
    BEGIN
        CREATE UNIQUE INDEX UQ_FactDatasetScan_Run_Dataset
            ON dbo.FactDatasetScan (ScanRunId, DatasetKey);
    END;

    IF OBJECT_ID(N'dbo.ModelTableSnapshot', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ModelTableSnapshot
        (
            ScanRunId bigint NOT NULL,
            DatasetKey int NOT NULL,
            TableName nvarchar(256) NOT NULL,
            MetadataJson nvarchar(max) NOT NULL,
            CONSTRAINT PK_ModelTableSnapshot
                PRIMARY KEY (ScanRunId, DatasetKey, TableName),
            CONSTRAINT FK_ModelTableSnapshot_FactDatasetScan
                FOREIGN KEY (ScanRunId, DatasetKey)
                REFERENCES dbo.FactDatasetScan (ScanRunId, DatasetKey),
            CONSTRAINT CK_ModelTableSnapshot_Metadata_IsJson
                CHECK (ISJSON(MetadataJson) = 1)
        );
    END;

    IF OBJECT_ID(N'dbo.ModelColumnSnapshot', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ModelColumnSnapshot
        (
            ScanRunId bigint NOT NULL,
            DatasetKey int NOT NULL,
            TableName nvarchar(256) NOT NULL,
            ColumnName nvarchar(256) NOT NULL,
            MetadataJson nvarchar(max) NOT NULL,
            CONSTRAINT PK_ModelColumnSnapshot
                PRIMARY KEY (ScanRunId, DatasetKey, TableName, ColumnName),
            CONSTRAINT FK_ModelColumnSnapshot_FactDatasetScan
                FOREIGN KEY (ScanRunId, DatasetKey)
                REFERENCES dbo.FactDatasetScan (ScanRunId, DatasetKey),
            CONSTRAINT CK_ModelColumnSnapshot_Metadata_IsJson
                CHECK (ISJSON(MetadataJson) = 1)
        );
    END;

    IF OBJECT_ID(N'dbo.ModelMeasureSnapshot', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ModelMeasureSnapshot
        (
            ScanRunId bigint NOT NULL,
            DatasetKey int NOT NULL,
            TableName nvarchar(256) NOT NULL,
            MeasureName nvarchar(256) NOT NULL,
            MetadataJson nvarchar(max) NOT NULL,
            CONSTRAINT PK_ModelMeasureSnapshot
                PRIMARY KEY (ScanRunId, DatasetKey, TableName, MeasureName),
            CONSTRAINT FK_ModelMeasureSnapshot_FactDatasetScan
                FOREIGN KEY (ScanRunId, DatasetKey)
                REFERENCES dbo.FactDatasetScan (ScanRunId, DatasetKey),
            CONSTRAINT CK_ModelMeasureSnapshot_Metadata_IsJson
                CHECK (ISJSON(MetadataJson) = 1)
        );
    END;

    IF OBJECT_ID(N'dbo.ModelExpressionSnapshot', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ModelExpressionSnapshot
        (
            ScanRunId bigint NOT NULL,
            DatasetKey int NOT NULL,
            ExpressionName nvarchar(256) NOT NULL,
            MetadataJson nvarchar(max) NOT NULL,
            CONSTRAINT PK_ModelExpressionSnapshot
                PRIMARY KEY (ScanRunId, DatasetKey, ExpressionName),
            CONSTRAINT FK_ModelExpressionSnapshot_FactDatasetScan
                FOREIGN KEY (ScanRunId, DatasetKey)
                REFERENCES dbo.FactDatasetScan (ScanRunId, DatasetKey),
            CONSTRAINT CK_ModelExpressionSnapshot_Metadata_IsJson
                CHECK (ISJSON(MetadataJson) = 1)
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
