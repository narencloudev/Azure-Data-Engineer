# Azure Data Factory – Incremental File Copy Using Last Modified Date

## 1. Project Overview

### Project Name
Incremental File Copy Using Azure Data Factory (ADF)

### Objective
Build an automated Azure Data Factory pipeline that copies files from a source storage location to a destination storage location based on file existence and modification timestamps.

The pipeline should:

1. Identify files available in the source.
2. Check whether each file exists in the destination.
3. Copy files that are missing.
4. Compare modification dates for existing files.
5. Overwrite destination files when the source file is newer.
6. Skip files when the source file is not newer.

### Real-Time Business Scenario

Imagine an organization receives CSV files every day:

- customers.csv
- sales.csv
- products.csv
- employees.csv

The organization stores the original files in a source folder and maintains a copy in a destination folder.

Instead of copying every file repeatedly, we use Azure Data Factory to check whether files are new or updated.

This reduces unnecessary file transfers.

---

## 2. Architecture

### High-Level Architecture

Source Storage → Azure Data Factory → Destination Storage

ADF contains two pipelines:

1. Parent pipeline: PL_Copy_Missing_Files
2. Child pipeline: PL_Check_Updated_File

### Pipeline Flow

```text
SOURCE STORAGE
      |
      v
GM_Source_Files
      |
      v
FE_Missing_Files
      |
      v
Check Destination File
      |
      v
IF_Destination_Exists
      |
      +-----------------------+
      |                       |
     TRUE                    FALSE
      |                       |
      v                       v
EP_Check_Updated_File    CP_Copy_Missing_File
      |
      v
CHILD PIPELINE
PL_Check_Updated_File
      |
      +--------------------------+
      |                          |
      v                          v
GM_Source_File_Metadata   GM_Destination_File_Metadata
      |                          |
      +------------+-------------+
                   |
                   v
            IF_Source_Is_Newer
                   |
             +-----+-----+
             |           |
            TRUE        FALSE
             |           |
             v           v
       CP_Copy_Updated  SKIP
```

---

## 3. Azure Services Used

| Service | Purpose |
|---|---|
| Azure Data Factory | Pipeline orchestration |
| Azure Storage / ADLS | Source and destination file storage |
| Linked Service | Connect ADF to storage |
| Dataset | Define file location and format |
| Get Metadata | Retrieve file properties |
| ForEach | Process files one by one |
| If Condition | Apply conditional logic |
| Execute Pipeline | Call child pipeline |
| Copy Data | Copy files between storage locations |
| Integration Runtime | Execute data movement |

We used Copy Activity and control-flow activities. We did not need Mapping Data Flow for this project.

---

## 4. Initial Setup – Storage and Datasets

### Step 1: Create Storage Locations

We configured source and destination locations in Azure Storage.

Example:

```text
Source:
container/source/

Destination:
container/destination/
```

The actual storage account and folder paths are configured in the datasets.

**Why?**

We need two locations:
- Source: Original files.
- Destination: Files copied by ADF.

### Step 2: Create Linked Service

A Linked Service establishes the connection between Azure Data Factory and Azure Storage.

Steps:

1. Open Azure Data Factory Studio.
2. Select Manage.
3. Select Linked Services.
4. Click New.
5. Select the appropriate Azure Storage connector.
6. Configure the storage account and authentication.
7. Test the connection.
8. Save.

**Why?**

ADF needs permission to access the storage locations.

### Step 3: Create Source Dataset

Dataset name:

`DS_Source`

Steps:

1. Open Author.
2. Select Datasets.
3. Click New Dataset.
4. Select the storage connector.
5. Select DelimitedText for CSV files.
6. Select the source linked service.
7. Configure the source folder.
8. Configure the file format.

We also configured a dataset parameter:

```text
pFileName
Type: String
```

This allows the same dataset to process multiple files dynamically.

### Step 4: Create Destination Dataset

Dataset name:

`DS_Destination`

Follow the same process, but select the destination storage location.

Create the same parameter:

```text
pFileName
Type: String
```

### Dataset Parameter Expression

The dataset's file name is dynamically supplied using:

```text
@dataset().pFileName
```

**Why parameters?**

Without parameters, we might need separate datasets for customers.csv, sales.csv, products.csv, etc.

With parameters, one dataset can handle multiple files.

---

## 5. Parent Pipeline – PL_Copy_Missing_Files

The parent pipeline manages all source files and decides whether to copy a missing file or call the child pipeline.

### Step 5: Create Parent Pipeline

Pipeline name:

