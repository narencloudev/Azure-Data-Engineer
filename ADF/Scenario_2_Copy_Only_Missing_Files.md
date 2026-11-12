# Azure Data Factory -- Scenario 2: Copy Only Missing Files

> **Learning level:** Beginner\
> **Service:** Azure Data Factory (ADF)\
> **Storage:** Azure Data Lake Storage Gen2 (ADLS Gen2)\
> **Main activities:** Get Metadata, Filter, ForEach, Copy Data

------------------------------------------------------------------------

## 1. Real-world scenario

Imagine you are a Junior Azure Data Engineer working for an e-commerce
company.

The company receives files in a **Source** folder. Some files have
already been copied to a **Destination** folder.

Your manager asks:

> Copy only the files that exist in the Source folder but are missing
> from the Destination folder. Do not copy files that already exist.

This requirement is called **copying only missing files**.

### Why is this needed?

-   Avoid copying the same files repeatedly.
-   Reduce unnecessary data movement.
-   Save processing time.
-   Avoid unnecessary Copy Activity executions and associated costs.

------------------------------------------------------------------------

## 2. Example

### Source folder

  File name
  ---------------
  customers.csv
  sales.csv
  products.csv
  orders.csv

### Destination folder

  File name
  ---------------
  customers.csv
  sales.csv

The destination already contains `customers.csv` and `sales.csv`.

Therefore, the pipeline should copy only:

-   `products.csv`
-   `orders.csv`

After the pipeline completes, the destination should contain all four
files.

------------------------------------------------------------------------

## 3. High-level architecture

``` text
                 SOURCE FOLDER
       customers.csv, sales.csv,
       products.csv, orders.csv
                      |
                      v
             Get Metadata - Source
               (Child items)
                      |
                      |
               DESTINATION FOLDER
                 customers.csv
                   sales.csv
                      |
                      v
          Get Metadata - Destination
                (Child items)
                      |
                      v
               Filter Activity
       Keep source files not in destination
                      |
                      v
                ForEach Activity
             Process each missing file
                      |
                      v
                 Copy Activity
                      |
                      v
              DESTINATION FOLDER
  customers.csv, sales.csv, products.csv,
                  orders.csv
```

------------------------------------------------------------------------

## 4. Activities used

  -----------------------------------------------------------------------
  Activity                            Purpose in this scenario
  ----------------------------------- -----------------------------------
  Get Metadata -- Source              Gets the list of files in the
                                      source folder.

  Get Metadata -- Destination         Gets the list of files already
                                      present in the destination folder.

  Filter                              Keeps only source files that are
                                      missing from the destination.

  ForEach                             Loops through the filtered list of
                                      missing files.

  Copy Data                           Copies each missing file to the
                                      destination.
  -----------------------------------------------------------------------

### 4.1 Get Metadata -- Source

**What is it?**\
Get Metadata retrieves information about a file or folder.

**Why do we use it here?**\
We need to know which files are available in the source folder.

For a folder, select the **Child items** field. It returns the items
inside that folder.

Example output:

``` json
[
  {"name": "customers.csv", "type": "File"},
  {"name": "sales.csv", "type": "File"},
  {"name": "products.csv", "type": "File"},
  {"name": "orders.csv", "type": "File"}
]
```

### 4.2 Get Metadata -- Destination

Use another Get Metadata activity to inspect the destination folder.

Select **Child items** again.

Example output:

``` json
[
  {"name": "customers.csv", "type": "File"},
  {"name": "sales.csv", "type": "File"}
]
```

Now the pipeline has two arrays (lists):

-   Source array: four file items.
-   Destination array: two file items.

### 4.3 Filter Activity

**What is Filter?**\
Filter takes an array and returns only the items that satisfy a
condition.

**Why do we use it?**\
We want source files that do not already exist in the destination.

Conceptually, for every source file:

1.  Check whether the destination list contains that file.
2.  If it exists, exclude it.
3.  If it does not exist, keep it in the Filter output.

The tutorial uses the `contains()` function for this comparison.

**Important concept:** The Filter activity's input is the **source Child
items array**, because we want to find which source files are missing
from the destination.

Conceptual logic:

``` text
For each file in Source:
    If Destination does NOT contain this file:
        Keep it in Filter output
    Otherwise:
        Exclude it
```

For the example:

  Source file       Exists in destination? Filter result
  --------------- ------------------------ ---------------
  customers.csv                        Yes Exclude
  sales.csv                            Yes Exclude
  products.csv                          No Keep
  orders.csv                            No Keep

The Filter output contains `products.csv` and `orders.csv`.

> **Implementation note:** Get Metadata returns child-item objects, not
> just plain strings. When building the exact ADF expression, compare
> the appropriate file-name property (such as `item().name`) against the
> destination child-item names. Ensure the expression checks for **not
> present**, so existing files are excluded.

### 4.4 ForEach Activity

**What is ForEach?**\
ForEach loops through every item in an array.

**Why do we use it?**\
The Filter output may contain one missing file or many missing files.
ForEach processes each one.

Example:

    Iteration Current file
  ----------- --------------
            1 products.csv
            2 orders.csv

The current item is available inside the loop and can be used to
parameterize the source file path/name.

### 4.5 Copy Activity

Copy Activity moves data from a source to a destination by reading and
writing it.

Inside ForEach:

-   Source: the current missing file in the Source folder.
-   Sink/destination: the corresponding file location in the Destination
    folder.

The loop runs Copy Activity for each missing file.

------------------------------------------------------------------------

