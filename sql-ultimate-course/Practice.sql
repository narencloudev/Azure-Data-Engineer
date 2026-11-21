
----OR
SELECT *
FROM customers
WHERE country = 'Germany' OR country = 'USA';

----IN
SELECT *
FROM customers
WHERE country IN ('Germany', 'USA');

----Like
SELECT *
FROM customers
WHERE first_name LIKE '__r%'

----Joins

SELECT *
FROM customers;

SELECT * 
FROM orders;

-----INNER JOIN
SELECT 
    c.id,
    c.first_name,
    c.country,
    o.order_id,
    o.sales
FROM customers AS c
INNER JOIN orders as o
ON c.id = o.customer_id;

-----LEFT JOIN
SELECT 
    c.id,
    c.first_name,
    c.country,
    o.order_id,
    o.sales
FROM orders as o
LEFT JOIN customers AS c
ON c.id = o.customer_id;

-----RIGHT JOIN
SELECT 
    c.id,
    c.first_name,
    c.country,
    o.order_id,
    o.sales
FROM customers AS c
RIGHT JOIN orders as o
ON c.id = o.customer_id;

-----FULL JOIN
SELECT 
    c.id,
    c.first_name,
    c.country,
    o.order_id,
    o.sales
FROM customers AS c
FULL JOIN orders as o
ON c.id = o.customer_id;

-----LEFT ANTI JOIN
/* get all customers who haven't palce any order*/

SELECT *
FROM customers AS c
LEFT JOIN orders AS o
ON c.id = o.customer_id
WHERE o.customer_id is NULL;

-----LEFT ANTI JOIN
/* get all customers without matching customers */
SELECT *
FROM customers AS c
RIGHT JOIN orders AS o
ON c.id = o.customer_id
WHERE c.id is NULL;

/* get all orders without matching customers */
SELECT *
FROM orders AS o
LEFT JOIN customers AS c
ON c.id = o.customer_id
WHERE c.id IS NULL;

-----FULL ANTI JOIN
/* get all lis */

SELECT *
FROM orders AS o
FULL JOIN customers AS c
ON c.id = o.customer_id
WHERE c.id IS NULL OR o.customer_id IS NULL;

 ---- Get all customers along with their orders, but only for customers who have placed an order (Without Using INNER JOIN] 
 SELECT *
 FROM customers as c
 LEFT JOIN orders AS o
 ON c.id = o.customer_id
 WHERE o.customer_id IS NOT NULL;

 -----CROSS JOIN
/* Generate all possible combinations of customers and orders. */
SELECT *
FROM customers
CROSS JOIN orders;



 /*Task: Using SalesDB, Retrieve a list of all orders, along with the related customer, product, and employee details. For each order, display: Order ID, Customer's name, Product name, Sales, Price, Sales person's name */


SELECT 
o.OrderID,
o.Sales,
c.FirstName,
c.LastName
FROM sales.Orders as o
LEFT JOIN Sales.Customers AS c
ON o.CustomerID = c.CustomerID;

------ set Operators
use SalesDB

---UNION
SELECT 
CustomerID AS I,
LastName AS nn
FROM Sales.Customers

UNION

SELECT 
EmployeeID,
LastName
FROM Sales.Employees

---UNION All
SELECT 
CustomerID AS I,
LastName AS nn
FROM Sales.Customers

UNION All

SELECT 
EmployeeID,
LastName
FROM Sales.Employees

----EXCEPT
SELECT 
FirstName,
LastName
FROM Sales.Employees

EXCEPT

SELECT 
FirstName,
LastName
FROM Sales.Customers

----INTERESECT
SELECT 
    FirstName,
    LastName
FROM Sales.Employees

INTERSECT

SELECT 
    FirstName,
    LastName
FROM Sales.Customers;

----UNION
SELECT
'Orders' AS SourceTable,
 *
FROM Sales.Orders

UNION

SELECT
'OrdersArchive' AS SourceTable,
 *
FROM Sales.OrdersArchive
ORDER BY OrderID


----FUNCTIONS

----String Functions 
---Concat
USE MyDatabase

SELECT
first_name,
country,
CONCAT(first_name, ' ', country) AS name_country,
LOWER(first_name) AS low_name,
UPPER(first_name) AS Upper_name,
TRIM(first_name) as TRIM
FROM customers;


-----TRIM & LEN
SELECT
first_name,
LEN(first_name) as len_name,
LEN(TRIM(first_name)) len_trim_name,
LEN(first_name) - LEN(TRIM(first_name)) flag
FROM Customers
WHERE LEN(first_name) != LEN(TRIM(first_name))


--REPLACE
SELECT
'report.txt' AS old_filename,
REPLACE('report.txt','.txt', '.csv') AS new_filename

--LEN
SELECT
    first_name,
    LEN(first_name) AS name_length
FROM customers

--- LEFT & RIGHT
SELECT
    first_name,
    LEFT(trim(first_name), 2) AS first2char,
    RIGHT(first_name, 2) AS last2char
FROM customers

---SUBSTRING
SELECT
    first_name,
    SUBSTRING(TRIM(first_name), 2, LEN(first_name)) AS trimmed_name
FROM customers

---NUMBER FUNCTIONS
SELECT 
3.516,
ROUND(3.516, 2) AS round_2,
ROUND(3.516, 1) AS round_1,
ROUND(3.516, 0) AS round_0

SELECT 
-10,
ABS(-10),
ABS(10)

---DATE & TIME

USE SalesDB;
---HardCoded
SELECT
OrderID AS OID,
CreationTime,
'2025-08-20' HardCoded,
GETDATE() Today
FROM Sales.Orders;