`PL_Copy_Missing_Files`

Steps:

1. Open Author.
2. Click the plus icon.
3. Select Pipeline.
4. Rename the pipeline.
5. Save.

### Step 6: Add Get Metadata – GM_Source_Files

Activity:

`GM_Source_Files`

Purpose:

Retrieve the list of files available in the source folder.

Steps:

1. Drag Get Metadata into the pipeline.
2. Select the source folder dataset.
3. Open Settings.
4. Add the field:

```text
childItems
```

Expected output:

```json
{
  "childItems": [
    {
      "name": "customers.csv",
      "type": "File"
    },
    {
      "name": "sales.csv",
      "type": "File"
    }
  ]
}
```

**Why childItems?**

It returns the list of files and folders inside the specified source folder.

### Step 7: Add ForEach – FE_Missing_Files

Activity:

`FE_Missing_Files`

Purpose:

Process each source file individually.

Steps:

1. Add ForEach after GM_Source_Files.
2. Open Settings.
3. Configure Items using dynamic content:

```text
@activity('GM_Source_Files').output.childItems
```

4. Configure the activities inside the ForEach.

**How it works:**

If the source contains five files, ForEach processes five items.

The current file can be accessed using:

```text
@item().name
```

Example:

```text
Iteration 1: customers.csv
Iteration 2: sales.csv
Iteration 3: products.csv
```

### Step 8: Check Destination File Existence

Inside the ForEach, we configured destination existence checking using Get Metadata.

Important metadata field:

```text
exists
```

The Get Metadata activity checks whether the current source file already exists in the destination.

Example:

```json
{
  "exists": true
}
```

Or:

```json
{
  "exists": false
}
```

**Why?**

We need to identify whether a file is new or already available in the destination.

Important: Selecting `exists` in Get Metadata allows the activity to return false when the file is missing instead of failing because the object does not exist.

### Step 9: Add If Condition – IF_Destination_Exists

Activity:

`IF_Destination_Exists`

Purpose:

Separate existing files from missing files.

Condition:

```text
@activity('GM_Destination_File_Metadata').output.exists
```

Use the actual destination Get Metadata activity name configured in your parent pipeline if it differs.

The logic:

**TRUE branch**

The destination file already exists.

We need to compare modification dates.

**FALSE branch**

The destination file does not exist.

We need to copy it as a new file.

---

## 6. Child Pipeline – PL_Check_Updated_File

The child pipeline is responsible for comparing source and destination file modification dates.

### Step 10: Create Child Pipeline

Pipeline name:

`PL_Check_Updated_File`

Steps:

1. Create a new pipeline.
2. Rename it.
3. Open the Parameters tab.
4. Add a parameter:

```text
Name: pFileName
Type: String
```

**Why?**

The parent pipeline needs to pass the current file name to the child pipeline.

For example:

```text
customers.csv
sales.csv
products.csv
```

### Step 11: Parameterize Source and Destination Datasets

Open `DS_Source`.

Configure its parameter:

```text
pFileName =
@pipeline().parameters.pFileName
```

Repeat for `DS_Destination`.

**Why?**

The child pipeline must check the exact file passed by the parent pipeline.

### Step 12: Add Source Get Metadata

Activity:

`GM_Source_File_Metadata`

Steps:

1. Drag Get Metadata into the child pipeline.
2. Select `DS_Source`.
3. Set the dataset parameter:

```text
pFileName =
@pipeline().parameters.pFileName
```

4. Select the metadata field:

```text
lastModified
```

Purpose:

Retrieve the source file's last modification timestamp.

Example:

```json
{
  "lastModified": "2026-11-12T11:49:23Z"
}
```

### Step 13: Add Destination Get Metadata

Activity:

`GM_Destination_File_Metadata`

Steps:

1. Add another Get Metadata activity.
2. Select `DS_Destination`.
3. Set the same parameter:

```text
pFileName =
@pipeline().parameters.pFileName
```

4. Select:

```text
lastModified
```

Purpose:

Retrieve the destination file's last modification timestamp.

### Step 14: Add If Condition – IF_Source_Is_Newer

Activity:

`IF_Source_Is_Newer`

Purpose:

Compare source and destination modification dates.

Expression:

```text
@greater(
  ticks(activity('GM_Source_File_Metadata').output.lastModified),
  ticks(activity('GM_Destination_File_Metadata').output.lastModified)
)
```

Explanation:

- `activity()` retrieves another activity's output.
- `lastModified` provides the modification timestamp.
- `ticks()` converts the timestamp into a comparable numeric value.
- `greater()` checks whether the first timestamp is greater than the second.

