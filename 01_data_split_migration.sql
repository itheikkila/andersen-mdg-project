-- Target Table 1: Dim_Products (Product Master Data)

CREATE TABLE Dim_Products AS
SELECT DISTINCT
    "Product Card Id" AS Product_ID,
    "Product Name" AS Product_Name,
    "Category Id" AS Category_ID,
    "Category Name" AS Category_Name,
    "Product Price" AS Standard_Price
FROM STG_DataCo_Raw
WHERE "Product Card Id" IS NOT NULL;

-- Target Table 2: Dim_Customers (Customer Master Data)

CREATE TABLE Dim_Customers AS
SELECT DISTINCT
    "Customer Id" AS Customer_ID,
    "Customer Fname" AS First_Name,
    "Customer Lname" AS Last_Name,
    "Customer City" AS City,
    "Customer State" AS State,
    "Customer Segment" AS Segment
FROM STG_DataCo_Raw
WHERE "Customer Id" IS NOT NULL;

-- Target Table 3: Fact_Orders (Transactional Ledger)

CREATE TABLE Fact_Orders AS
SELECT
    "Order Id" AS Order_ID,
    "Order Item Cardprod Id" AS Product_ID, -- Links to Dim_Products
    "Customer Id" AS Customer_ID,           -- Links to Dim_Customers
    "order date (DateOrders)" AS Order_Date,
    "Order Item Quantity" AS Quantity,
    "Sales" AS Total_Sales,
    "Order Status" AS Order_Status
FROM STG_DataCo_Raw;

/* ============================================================================
   PROJECT: Master Data Governance - Supply Chain Anomaly Detection
   AUTHOR: Isaac
   DATE: May 2026
   DESCRIPTION: This script profiles a simulated 3-table SQLite database 
                (Products, Customers, Orders) to detect referential integrity 
                failures, pricing anomalies, and structural completeness issues.
   ============================================================================ */

/* ----------------------------------------------------------------------------
   QUERY 1: THE INTEGRITY PROFILER
   Purpose: Detect "orphaned" transactional records.
   Governance Risk: Transactional systems generating orders with Customer or 
                    Product IDs that do not exist in the master hub.
   ---------------------------------------------------------------------------- */

SELECT 
    o.Order_ID,
    o.Order_Date,
    o.Customer_ID AS Order_Customer_ID,
    c.Customer_ID AS Master_Customer_ID,
    o.Product_ID AS Order_Product_ID,
    p.Product_ID AS Master_Product_ID,
    CASE 
        WHEN c.Customer_ID IS NULL AND p.Product_ID IS NULL THEN 'Critical: Both Customer & Product Master Missing'
        WHEN c.Customer_ID IS NULL THEN 'Error: Missing Customer Master Record'
        WHEN p.Product_ID IS NULL THEN 'Error: Missing Product Master Record'
    END AS Integrity_Failure_Type
FROM Fact_Orders o
LEFT JOIN Dim_Customers c ON o.Customer_ID = c.Customer_ID
LEFT JOIN Dim_Products p ON o.Product_ID = p.Product_ID
WHERE c.Customer_ID IS NULL 
   OR p.Product_ID IS NULL;

/* ----------------------------------------------------------------------------
   QUERY 2: Product Attribute Anomalies (Detecting Outliers)
   Purpose: Find price discrepancies.
   Governance Risk: Incorrectly priced materials.
   ---------------------------------------------------------------------------- */

WITH Order_Pricing_Analysis AS (
    SELECT 
        o.Order_ID,
        p.Product_ID,
        p.Product_Name,
        p.Standard_Price,
        -- Calculate the actual unit price charged in the transaction
        ROUND(o.Total_Sales / o.Quantity, 2) AS Actual_Unit_Price
    FROM Fact_Orders o
    JOIN Dim_Products p ON o.Product_ID = p.Product_ID
    WHERE o.Quantity > 0
)
SELECT 
    Product_ID,
    Product_Name,
    Standard_Price,
    Actual_Unit_Price,
    ROUND(Actual_Unit_Price - Standard_Price, 2) AS Price_Variance,
    ROUND(((Actual_Unit_Price - Standard_Price) / Standard_Price) * 100, 2) AS Percent_Variance
FROM Order_Pricing_Analysis
-- Flag variations greater than 15% above or below master catalog price
WHERE ABS(((Actual_Unit_Price - Standard_Price) / Standard_Price) * 100) > 15.0
ORDER BY ABS(Percent_Variance) DESC;

/* ----------------------------------------------------------------------------
   QUERY 3: METADATA COMPLETENESS SCORING
   Purpose: Profile the Customer Master table for missing critical fields.
   Governance Risk: Missing geographic data breaks automated tax and shipping logic.
   ---------------------------------------------------------------------------- */

SELECT 
    COUNT(*) AS Total_Customer_Records,
    SUM(CASE WHEN City IS NULL OR TRIM(City) = '' THEN 1 ELSE 0 END) AS Missing_Cities,
    SUM(CASE WHEN State IS NULL OR TRIM(State) = '' THEN 1 ELSE 0 END) AS Missing_States,
    ROUND(((COUNT(*) - SUM(CASE WHEN State IS NULL OR TRIM(State) = '' THEN 1 ELSE 0 END)) * 100.0) / COUNT(*), 2) AS State_Completeness_Score
FROM Dim_Customers;