# Azure Data Factory Portfolio Project

## Retail Dynamic CSV Ingestion -- Three Tested Scenarios

**Project:** Retail Sales Dynamic CSV Ingestion\
**Services:** Azure Data Factory, Azure Blob Storage / ADLS Gen2, Azure
SQL Database, Azure Integration Runtime\
**Pipeline:** `PL_Scenario1_Dynamic_Ingestion`\
**Region used in practice:** Central India\
**Status:** Three scenarios tested successfully

------------------------------------------------------------------------

## 1. Business requirement

A retail company uploads multiple CSV files into a source storage
folder. The company wants an automated pipeline that:

1.  Discovers CSV files without hardcoding individual filenames.
2.  Copies new files to a destination folder.
3.  Avoids copying files that have not changed.
4.  Detects modified files and copies the updated content.
5.  Maintains a SQL tracking record for each processed file.
6.  Provides a foundation for deletion handling, error logging, retries,
    monitoring, and scheduled execution.

### Storage layout

``` text
Storage Account
├── source
│   └── csvfiles
│       ├── customer.csv
│       ├── order.csv
│       ├── product.csv
│       └── sales.csv
│
└── destination
    └── csvfiles
        ├── customer.csv
        ├── order.csv
        ├── product.csv
        └── sales.csv
```

The exact files in the source can change over time. The pipeline
discovers them dynamically.

------------------------------------------------------------------------

## 2. Azure services and their responsibilities

  -----------------------------------------------------------------------
  Azure service / component           Responsibility in this project
  ----------------------------------- -----------------------------------
  Azure Data Factory (ADF)            Orchestrates discovery, filtering,
                                      looping, decision-making, copying,
                                      and SQL tracking

  Azure Storage Account               Holds source and destination CSV
                                      files

  Azure SQL Database                  Stores file-processing metadata
  (`RetailTrackingDB`)                

  Azure Integration Runtime           Provides compute/connectivity for
                                      moving data between services

  ADF Linked Services                 Store connection configuration for
                                      Storage and Azure SQL

  ADF Datasets                        Define the source folder,
                                      individual source file, destination
                                      file, and SQL table
  -----------------------------------------------------------------------

### Linked services

-   `LS_ADLS`: connects ADF to the Storage Account.
-   `LS_AzureSQL_Retail`: connects ADF to `RetailTrackingDB`.

### Datasets

-   `DS_Source_Folder`: points to the `source/csvfiles` folder and is
    used to list files.
-   `DS_Source_CSV`: points to a source CSV file. It has the `pFileName`
    parameter.
-   `DS_Destination_CSV`: points to a destination CSV file. It has the
    `pFileName` parameter.
-   `DS_SQL_FileTracking`: points to the SQL tracking table.

The file-level datasets use this dynamic filename expression:

``` text
@dataset().pFileName
```

The Copy activity passes the current filename to both datasets:

``` text
@item().name
```

This means one Copy activity can process many files without creating a
separate activity for every filename.

------------------------------------------------------------------------

## 3. Overall architecture

``` mermaid
flowchart TD
    A["Azure Storage – source/csvfiles"] --> B["Get_Source_Files – Get Metadata"]
    B --> C["Filter_CSV_Files – Filter .csv files"]
    C --> D["ForEach_CSV_Files"]
    D --> E["Get_Source_LastModified"]
    E --> F["Lookup_File_Tracking"]
    F --> G{"ShouldCopy = 1?"}
    G -- Yes --> H["Copy_Each_CSV"]
    H --> I["Update_SQL_File_Tracking"]
    G -- No --> J["Skip unchanged file"]
    H --> K["Azure Storage – destination/csvfiles"]
    I --> L["Azure SQL – dbo.FileTracking"]
```

### Pipeline activity sequence

1.  `Get_Source_Files`
2.  `Filter_CSV_Files`
3.  `ForEach_CSV_Files`
    -   `Get_Source_LastModified`
    -   `Lookup_File_Tracking`
    -   `If_File_Not_Exists`
        -   True branch:
            -   `Copy_Each_CSV`
            -   `Update_SQL_File_Tracking`
        -   False branch:
            -   No copy; file is skipped

**Note:** The If activity name `If_File_Not_Exists` is historical and
now slightly misleading. Its expression checks whether a file needs
copying (new or modified), not only whether it is absent from tracking.
A clearer name would be `If_File_Needs_Copy`.