Why use ticks?

It allows us to compare timestamps accurately, rather than comparing date strings.

Logic:

```text
Source > Destination = TRUE

Source <= Destination = FALSE
```

---

## 7. Configure the Updated File Copy

### Step 15: Connect the If Condition

Connect the successful completion of `GM_Destination_File_Metadata` to `IF_Source_Is_Newer`.

Inside the If Condition:

TRUE branch → Copy updated file.

FALSE branch → Leave empty.

### Step 16: Add Copy Data

Activity:

`CP_Copy_Updated_File`

Add this activity inside the TRUE branch.

Configure Source:

```text
Dataset: DS_Source

pFileName:
@pipeline().parameters.pFileName
```

Configure Sink:

```text
Dataset: DS_Destination

pFileName:
@pipeline().parameters.pFileName
```

Configure the sink copy behavior to overwrite the existing destination file.

**Why overwrite?**

The destination already contains an older version. We need to replace it with the newer source file.

### Step 17: Validate and Save Child Pipeline

1. Check the True branch contains CP_Copy_Updated_File.
2. Check the False branch is empty.
3. Return to the child pipeline canvas.
4. Click Validate.
5. Save the pipeline.

Expected child pipeline:

```text
GM_Source_File_Metadata
          |
GM_Destination_File_Metadata
          |
IF_Source_Is_Newer
          |
     TRUE branch
          |
CP_Copy_Updated_File

     FALSE branch
          |
         Skip
```

---

## 8. Connect Parent and Child Pipelines

### Step 18: Add Execute Pipeline

Return to:

`PL_Copy_Missing_Files`

Open:

`FE_Missing_Files`

Open:

`IF_Destination_Exists`

Inside the TRUE branch, add Execute Pipeline.

Activity name:

`EP_Check_Updated_File`

Configure Settings:

```text
Invoked Pipeline:
PL_Check_Updated_File

Wait on completion:
Enabled
```

Configure the parameter:

```text
pFileName =
@item().name
```

**Why Execute Pipeline?**

It allows the parent pipeline to call the child pipeline and pass the current file name.

Example:

```text
Parent:
sales.csv

Child:
PL_Check_Updated_File

Parameter:
pFileName = sales.csv
```

The child pipeline now knows which file it must compare.

### Step 19: Add Copy Data for Missing Files

Open:

`IF_Destination_Exists`

Inside the FALSE branch, add Copy Data.

Activity name:

`CP_Copy_Missing_File`

Configure Source:

```text
Dataset: DS_Source

pFileName:
@item().name
```

Configure Sink:

```text
Dataset: DS_Destination

pFileName:
@item().name
```

Keep the same destination file name.

**Why?**

When a file is missing in the destination, we don't need to compare timestamps.

We can directly copy it.

### Step 20: Remove Old Standalone Copy Activity

We checked the ForEach canvas for the original standalone Copy activity outside the If Condition.

The old standalone Copy activity was removed so that files would not be copied unconditionally.

We retained the new Copy activity inside the FALSE branch.

This ensures that copying happens only when required.

---

## 9. Validate and Publish

### Step 21: Validate Parent Pipeline

Return to:

`PL_Copy_Missing_Files`

Click Validate.

Expected result:

```text
Validation succeeded.
No errors found.
```

### Step 22: Save Parent Pipeline

Click Save.

### Step 23: Publish

Click:

```text
Publish all
```

Wait for:

```text
Publish succeeded
```

Difference:

| Save | Publish |
|---|---|
| Saves authoring changes | Deploys changes |
| Used while developing | Used to run the latest published version |

---

## 10. Execute the Pipeline

### Step 24: Trigger Now

1. Open `PL_Copy_Missing_Files`.
2. Click Add trigger.
3. Select Trigger now.
4. Review parameters if displayed.
5. Click OK.

### Step 25: Monitor Pipeline Runs

1. Open Monitor.
2. Select Pipeline runs.
3. Find the latest run.
4. Check the status.
5. Open the pipeline run to see activity details.

We received:

```text
Status: Succeeded
```

This confirmed that the parent pipeline execution completed successfully.

---

## 11. Real-Time Testing Performed

### Test 1: Existing File Updated

We modified `customer.csv` in the source by adding one column.

Then we triggered the pipeline.

Expected execution:

```text
IF_Destination_Exists = TRUE

EP_Check_Updated_File

GM_Source_File_Metadata

GM_Destination_File_Metadata

IF_Source_Is_Newer = TRUE

CP_Copy_Updated_File
```

