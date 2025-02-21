-- Input parameters for flexible analysis
DECLARE @year INT = 2019;                    -- Analysis year
DECLARE @time_unit VARCHAR(10) = 'Month';  -- Time unit ('MONTH' or 'QUARTER')
DECLARE @from_period INT = NULL;             -- Starting period (NULL for all)
DECLARE @to_period INT = NULL;               -- Ending period (NULL for all)

-- Define date range
DECLARE @start_date DATE = DATEFROMPARTS(@year, 1, 1);
DECLARE @end_date DATE = DATEADD(DAY, -1, DATEFROMPARTS(@year + 1, 1, 1));

-- Calculate RFM metrics based on selected time unit
WITH metrics AS (
    SELECT 
        CustomerNo,
        YEAR(Date) AS year,
        CASE 
            WHEN @time_unit = 'MONTH' THEN MONTH(Date)
            ELSE DATEPART(QUARTER, Date)
        END AS period,
        DATEDIFF(DAY, MAX(Date), @end_date) AS recency,
        DATEDIFF(DAY, MIN(Date), MAX(Date)) / NULLIF(COUNT(*), 0) AS frequency,
        SUM(Quantity * Price) / NULLIF(COUNT(*), 0) AS monetary
    FROM [sale_transaction-data]
    WHERE YEAR(Date) = @year
    GROUP BY 
        CustomerNo, 
        YEAR(Date), 
        CASE 
            WHEN @time_unit = 'MONTH' THEN MONTH(Date)
            ELSE DATEPART(QUARTER, Date)
        END
    HAVING 
        DATEDIFF(DAY, MIN(Date), MAX(Date)) / NULLIF(COUNT(*), 0) > 0
)

-- Save metrics to temporary table
SELECT * INTO #metrics FROM metrics;

-- Calculate percentile values for RFM scoring
SELECT 
    -- Recency: lower is better
    percentile_disc(0.2) WITHIN GROUP (ORDER BY recency) OVER() AS recency_20,
    percentile_disc(0.4) WITHIN GROUP (ORDER BY recency) OVER() AS recency_40,
    percentile_disc(0.6) WITHIN GROUP (ORDER BY recency) OVER() AS recency_60,
    percentile_disc(0.8) WITHIN GROUP (ORDER BY recency) OVER() AS recency_80,

    -- Frequency: lower is better (days between purchases)
    percentile_disc(0.2) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_20,
    percentile_disc(0.4) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_40,
    percentile_disc(0.6) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_60,
    percentile_disc(0.8) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_80,

    -- Monetary: higher is better
    -1 * percentile_disc(0.2) WITHIN GROUP (ORDER BY monetary * -1) OVER() AS monetary_20,
    -1 * percentile_disc(0.4) WITHIN GROUP (ORDER BY monetary * -1) OVER() AS monetary_40,
    -1 * percentile_disc(0.6) WITHIN GROUP (ORDER BY monetary * -1) OVER() AS monetary_60,
    -1 * percentile_disc(0.8) WITHIN GROUP (ORDER BY monetary * -1) OVER() AS monetary_80
INTO #percentile_values
FROM #metrics;

-- Declare variables for percentile boundaries
DECLARE @recency_20 INT, @recency_40 INT, @recency_60 INT, @recency_80 INT;
DECLARE @frequency_20 DECIMAL(10, 2), @frequency_40 DECIMAL(10, 2), @frequency_60 DECIMAL(10, 2), @frequency_80 DECIMAL(10, 2);
DECLARE @monetary_20 DECIMAL(10, 2), @monetary_40 DECIMAL(10, 2), @monetary_60 DECIMAL(10, 2), @monetary_80 DECIMAL(10, 2);

-- Assign values from temporary table to variables
SELECT 
    @recency_20 = recency_20,
    @recency_40 = recency_40,
    @recency_60 = recency_60,
    @recency_80 = recency_80,

    @frequency_20 = frequency_20,
    @frequency_40 = frequency_40,
    @frequency_60 = frequency_60,
    @frequency_80 = frequency_80,

    @monetary_20 = monetary_20,
    @monetary_40 = monetary_40,
    @monetary_60 = monetary_60,
    @monetary_80 = monetary_80
FROM 
    #percentile_values;