------------------------------------------------------------------------

## 4. SQL tracking design

### 4.1 Tracking table

Table name: `dbo.FileTracking`

``` sql
CREATE TABLE dbo.FileTracking
(
    FileName NVARCHAR(255) NOT NULL PRIMARY KEY,
    LastModified DATETIME2(7) NOT NULL,
    FileSize BIGINT NULL,
    LastProcessedAt DATETIME2(7) NOT NULL
        DEFAULT SYSUTCDATETIME(),
    Status NVARCHAR(20) NOT NULL
        DEFAULT 'Succeeded'
);
```

  -----------------------------------------------------------------------
  Column                              Meaning
  ----------------------------------- -----------------------------------
  `FileName`                          Source filename; primary key

  `LastModified`                      Last-modified timestamp captured
                                      from the source file

  `FileSize`                          Optional file size; currently
                                      passed as NULL in this practice

  `LastProcessedAt`                   UTC time when the tracking record
                                      was inserted or updated

  `Status`                            Current recorded processing status;
                                      successful copies are recorded as
                                      `Succeeded`
  -----------------------------------------------------------------------

### 4.2 Stored procedure: check whether copying is required

Procedure: `dbo.usp_CheckFileModification`

``` sql
CREATE OR ALTER PROCEDURE dbo.usp_CheckFileModification
    @FileName NVARCHAR(255),
    @CurrentLastModified DATETIME2(7)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FileTracking
        WHERE FileName = @FileName
    )
    BEGIN
        SELECT CAST(1 AS INT) AS ShouldCopy;
        RETURN;
    END;

    SELECT
        CASE
            WHEN LastModified <> @CurrentLastModified THEN 1
            ELSE 0
        END AS ShouldCopy
    FROM dbo.FileTracking
    WHERE FileName = @FileName;
END;
```

The procedure returns one result:

  Situation                                               `ShouldCopy`
  ----------------------------------------------------- --------------
  File does not exist in SQL tracking                                1
  File exists, but its modified timestamp changed                    1
  File exists and its modified timestamp is unchanged                0

### 4.3 Stored procedure: insert or update tracking

Procedure: `dbo.usp_UpsertFileTracking`

``` sql
CREATE OR ALTER PROCEDURE dbo.usp_UpsertFileTracking
    @FileName NVARCHAR(255),
    @LastModified DATETIME2(7),
    @FileSize BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.FileTracking
    SET
        LastModified = @LastModified,
        FileSize = @FileSize,
        LastProcessedAt = SYSUTCDATETIME(),
        Status = 'Succeeded'
    WHERE FileName = @FileName;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.FileTracking
        (
            FileName,
            LastModified,
            FileSize,
            Status
        )
        VALUES
        (
            @FileName,
            @LastModified,
            @FileSize,
            'Succeeded'
        );
    END
END;
```

This is an **upsert** pattern: update an existing row; if no row exists,
insert a new row.

### 4.4 ADF parameter mappings

For `Lookup_File_Tracking`:

  ------------------------------------------------------------------------------------------------
  Stored procedure parameter          ADF value
  ----------------------------------- ------------------------------------------------------------
  `@FileName`                         `@item().name`

  `@CurrentLastModified`              `@activity('Get_Source_LastModified').output.lastModified`
  ------------------------------------------------------------------------------------------------

The Lookup is configured to return the first row. The If Condition
evaluates:

``` text
@equals(activity('Lookup_File_Tracking').output.firstRow.ShouldCopy, 1)
```

For `Update_SQL_File_Tracking`:

  ------------------------------------------------------------------------------------------------
  Stored procedure parameter          ADF value
  ----------------------------------- ------------------------------------------------------------
  `@FileName`                         `@item().name`

  `@LastModified`                     `@activity('Get_Source_LastModified').output.lastModified`

  `@FileSize`                         Treat as null (for the current practice configuration)
  ------------------------------------------------------------------------------------------------

The SQL tracking procedure runs only after the Copy activity succeeds.

------------------------------------------------------------------------

# 5. Scenario 1 -- Initial ingestion of multiple CSV files

## Business problem

The retail company uploads four CSV files for the first time. The
pipeline must discover and copy all CSV files without hardcoding their
names.

### Before execution

Source folder:

``` text
source/csvfiles/
├── customer.csv
├── order.csv
├── product.csv
└── sales.csv
```

SQL tracking table:

``` sql
SELECT * FROM dbo.FileTracking;
```

