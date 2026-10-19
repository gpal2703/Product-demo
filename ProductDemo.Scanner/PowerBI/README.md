# Power BI Metadata Governance Report

This starter kit builds a Power BI report over the Power BI scanner metadata
already stored in SQLMI. It reports on model structure and DAX definitions; it
does not contain the WBR business data evaluated by those measures.

## SQL views

Run `../Sql/PowerBIReport.Views.sql` in the `pbi_demo` database. It creates:

| View | Purpose |
| --- | --- |
| `dbo.vwPowerBIReportScanHistory` | One row per scan and dataset, for trends and scan history |
| `dbo.vwPowerBIReportLatestScanSummary` | The most recent scan for each environment/model |
| `dbo.vwPowerBIReportLatestModelObject` | Latest tables, columns, measures, and expressions |
| `dbo.vwPowerBIReportLatestMeasureCatalog` | Latest DAX measures, with expression and metadata fields |

The latest-object views retain full metadata JSON for investigation. DAX is
extracted as `nvarchar(max)` so expressions are not limited to 4,000 characters.

## Connect from Power BI Desktop

1. On the Windows laptop, open Power BI Desktop and choose **Get data >
   SQL Server**.
2. Enter server `sqlmi-pbi.public.cedf5cfa0bc5.database.windows.net,3342` and
   database `pbi_demo`.
3. Choose **Import** storage mode and authenticate using the SQLMI-approved
   organizational account/MFA method. Do not save a password in this project.
4. In Navigator, select these views:
   - `dbo.vwPowerBIReportScanHistory` (rename to **Scan History**)
   - `dbo.vwPowerBIReportLatestScanSummary` (rename to **Latest Scan Summary**)
   - `dbo.vwPowerBIReportLatestMeasureCatalog` (rename to **Latest Measure Catalog**)
   - `dbo.vwPowerBIReportLatestModelObject` (rename to **Latest Model Object**)
5. In Model view, create single-direction, one-to-many relationships:
   - `Latest Scan Summary[ScanDatasetKey]` (one) to
     `Latest Measure Catalog[ScanDatasetKey]` (many)
   - `Latest Scan Summary[ScanDatasetKey]` (one) to
     `Latest Model Object[ScanDatasetKey]` (many)
6. Hide technical IDs and raw JSON fields from report view. Keep DAX expressions
   available on the measure catalog detail page.
7. Create a measure table (for example, **Report Measures**) and add the measures
   in `MetadataReport.Measures.dax`.
8. Save the report as a `.pbix` on that laptop.

`ScanDatasetKey` is the relationship key. It identifies a specific scan and
dataset, so the latest inventory relates only to its matching latest summary.
`Scan History` contains prior scans and is intentionally separate, to avoid
ambiguous paths through the latest-snapshot tables.

## Suggested report pages

### Overview

- Cards: **Model Instances (Latest)**, **Tables (Latest)**, **Columns (Latest)**,
  **Measures (Latest)**, **Expressions (Latest)**.
- Slicers: environment and comparison model.
- Table: environment, model, workspace, dataset, scan date, and object counts.
- Line chart: scan date on the axis, table/column/measure counts as values, and
  environment as the legend (use **Scan History**).

### DAX measure catalog

- Slicers: environment, comparison model, table, and display folder.
- Table: table name, measure name, format string, description, hidden status,
  and DAX expression.
- Enable search on the measure and table slicers. Turn on word wrap for DAX and
  use a detail page or tooltip if expressions are too long for a table visual.
- Cards: **Measures with DAX**, **Hidden Measures**, and
  **Measures with Description**.

### Model inventory

- Matrix hierarchy: `MetadataType` > `TableName` > `ObjectName`.
- Add `DataType`, `Description`, `DisplayFolder`, and `IsHidden` as detail
  columns where applicable.
- Use environment/model slicers to scope the inventory.

### Scan history

- Table: scan date/time, environment, model, workspace, dataset, and table,
  column, measure, and expression counts.
- Line chart: counts by scan date, with environment as legend.
- Use **Scan History** for this page; it contains every scan, not just the
  latest one.

## Current data and refresh

The database currently has one Dev scan. The inventory and measure catalog can
be used immediately; history trends need more scans, and a meaningful Dev/Prod
comparison needs a Prod scan. Refresh the imported views after each scanner load.

When publishing to Power BI Service, confirm that the service can reach the
SQLMI endpoint and configure the organization-approved credentials and gateway
if required by your network setup.