-- Calculate RFM scores for each customer and period
SELECT
    CustomerNo,
    year,
    period,
    CAST(
        CASE
            WHEN recency <= @recency_20 THEN 5
            WHEN recency <= @recency_40 THEN 4
            WHEN recency <= @recency_60 THEN 3
            WHEN recency <= @recency_80 THEN 2
            ELSE 1
        END AS VARCHAR
    ) + CAST(
        CASE
            WHEN frequency <= @frequency_20 THEN 5
            WHEN frequency <= @frequency_40 THEN 4
            WHEN frequency <= @frequency_60 THEN 3
            WHEN frequency <= @frequency_80 THEN 2
            ELSE 1
        END AS VARCHAR
    ) + CAST(
        CASE
            WHEN monetary >= @monetary_20 THEN 5
            WHEN monetary >= @monetary_40 THEN 4
            WHEN monetary >= @monetary_60 THEN 3
            WHEN monetary >= @monetary_80 THEN 2
            ELSE 1
        END AS VARCHAR
    ) AS rfm_score
INTO #rfm_scores
FROM #metrics;

-- Define RFM segments based on RFM scores
SELECT DISTINCT rfm_score,
  CASE 
        -- Champions
        WHEN rfm_score IN ('555', '554', '544', '545', '454', '455', '445') THEN 'Champions'
        -- Loyal Customers
        WHEN rfm_score IN ('543', '444', '435', '355', '354', '345', '344', '335') THEN 'Loyal'
        -- Potential Loyalist
        WHEN rfm_score IN ('553', '551', '552', '541', '542', '533', '532', '531', '452', '451', '442', '441', '431', '453', '433', '432', '423', '353', '352', '351', '342', '341', '333', '323') THEN 'Potential Loyalist'
        -- New Customers
        WHEN rfm_score IN ('512', '511', '422', '421', '412', '411', '311') THEN 'New Customers'
        -- Promising
        WHEN rfm_score IN ('525', '524', '523', '522', '521', '515', '514', '513', '425', '424', '413', '414', '415', '315', '314', '313') THEN 'Promising'
        -- Need Attention
        WHEN rfm_score IN ('535', '534', '443', '434', '343', '334', '325', '324') THEN 'Need Attention'
        -- About to Sleep
        WHEN rfm_score IN ('331', '321', '312', '221', '213', '231', '241', '251') THEN 'About to Sleep'
        -- Cannot Lose Them But Losing
        WHEN rfm_score IN ('155', '154', '144', '214', '215', '115', '114', '113') THEN 'Cannot Lose Them But Losing'
        -- At Risk
        WHEN rfm_score IN ('255', '254', '245', '244', '253', '252', '243', '242', '235', '234', '225', '224', '153', '152', '145', '143', '142', '135', '134', '133', '125', '124') THEN 'At Risk'
        -- Hibernating
        WHEN rfm_score IN ('332', '322', '233', '232', '223', '222', '132', '123', '122', '212', '211') THEN 'Hibernating'
        -- Lost Customers
        WHEN rfm_score IN ('111', '112', '121', '131', '141', '151') THEN 'Lost Customers'
        ELSE 'Unclassified'
 END AS rfm_segment
INTO #rfm_segment
FROM #rfm_scores;

-- Analyze customer transitions between segments across periods
SELECT 
    a.year,
    @time_unit AS time_unit,
    a.period AS period_from,
    b.period AS period_to,
    a.rfm_score AS rfm_from,
    rs_from.rfm_segment AS segment_from,
    b.rfm_score AS rfm_to,
    rs_to.rfm_segment AS segment_to,
    COUNT(DISTINCT a.CustomerNo) AS num_customers
FROM 
    #rfm_scores a
JOIN 
    #rfm_scores b ON a.CustomerNo = b.CustomerNo 
                  AND a.year = b.year 
                  AND a.period + 1 = b.period
JOIN 
    #rfm_segment rs_from ON a.rfm_score = rs_from.rfm_score
JOIN 
    #rfm_segment rs_to ON b.rfm_score = rs_to.rfm_score
WHERE 
    a.year = @year
    AND (@from_period IS NULL OR a.period = @from_period)
    AND (@to_period IS NULL OR b.period = @to_period)
GROUP BY 
    a.year,
    a.period,
    b.period,
    a.rfm_score,
    rs_from.rfm_segment,
    b.rfm_score,
    rs_to.rfm_segment
ORDER BY 
    a.year,
    a.period,
    b.period,
    rs_from.rfm_segment,
    rs_to.rfm_segment;

-- -- Clean up temporary tables
DROP TABLE #metrics;
DROP TABLE #percentile_values;
DROP TABLE #rfm_scores;
DROP TABLE #rfm_segment;