Observed result:

The new column was reflected in the destination file.

**Conclusion:** The updated-file copy scenario worked.

### Test 2: Unchanged File

We ran the pipeline again without modifying the source file.

We checked the child pipeline activity runs.

The following activities showed success:

```text
GM_Source_File_Metadata

GM_Destination_File_Metadata

IF_Source_Is_Newer
```

We also found `CP_Copy_Updated_File` with Succeeded status in the activity runs.

Important:

This test is not yet conclusively verified as a skip scenario. We still need to compare source and destination `lastModified` values and confirm the actual condition result.

### Test 3: Missing File

Expected test:

1. Add a new CSV file to the source.
2. Do not create the same file in the destination.
3. Trigger the pipeline.
4. Check IF_Destination_Exists.
5. Confirm the FALSE branch executes CP_Copy_Missing_File.
6. Verify the file exists in the destination.

This scenario should be verified separately if it has not already been tested with a newly introduced file.

---

## 12. Important Dynamic Expressions

| Purpose | Expression |
|---|---|
| Get source file list | `@activity('GM_Source_Files').output.childItems` |
| Get current file name | `@item().name` |
| Access pipeline parameter | `@pipeline().parameters.pFileName` |
| Access dataset parameter | `@dataset().pFileName` |
| Check destination existence | `@activity('GM_Destination_File_Metadata').output.exists` |
| Get source modification date | `@activity('GM_Source_File_Metadata').output.lastModified` |
| Get destination modification date | `@activity('GM_Destination_File_Metadata').output.lastModified` |
| Compare timestamps | `@greater(ticks(activity('GM_Source_File_Metadata').output.lastModified),ticks(activity('GM_Destination_File_Metadata').output.lastModified))` |

Note: Activity names in expressions must exactly match the names in the pipeline where the expression is configured.

---

## 13. Common Problems and Troubleshooting

### Problem 1: Cannot find If Condition

Solution:

- Open the Activities pane.
- Search for If Condition.
- If the activity list is filtered or collapsed, expand the relevant category.

### Problem 2: Cannot navigate through the provided data source

Possible areas to check:

- Linked Service connection.
- Dataset file path.
- Storage permissions.
- Dataset parameter values.

Verify the source and destination datasets independently.

### Problem 3: Copy Activity runs unnecessarily

Cause:

An old standalone Copy activity may still exist outside the If Condition.

Solution:

Keep the Copy activity inside the correct branch and remove unintended standalone activities.

### Problem 4: Existing destination file must be overwritten

Solution:

Check the Copy activity Sink settings and configure overwrite behavior.

### Problem 5: Pipeline succeeded but Copy activity did not run

Explanation:

An If Condition can succeed even when its True or False branch contains no activity to execute.

Always inspect the branch result and activity runs.

### Problem 6: Get Metadata output shows {}

Check:

- Whether you opened Input or Output.
- Whether you selected the correct activity.
- Whether you opened the correct child pipeline run.

The actual Get Metadata output should contain the requested metadata fields.

---

## 14. How to Monitor the Project

Go to:

```text
Azure Data Factory
      |
      v
Monitor
      |
      v
Pipeline Runs
      |
      v
Select Pipeline Run
      |
      v
Activity Runs
      |
      v
Inspect Input / Output
```

Important details to monitor:

- Pipeline status.
- Activity status.
- Source file name.
- Destination file name.
- Last modified timestamps.
- Copy activity rows/files read and written, where available.
- Execution duration.
- Integration Runtime.
- Billing reference.

---

## 15. Cost Considerations

We used:

- Get Metadata activities.
- ForEach.
- If Condition.
- Execute Pipeline.
- Copy Data.
- Azure Integration Runtime.

We did not use Mapping Data Flow.

Why avoid Data Flow here?

This project only requires metadata checking and file copying. A Mapping Data Flow would add unnecessary transformation compute for this requirement.

Important cost points:

1. Copy activity has data movement charges based on the applicable Integration Runtime and usage.
2. Pipeline orchestration and activity executions can incur charges.
3. Storage transactions and storage capacity can also incur charges.
4. Free-tier eligibility and quotas depend on the subscription and service.

Always check Azure Cost Management for actual charges.

---

## 16. Final Expected Business Logic

| Scenario | Destination exists? | Source newer? | Action |
|---|---|---|---|
| New file | No | Not required | Copy |
| Updated file | Yes | Yes | Overwrite |
| Unchanged file | Yes | No | Skip |
| Older source file | Yes | No | Skip |