Expected initial state: zero rows.

## Architecture

``` mermaid
flowchart TD
    A["Source folder – 4 CSV files"] --> B["Get_Source_Files"]
    B --> C["Filter_CSV_Files"]
    C --> D["ForEach_CSV_Files"]
    D --> E["Get_Source_LastModified"]
    E --> F["Lookup_File_Tracking"]
    F --> G["File not in SQL?"]
    G -- Yes --> H["ShouldCopy = 1"]
    H --> I["Copy_Each_CSV"]
    I --> J["Update_SQL_File_Tracking"]
    J --> K["Destination folder"]
    J --> L["4 SQL tracking records"]
```

## Step-by-step execution

### Step 1 -- Get_Source_Files

Activity type: **Get Metadata**

Purpose: List the files available in the source folder.

Field selected:

``` text
childItems
```

Output contains the child items in the folder, including their names and
types.

### Step 2 -- Filter_CSV_Files

Activity type: **Filter**

Items expression:

``` text
@activity('Get_Source_Files').output.childItems
```

Condition:

``` text
@endsWith(item().name, '.csv')
```

Purpose: Keep only CSV files and ignore other file types.

### Step 3 -- ForEach_CSV_Files

Activity type: **ForEach**

Items expression:

``` text
@activity('Filter_CSV_Files').output.value
```

Sequential execution is enabled for this practice pipeline.

Purpose: Process each CSV file one at a time.

### Step 4 -- Get_Source_LastModified

Activity type: **Get Metadata**

Dataset: `DS_Source_CSV`

Filename parameter:

``` text
@item().name
```

Field selected:

``` text
Last modified
```

Purpose: Read the current source file's last-modified timestamp.

### Step 5 -- Lookup_File_Tracking

Activity type: **Lookup**

Stored procedure:

``` text
dbo.usp_CheckFileModification
```

Purpose: Check whether the current filename already exists in SQL
tracking and whether its timestamp changed.

Because the tracking table is initially empty, each file returns:

``` text
ShouldCopy = 1
```

### Step 6 -- If_File_Not_Exists

Activity type: **If Condition**

Expression:

``` text
@equals(activity('Lookup_File_Tracking').output.firstRow.ShouldCopy, 1)
```

The expression evaluates to True for each new file.

### Step 7 -- Copy_Each_CSV

Activity type: **Copy Data**

Source dataset: `DS_Source_CSV`\
Sink dataset: `DS_Destination_CSV`

Both dataset parameters receive:

``` text
@item().name
```

Purpose: Copy the current CSV file while preserving its filename.

The selected Copy behavior is `Flatten hierarchy`.

### Step 8 -- Update_SQL_File_Tracking

Activity type: **Stored Procedure**

Procedure:

``` text
dbo.usp_UpsertFileTracking
```

Dependency: runs after `Copy_Each_CSV` succeeds.

Purpose: Insert the filename, source modified timestamp, and success
status into SQL.

## Actual result observed

  File           Copy result   SQL tracking
  -------------- ------------- --------------
  customer.csv   Copied        Inserted
  order.csv      Copied        Inserted
  product.csv    Copied        Inserted
  sales.csv      Copied        Inserted

**Observed result:** 4 files copied and 4 SQL tracking records created,
all with `Succeeded` status.

------------------------------------------------------------------------

# 6. Scenario 2 -- Prevent duplicate copying of unchanged files

## Business problem

The pipeline runs again, but the four source files have not changed.
Copying all four again wastes processing time and resources.

## Architecture

``` mermaid
flowchart TD
    A["Source folder – 4 CSV files"] --> B["Get Metadata and Filter"]
    B --> C["ForEach"]
    C --> D["Get current LastModified"]
    D --> E["Lookup SQL tracking"]
    E --> F{"Timestamp changed or file new?"}
    F -- No --> G["ShouldCopy = 0"]
    G --> H["Skip file"]
    F -- Yes --> I["Copy and update SQL"]
```

## Step-by-step execution

1.  `Get_Source_Files` lists source folder contents.
2.  `Filter_CSV_Files` keeps only CSV files.
3.  `ForEach_CSV_Files` processes the filtered files.
4.  `Get_Source_LastModified` retrieves the current timestamp.
5.  `Lookup_File_Tracking` calls `dbo.usp_CheckFileModification`.
6.  SQL finds the same filename and same timestamp.
7.  The stored procedure returns `ShouldCopy = 0`.
8.  The If Condition evaluates False.
9.  The Copy activity is not executed.
10. The existing SQL record is left unchanged.

