-- 1. Set up date parameters
DECLARE @year INT = 2019;
DECLARE @start_date DATE = DATEFROMPARTS(@year, 1, 1);
DECLARE @end_date DATE = DATEADD(DAY, 1, DATEFROMPARTS(@year, 12, 31));

-- 2. Create and populate RFM base metrics
IF OBJECT_ID('tempdb..#RFM_Base') IS NOT NULL DROP TABLE #RFM_Base;
SELECT 
    customerno,
    DATEDIFF(DAY, MAX(date), @end_date) AS recency,
    DATEDIFF(DAY, MIN(date), MAX(date))/ NULLIF(COUNT(*), 0) AS frequency,
    SUM(price * quantity) / NULLIF(COUNT(*), 0) AS monetary
INTO #RFM_Base
FROM Uk_Sale_Transaction
WHERE YEAR(date) = @year
GROUP BY customerno
HAVING DATEDIFF(DAY, MIN(Date), MAX(Date)) / NULLIF(COUNT(*), 0) > 0;

-- 3. Create and populate percentile values
IF OBJECT_ID('tempdb..#Percentiles') IS NOT NULL DROP TABLE #Percentiles;
SELECT 
    PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY recency) OVER() AS recency_20,
    PERCENTILE_DISC(0.4) WITHIN GROUP (ORDER BY recency) OVER() AS recency_40,
    PERCENTILE_DISC(0.6) WITHIN GROUP (ORDER BY recency) OVER() AS recency_60,
    PERCENTILE_DISC(0.8) WITHIN GROUP (ORDER BY recency) OVER() AS recency_80,
    
    PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_20,
    PERCENTILE_DISC(0.4) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_40,
    PERCENTILE_DISC(0.6) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_60,
    PERCENTILE_DISC(0.8) WITHIN GROUP (ORDER BY frequency) OVER() AS frequency_80,
    
    PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY monetary * -1) OVER() * -1 AS monetary_20,
    PERCENTILE_DISC(0.4) WITHIN GROUP (ORDER BY monetary * -1) OVER() * -1 AS monetary_40,
    PERCENTILE_DISC(0.6) WITHIN GROUP (ORDER BY monetary * -1) OVER() * -1 AS monetary_60,
    PERCENTILE_DISC(0.8) WITHIN GROUP (ORDER BY monetary * -1) OVER() * -1 AS monetary_80
INTO #Percentiles
FROM #RFM_Base;

-- Store percentile values in variables
DECLARE @recency_20 INT, @recency_40 INT, @recency_60 INT, @recency_80 INT;
DECLARE @frequency_20 FLOAT, @frequency_40 FLOAT, @frequency_60 FLOAT, @frequency_80 FLOAT;
DECLARE @monetary_20 FLOAT, @monetary_40 FLOAT, @monetary_60 FLOAT, @monetary_80 FLOAT;

SELECT 
    @recency_20 = recency_20, @recency_40 = recency_40, 
    @recency_60 = recency_60, @recency_80 = recency_80,
    @frequency_20 = frequency_20, @frequency_40 = frequency_40,
    @frequency_60 = frequency_60, @frequency_80 = frequency_80,
    @monetary_20 = monetary_20, @monetary_40 = monetary_40,
    @monetary_60 = monetary_60, @monetary_80 = monetary_80
FROM #Percentiles;

-- 4. Create and populate RFM Scores
IF OBJECT_ID('tempdb..#RFM_Scores') IS NOT NULL DROP TABLE #RFM_Scores;
SELECT 
    CustomerNo,
    CONCAT(
        CASE
            WHEN recency <= @recency_20 THEN 5
            WHEN recency <= @recency_40 THEN 4
            WHEN recency <= @recency_60 THEN 3
            WHEN recency <= @recency_80 THEN 2
            ELSE 1
        END,
        CASE
            WHEN frequency <= @frequency_20 THEN 5
            WHEN frequency <= @frequency_40 THEN 4
            WHEN frequency <= @frequency_60 THEN 3
            WHEN frequency <= @frequency_80 THEN 2
            ELSE 1
        END,
        CASE
            WHEN monetary >= @monetary_20 THEN 5
            WHEN monetary >= @monetary_40 THEN 4
            WHEN monetary >= @monetary_60 THEN 3
            WHEN monetary >= @monetary_80 THEN 2
            ELSE 1
        END
    ) AS rfm_score
INTO #RFM_Scores
FROM #RFM_Base;

-- 5. Create and populate Segment Classification
IF OBJECT_ID('tempdb..#RFM_Segments') IS NOT NULL DROP TABLE #RFM_Segments;
SELECT rfm_score,
    CASE 
        WHEN rfm_score IN ('555', '554', '544', '545', '454', '455', '445') 
            THEN 'Champions'
        WHEN rfm_score IN ('543', '444', '435', '355', '354', '345', '344', '335') 
            THEN 'Loyal'
        WHEN rfm_score IN ('553', '551', '552', '541', '542', '533', '532', '531', 
                          '452', '451', '442', '441', '431', '453', '433', '432', 
                          '423', '353', '352', '351', '342', '341', '333', '323') 
            THEN 'Potential Loyalist'
        WHEN rfm_score IN ('512', '511', '422', '421', '412', '411', '311') 
            THEN 'New Customers'
        WHEN rfm_score IN ('525', '524', '523', '522', '521', '515', '514', 
                          '513', '425', '424', '413', '414', '415', '315', '314', '313') 
            THEN 'Promising'
        WHEN rfm_score IN ('535', '534', '443', '434', '343', '334', '325', '324') 
            THEN 'Need Attention'
        WHEN rfm_score IN ('331', '321', '312', '221', '213', '231', '241', '251') 
            THEN 'About to Sleep'
        WHEN rfm_score IN ('155', '154', '144', '214', '215', '115', '114', '113') 
            THEN 'Cannot Lose Them But Losing'
        WHEN rfm_score IN ('255', '254', '245', '244', '253', '252', '243', '242', 
                          '235', '234', '225', '224', '153', '152', '145', '143', 
                          '142', '135', '134', '133', '125', '124') 
            THEN 'At Risk'
        WHEN rfm_score IN ('332', '322', '233', '232', '223', '222', '132', '123', 
                          '122', '212', '211') 
            THEN 'Hibernating'
        WHEN rfm_score IN ('111', '112', '121', '131', '141', '151') 
            THEN 'Lost Customers'
        ELSE 'Unclassified'
    END AS segment
INTO #RFM_Segments
FROM #RFM_Scores;

-- 6. View Results
-- View individual customer segments
SELECT DISTINCT 
    s.CustomerNo,
    s.rfm_score,
    seg.segment
FROM #RFM_Scores s
JOIN #RFM_Segments seg ON s.rfm_score = seg.rfm_score;

-- View segment summary
SELECT 
    seg.segment,
    COUNT(DISTINCT s.CustomerNo) AS customer_count
FROM #RFM_Scores s
JOIN #RFM_Segments seg ON s.rfm_score = seg.rfm_score
GROUP BY seg.segment
ORDER BY customer_count DESC;

-- View detailed breakdown by segment and RFM score
SELECT 
    seg.segment,
    s.rfm_score,
    COUNT(DISTINCT s.CustomerNo) AS customer_count,
    SUM(COUNT(DISTINCT s.CustomerNo)) OVER (PARTITION BY seg.segment) AS segment_total
FROM #RFM_Scores s
JOIN #RFM_Segments seg ON s.rfm_score = seg.rfm_score
GROUP BY seg.segment, s.rfm_score
ORDER BY 
    seg.segment,
    customer_count DESC;