### What We Built

We created a reusable file-level incremental copy pipeline using Azure Data Factory.

The parent pipeline identifies files and checks their existence.

The child pipeline compares modification dates and copies only newer files.

This architecture avoids copying existing files unnecessarily.

---

## 17. What I Learned from This Project

| Concept | What I learned |
|---|---|
| Linked Service | How ADF connects to storage |
| Dataset | How to define source and destination files |
| Dataset Parameters | How to reuse datasets |
| Pipeline Parameters | How to pass file names |
| Get Metadata | How to retrieve file properties |
| childItems | How to retrieve files from a folder |
| exists | How to check file existence |
| lastModified | How to retrieve modification timestamps |
| ForEach | How to process multiple files |
| If Condition | How to implement conditional logic |
| Execute Pipeline | How to call a child pipeline |
| Copy Activity | How to copy and overwrite files |
| Dynamic Content | How to use expressions |
| Integration Runtime | How ADF executes data movement |
| Monitor | How to troubleshoot pipeline execution |

---

## 18. Interview Explanation

**Question: Explain your Azure Data Factory project.**

Answer:

I developed an incremental file-copying solution using Azure Data Factory.

The requirement was to copy files from source storage to destination storage without unnecessarily copying all files on every execution.

I created a parent pipeline called `PL_Copy_Missing_Files` and a child pipeline called `PL_Check_Updated_File`.

The parent pipeline uses Get Metadata to retrieve source file information and ForEach to process each file.

I used an If Condition to check whether the destination file exists.

If the destination file does not exist, Copy Activity copies the file directly.

If the destination file already exists, Execute Pipeline calls the child pipeline and passes the file name as a parameter.

The child pipeline uses Get Metadata to retrieve the last modified timestamps of both files.

I compare those timestamps using the greater and ticks functions.

If the source file is newer, Copy Activity overwrites the destination file. Otherwise, the file is skipped.

Finally, I validated, published, triggered and monitored the pipeline through Azure Data Factory Monitor.

---

## 19. Future Enhancements

These are possible improvements, not features implemented in this project:

- Add logging for copied and skipped files.
- Add error handling and retry logic.
- Send failure notifications.
- Add file extension filtering.
- Add archive handling.
- Add checksum comparison for content-level verification.
- Add scheduled triggers.
- Add support for nested folders.
- Add a separate audit table for file processing history.

---

## 20. Microsoft Learn References

Official documentation:

1. [Azure Data Factory – Get Metadata Activity](https://learn.microsoft.com/en-us/azure/data-factory/control-flow-get-metadata-activity)

2. [Azure Data Factory – ForEach Activity](https://learn.microsoft.com/en-us/azure/data-factory/control-flow-for-each-activity)

3. [Azure Data Factory – If Condition Activity](https://learn.microsoft.com/en-us/azure/data-factory/control-flow-if-condition-activity)

4. [Azure Data Factory – Execute Pipeline Activity](https://learn.microsoft.com/en-us/azure/data-factory/control-flow-execute-pipeline-activity)

5. [Azure Data Factory – Copy Activity](https://learn.microsoft.com/en-us/azure/data-factory/copy-activity-overview)

6. [Azure Data Factory – Expressions and Functions](https://learn.microsoft.com/en-us/azure/data-factory/control-flow-expression-language-functions)

7. [Azure Data Factory – Parameters and Variables](https://learn.microsoft.com/en-us/azure/data-factory/concepts-parameters-variables)

8. [Azure Data Factory – Monitor Pipeline Runs](https://learn.microsoft.com/en-us/azure/data-factory/monitor-visually)

---

## 21. Project Completion Checklist

- [x] Source and destination datasets configured
- [x] Parent pipeline created
- [x] Source file metadata configured
- [x] ForEach configured
- [x] Destination existence logic configured
- [x] Child pipeline created
- [x] Pipeline parameter configured
- [x] Source modification metadata configured
- [x] Destination modification metadata configured
- [x] Date comparison configured
- [x] Updated-file Copy activity configured
- [x] Execute Pipeline configured
- [x] Missing-file Copy activity configured
- [x] Old standalone Copy activity removed
- [x] Parent pipeline validated
- [x] Child pipeline validated
- [x] Changes published
- [x] Main pipeline triggered successfully
- [x] Updated customer.csv reflected in destination
- [ ] Unchanged-file skip behavior verified
- [ ] Missing-file scenario independently verified

**Final Status:** Core pipeline built, published and successfully executed. Two test cases remain to be conclusively verified.