### Example decision

  File           SQL timestamp matches source?     `ShouldCopy` Action
  -------------- ------------------------------- -------------- --------
  customer.csv   Yes                                          0 Skip
  order.csv      Yes                                          0 Skip
  product.csv    Yes                                          0 Skip
  sales.csv      Yes                                          0 Skip

**Observed result:** Debug succeeded and no files were copied.

### Why this is useful

-   Avoids unnecessary file transfers.
-   Reduces repeated processing.
-   Saves time and potentially reduces data movement costs.
-   Makes recurring ingestion more efficient.

------------------------------------------------------------------------

# 7. Scenario 3 -- Modified file, new file, and deleted file

## Business problem

The company makes three changes:

1.  Modifies `customer.csv` but keeps the same filename.
2.  Adds a new CSV file.
3.  Deletes `product.csv` from the source folder.

The pipeline must identify the modified and new files, skip unchanged
files, and not attempt to process the deleted file.

## Source changes made during the test

Before the test, the source had:

``` text
customer.csv
order.csv
product.csv
sales.csv
```

Changes:

-   `customer.csv`: edited and uploaded again with the same filename.
-   New CSV: added to the source folder.
-   `product.csv`: deleted from the source folder.
-   `order.csv` and `sales.csv`: unchanged.

## Architecture

``` mermaid
flowchart TD
    A["Source folder after changes"] --> B["Get_Source_Files"]
    B --> C["Filter_CSV_Files"]
    C --> D["ForEach"]
    D --> E["Get current LastModified"]
    E --> F["Lookup SQL tracking"]
    F --> G{"ShouldCopy?"}
    G -- "1 – Modified or new" --> H["Copy file"]
    H --> I["Upsert SQL tracking"]
    G -- "0 – Unchanged" --> J["Skip file"]
    B --> K["Deleted product.csv is not listed"]
    K --> L["No deletion action in current design"]
```

## Step-by-step execution

### Step 1 -- Discover source files

`Get_Source_Files` lists only files currently available in the source
folder.

Because `product.csv` was deleted, it is no longer returned.

### Step 2 -- Filter CSV files

`Filter_CSV_Files` filters the current source listing to retain `.csv`
files.

### Step 3 -- Process each available file

`ForEach_CSV_Files` processes each file returned by the Filter activity.

### Step 4 -- Check the current modified timestamp

`Get_Source_LastModified` retrieves the timestamp of each current source
file.

### Step 5 -- Compare with SQL tracking

`Lookup_File_Tracking` calls `dbo.usp_CheckFileModification`.

Decisions:

  File           SQL comparison                  Decision
  -------------- ------------------------------- ---------------
  customer.csv   Timestamp changed               Copy
  New CSV        Filename not found in SQL       Copy
  order.csv      Timestamp unchanged             Skip
  sales.csv      Timestamp unchanged             Skip
  product.csv    Not in current source listing   Not processed

### Step 6 -- Copy changed and new files

The If Condition True branch runs `Copy_Each_CSV` for the modified and
new files.

### Step 7 -- Update SQL tracking

After each successful copy, `Update_SQL_File_Tracking` calls
`dbo.usp_UpsertFileTracking`.

-   Existing `customer.csv` record is updated.
-   New CSV receives a new tracking record.
-   Unchanged files are not updated.

## Actual result observed

The Debug run succeeded and produced the expected behavior:

-   Modified customer file copied.
-   New CSV copied.
-   Unchanged order and sales files skipped.
-   Deleted product file was not processed.

### Important limitation -- deletion handling

The current pipeline does not detect or remove deleted files from the
destination.

The `product.csv` record also remains in `dbo.FileTracking`.

This is expected because the pipeline only processes files returned by
the current source folder listing. It does not yet compare the complete
source inventory with SQL tracking.

A future enhancement can mark missing source files as `Deleted` in SQL
and optionally remove them from the destination, depending on the
business requirement.

------------------------------------------------------------------------