## 5. End-to-end execution

1.  Pipeline starts.
2.  Get Metadata -- Source reads the source folder's Child items.
3.  Get Metadata -- Destination reads the destination folder's Child
    items.
4.  Filter compares source files against destination files.
5.  Filter outputs only missing files.
6.  ForEach loops through those missing files.
7.  Copy Activity copies each missing file.
8.  Check the pipeline run in the ADF **Monitor** view.

### Expected result

Before:

``` text
Source:      customers.csv, sales.csv, products.csv, orders.csv
Destination: customers.csv, sales.csv
```

After:

``` text
Source:      customers.csv, sales.csv, products.csv, orders.csv
Destination: customers.csv, sales.csv, products.csv, orders.csv
```

The source files remain in the source folder. Copy Activity copies them;
it does not delete the originals.

------------------------------------------------------------------------

## 6. Two approaches mentioned in the tutorial

The tutorial describes two ways to compare the folders:

### Approach 1 -- Filter activity

1.  Get Metadata on Source.
2.  Get Metadata on Destination.
3.  Pass the Source Child items array to Filter.
4.  Use a condition to keep source items that are not present in the
    destination list.
5.  Pass the Filter output to ForEach.
6.  Copy each missing file.

### Approach 2 -- ForEach with a condition

1.  Get Metadata on Source.
2.  Get Metadata on Destination.
3.  Pass the Source Child items array to ForEach.
4.  For each source file, check whether it exists in the destination
    array.
5.  If it does not exist, run Copy Activity.
6.  If it already exists, do not copy it.

Both approaches have the same objective. The tutorial demonstrates the
Filter approach.

------------------------------------------------------------------------

## 7. Real-world uses

  -----------------------------------------------------------------------
  Industry                            Example
  ----------------------------------- -----------------------------------
  Banking                             Copy transaction files that have
                                      not yet reached the reporting
                                      folder.

  E-commerce                          Copy newly received order or sales
                                      files.

  Healthcare                          Copy missing report files into an
                                      analytics storage area.

  Retail                              Copy new inventory files from store
                                      folders.
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 8. Interview questions and answers

**Q1. What is the purpose of Get Metadata?**\
It retrieves metadata about a file or folder. In this scenario, Child
items gives us the list of files in a folder.

**Q2. Why do we use Get Metadata on both folders?**\
We need the source file list and the destination file list so that we
can compare them.

**Q3. Why is the source array passed to Filter?**\
Because we want to examine every source file and identify which ones are
missing from the destination.

**Q4. What is the purpose of Filter Activity?**\
It returns only the array items that satisfy the configured condition.

**Q5. What is the purpose of ForEach?**\
It processes each item in an array, one iteration at a time or in
parallel depending on its configuration.

**Q6. Why do we use Copy Activity inside ForEach?**\
Because each missing file must be copied individually using its current
file name/path.

**Q7. What is the difference between Scenario 1 and Scenario 2 in the
tutorial?**

  -----------------------------------------------------------------------
  Scenario 1                          Scenario 2
  ----------------------------------- -----------------------------------
  Finds the latest file using         Finds files missing from the
  modification time.                  destination.

  Uses Get Metadata, ForEach, If      Uses Get Metadata, Filter, ForEach
  Condition and variables.            and Copy Activity.

  Compares last-modified dates.       Compares file presence/names.
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 9. Important production considerations

This tutorial's basic approach checks whether a file is present by its
name/item. It does not compare the file contents.

For example, if `sales.csv` already exists in the destination and the
source version is later updated, a simple name-based check may skip the
updated file.

For a production pipeline, consider:

-   Whether file names are unique.
-   Whether file names are case-sensitive in the storage path.
-   What should happen if a file exists but its contents have changed.
-   How to handle failed or partially completed copies.
-   Whether to compare last-modified timestamps, file sizes, checksums,
    or maintain a processing log.
-   Whether parallel ForEach execution could cause conflicts.

Also remember that Get Metadata, Filter, ForEach and Copy Activity
executions can contribute to Azure usage charges. Use small test files
and monitor costs while practising.

------------------------------------------------------------------------

## 10. Quick revision

-   **Get Metadata:** Finds information about files/folders.
-   **Child items:** Lists the items inside a folder.
-   **Filter:** Keeps only items that satisfy a condition.
-   **contains():** Checks whether an array contains a specified
    value/item.
-   **ForEach:** Loops through an array.
-   **Copy Activity:** Copies the current file to the destination.
-   **Monitor:** Helps verify whether the pipeline succeeded or failed.

### One-line summary

> Scenario 2 compares the Source and Destination folder contents and
> copies only the files that are present in Source but missing from
> Destination.

Let's test whether your pipeline avoids copying files again.
1. Run Debug one more time.
2. Since all four files now exist in the destination, Filter should return zero files.
3. ForEach should execute zero iterations.
4. No files should be copied.
Expected result
 Pipeline succeeds with 0 new copies.

This is an important concept called idempotent processing: repeating the same operation should not create unnecessary duplicate work.
Interview question
Q: How do you copy only missing files from source to destination using Azure Data Factory?

Answer: I use Get Metadata to retrieve file lists from both folders, Filter to identify files that don't exist in the destination, ForEach to iterate through the filtered files, and Copy Activity with dynamic dataset parameters to copy each missing file.

One final reminder: because you're practising with an Azure Free Trial, check Cost Management after your exercises and remove resources when you no longer need them. 

You've completed your first end-to-end ADF file-processing scenario!
