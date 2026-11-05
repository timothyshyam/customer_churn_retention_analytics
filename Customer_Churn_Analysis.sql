-- Customer Churn & Retention Analytics
-- Run this script in MySQL 8.0.
-- First, use MySQL Workbench's Table Data Import Wizard to load
-- customers_raw.csv into the table named customers_raw.

CREATE DATABASE IF NOT EXISTS churn_analytics;
USE churn_analytics;

-- The raw table keeps the original values from the CSV file.
CREATE TABLE IF NOT EXISTS customers_raw (
    customer_id VARCHAR(20),
    gender VARCHAR(20),
    age INT,
    tenure_months INT,
    contract_type VARCHAR(40),
    internet_service VARCHAR(40),
    payment_method VARCHAR(40),
    monthly_charges DECIMAL(10,2),
    total_charges DECIMAL(12,2),
    support_tickets_90d DECIMAL(10,2),
    late_payments_12m INT,
    autopay VARCHAR(10),
    paperless_billing VARCHAR(10),
    streaming_bundle VARCHAR(10),
    churn VARCHAR(10)
);

-- Check the number of rows and missing values before cleaning.
SELECT COUNT(*) AS raw_rows FROM customers_raw;

SELECT
    SUM(total_charges IS NULL) AS missing_total_charges,
    SUM(support_tickets_90d IS NULL) AS missing_support_tickets
FROM customers_raw;

-- Find repeated customer IDs.
SELECT customer_id, COUNT(*) AS records_found
FROM customers_raw
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Find the median support-ticket count to use for missing values.
SET @median_support_tickets = (
    SELECT AVG(support_tickets_90d)
    FROM (
        SELECT
            support_tickets_90d,
            ROW_NUMBER() OVER (ORDER BY support_tickets_90d) AS row_num,
            COUNT(*) OVER () AS total_rows
        FROM customers_raw
        WHERE support_tickets_90d IS NOT NULL
    ) AS ticket_numbers
    WHERE row_num IN (
        FLOOR((total_rows + 1) / 2),
        FLOOR((total_rows + 2) / 2)
    )
);

-- Remove repeated customer IDs, tidy category names and fill missing values.
DROP TABLE IF EXISTS customers_clean;

CREATE TABLE customers_clean AS
SELECT
    customer_id,
    CASE
        WHEN LOWER(TRIM(gender)) = 'male' THEN 'Male'
        WHEN LOWER(TRIM(gender)) = 'female' THEN 'Female'
        ELSE TRIM(gender)
    END AS gender,
    age,
    tenure_months,
    CASE
        WHEN LOWER(TRIM(contract_type)) = 'month-to-month' THEN 'Month-to-month'
        WHEN LOWER(TRIM(contract_type)) = 'one year' THEN 'One year'
        WHEN LOWER(TRIM(contract_type)) = 'two year' THEN 'Two year'
        ELSE TRIM(contract_type)
    END AS contract_type,
    CASE
        WHEN LOWER(TRIM(internet_service)) = 'dsl' THEN 'DSL'
        WHEN LOWER(TRIM(internet_service)) = 'fiber optic' THEN 'Fiber optic'
        WHEN LOWER(TRIM(internet_service)) = 'no internet' THEN 'No internet'
        ELSE TRIM(internet_service)
    END AS internet_service,
    CASE
        WHEN LOWER(TRIM(payment_method)) = 'bank transfer' THEN 'Bank transfer'
        WHEN LOWER(TRIM(payment_method)) = 'credit card' THEN 'Credit card'
        WHEN LOWER(TRIM(payment_method)) = 'electronic check' THEN 'Electronic check'
        WHEN LOWER(TRIM(payment_method)) = 'mailed check' THEN 'Mailed check'
        ELSE TRIM(payment_method)
    END AS payment_method,
    monthly_charges,
    ROUND(COALESCE(total_charges, monthly_charges * tenure_months), 2) AS total_charges,
    CAST(COALESCE(support_tickets_90d, @median_support_tickets) AS UNSIGNED) AS support_tickets_90d,
    late_payments_12m,
    CASE WHEN LOWER(TRIM(autopay)) = 'yes' THEN 'Yes' ELSE 'No' END AS autopay,
    CASE WHEN LOWER(TRIM(paperless_billing)) = 'yes' THEN 'Yes' ELSE 'No' END AS paperless_billing,
    CASE WHEN LOWER(TRIM(streaming_bundle)) = 'yes' THEN 'Yes' ELSE 'No' END AS streaming_bundle,
    CASE WHEN LOWER(TRIM(churn)) = 'yes' THEN 'Yes' ELSE 'No' END AS churn