# 8. Problems encountered and resolutions

  ----------------------------------------------------------------------------------
  Issue                              Cause / explanation     Resolution
  ---------------------------------- ----------------------- -----------------------
  SQL firewall connection error      Client IP was not       Added the current
                                     allowed by the SQL      client IP to the
                                     Server firewall         firewall rules

  Dynamic filename setup             ADF needed to process   Added `pFileName`
                                     multiple files without  dataset parameters and
                                     hardcoding filenames    passed `@item().name`

  Duplicate copying                  File-existence checks   Added SQL timestamp
                                     alone do not detect     comparison
                                     changed content         

  Nested If / Switch UI issue        The attempted nested    Used one SQL procedure
                                     activities were         to return `ShouldCopy`,
                                     unavailable/greyed out  then one If Condition
                                     in the designer         

  `is not a valid value for Int64`   A blank value was being Selected **Treat as
                                     supplied for the BIGINT null** for `@FileSize`
                                     `@FileSize` parameter   

  Deleted file remains in            Deletion reconciliation Planned as a future
  destination/tracking               is not part of the      enhancement
                                     current pipeline        
  ----------------------------------------------------------------------------------

------------------------------------------------------------------------

# 9. Error handling -- current implementation versus future work

## Implemented now

-   SQL tracking update is connected after Copy success.
-   If Copy fails, the success-dependent SQL update does not run.
-   Unchanged files are skipped.
-   Pipeline failures can be inspected in ADF Monitor.
-   A failed copy does not get recorded as a successful tracking update
    through the current success path.

## Not implemented yet

-   Dedicated SQL error-log table.
-   Failure dependency path and explicit failure logging.
-   Retry configuration and retry testing.
-   Email or other alert notifications.
-   Malformed CSV validation and quarantine.
-   Deleted-file reconciliation.
-   Automated recovery/reprocessing.
-   Detailed run-level audit logging.

**Important:** This project currently has basic success-dependent
tracking, not complete production-grade error handling. The `Status`
column currently records successful processing; it is not yet a complete
failure-status workflow.

------------------------------------------------------------------------

# 10. Testing checklist

  -----------------------------------------------------------------------
  Test                    Expected behavior       Result
  ----------------------- ----------------------- -----------------------
  First run with four CSV Copy all four and       Passed
  files                   insert four tracking    
                          rows                    

  Run again without       Copy zero files         Passed
  source changes                                  

  Modify existing CSV     Copy modified file and  Passed
                          update tracking         

  Add a new CSV           Copy it and insert a    Passed
                          new tracking row        

  Leave other files       Skip unchanged files    Passed
  unchanged                                       

  Delete a source CSV     Do not process it;      Observed as expected
                          destination/tracking    for current design
                          remain for now          
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 11. How to explain the project in an interview

> I developed a dynamic CSV ingestion pipeline using Azure Data Factory,
> Azure Storage, and Azure SQL Database.
>
> The pipeline discovers CSV files dynamically using Get Metadata,
> filters the required files, and processes them through a ForEach
> activity.
>
> I implemented incremental ingestion using a SQL tracking table and
> stored procedures. For each file, the pipeline retrieves the source
> last-modified timestamp and compares it with the timestamp stored in
> SQL.
>
> New and modified files are copied to the destination, while unchanged
> files are skipped. After a successful copy, an upsert stored procedure
> inserts or updates the file tracking record.
>
> I tested initial ingestion, duplicate prevention, modified-file
> detection, and new-file ingestion. Deleted-file reconciliation and
> production-grade error handling are planned enhancements.

------------------------------------------------------------------------

# 12. Next development steps

Recommended order:

1.  **Deleted-file detection:** Compare source filenames with SQL
    tracking and mark missing files as `Deleted`.
2.  **Error logging:** Create a separate SQL error-log table and capture
    failed activity details.
3.  **Retry handling:** Configure and test retry behavior for transient
    failures.
4.  **File validation:** Validate headers, required columns, and file
    format before copying.
5.  **Quarantine:** Move invalid files to a separate rejected-files
    folder.
6.  **Monitoring and alerts:** Add run-level logging and notifications.
7.  **Triggers:** Schedule the pipeline or trigger it based on storage
    events.
8.  **Production hardening:** Review security, secrets, access control,
    concurrency, and cost.

------------------------------------------------------------------------

## Final project summary

**Built and tested:** Dynamic file discovery, parameterized CSV copying,
SQL-based new/modified-file detection, duplicate prevention, and
success-dependent SQL tracking.

**Not yet built:** Deleted-file reconciliation, complete failure
logging, retries, validation, alerting, and triggers.

This distinction is important when presenting the project: describe
completed features as implemented and tested, and describe the remaining
features as planned enhancements.