FROM (
    SELECT
        customers_raw.*,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY customer_id
        ) AS customer_row
    FROM customers_raw
) AS numbered_customers
WHERE customer_row = 1;

ALTER TABLE customers_clean ADD PRIMARY KEY (customer_id);

-- Confirm the cleaned data.
SELECT COUNT(*) AS cleaned_customers FROM customers_clean;
SELECT COUNT(*) AS repeated_customer_ids
FROM (
    SELECT customer_id
    FROM customers_clean
    GROUP BY customer_id
    HAVING COUNT(*) > 1
) AS repeated_ids;

SELECT
    SUM(total_charges IS NULL) AS missing_total_charges,
    SUM(support_tickets_90d IS NULL) AS missing_support_tickets
FROM customers_clean;

-- BUSINESS QUESTION 1: How many customers have stayed or left?
SELECT
    COUNT(*) AS total_customers,
    SUM(churn = 'Yes') AS churned_customers,
    SUM(churn = 'No') AS retained_customers,
    ROUND(100 * SUM(churn = 'Yes') / COUNT(*), 2) AS churn_rate_percent
FROM customers_clean;

-- BUSINESS QUESTION 2: Which contract type has the highest churn rate?
SELECT
    contract_type,
    COUNT(*) AS customers,
    SUM(churn = 'Yes') AS churned_customers,
    ROUND(100 * SUM(churn = 'Yes') / COUNT(*), 2) AS churn_rate_percent
FROM customers_clean
GROUP BY contract_type
ORDER BY churn_rate_percent DESC;

-- BUSINESS QUESTION 3: At what stage of tenure do customers leave?
SELECT
    CASE
        WHEN tenure_months <= 5 THEN '0-5 months'
        WHEN tenure_months <= 11 THEN '6-11 months'
        WHEN tenure_months <= 23 THEN '12-23 months'
        WHEN tenure_months <= 47 THEN '24-47 months'
        ELSE '48+ months'
    END AS tenure_band,
    COUNT(*) AS customers,
    SUM(churn = 'Yes') AS churned_customers,
    ROUND(100 * SUM(churn = 'Yes') / COUNT(*), 2) AS churn_rate_percent
FROM customers_clean
GROUP BY tenure_band
ORDER BY MIN(tenure_months);

-- BUSINESS QUESTION 4: Does internet service type relate to churn?
SELECT
    internet_service,
    COUNT(*) AS customers,
    SUM(churn = 'Yes') AS churned_customers,
    ROUND(100 * SUM(churn = 'Yes') / COUNT(*), 2) AS churn_rate_percent
FROM customers_clean
GROUP BY internet_service
ORDER BY churn_rate_percent DESC;

-- BUSINESS QUESTION 5: Which payment method has the highest churn rate?
SELECT
    payment_method,
    COUNT(*) AS customers,
    SUM(churn = 'Yes') AS churned_customers,
    ROUND(100 * SUM(churn = 'Yes') / COUNT(*), 2) AS churn_rate_percent
FROM customers_clean
GROUP BY payment_method
ORDER BY churn_rate_percent DESC;

-- BUSINESS QUESTION 6: Is churn different for customers using AutoPay?
SELECT
    autopay,
    COUNT(*) AS customers,
    SUM(churn = 'Yes') AS churned_customers,
    ROUND(100 * SUM(churn = 'Yes') / COUNT(*), 2) AS churn_rate_percent
FROM customers_clean
GROUP BY autopay
ORDER BY churn_rate_percent DESC;

-- BUSINESS QUESTION 7: How much monthly charge is associated with churned customers?
SELECT
    COUNT(*) AS churned_customers,
    ROUND(SUM(monthly_charges), 2) AS monthly_charges_from_churned_customers,
    ROUND(AVG(monthly_charges), 2) AS average_monthly_charge
FROM customers_clean
WHERE churn = 'Yes';

-- BUSINESS QUESTION 8: Which retained customers may need a follow-up?
-- This list shows customers with at least two support tickets in 90 days.
SELECT
    customer_id,
    contract_type,
    tenure_months,
    support_tickets_90d,
    monthly_charges
FROM customers_clean
WHERE churn = 'No'
  AND support_tickets_90d >= 2
ORDER BY support_tickets_90d DESC, monthly_charges DESC
LIMIT 20;
