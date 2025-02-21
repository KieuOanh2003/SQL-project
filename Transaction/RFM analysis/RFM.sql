DECLARE @year INT = 2019;
DECLARE @start_date DATE = DATEFROMPARTS(@year, 1, 1);
DECLARE @end_date DATE = DATEADD(DAY, 1, DATEFROMPARTS(@year, 12, 31));

--with RFM_data as (
 SELECT 
        customerno,
        DATEDIFF(DAY, MAX(date), @end_date) AS recency, 
DATEDIFF(DAY, MIN(date), MAX(date))/ COUNT(*)  AS frequency,
        SUM(price*quantity) / NULLIF(COUNT(*), 0) AS monetary
    FROM [Uk_Sale_Transaction]
    WHERE YEAR(date) = @year  
    GROUP BY customerno
    HAVING 
    DATEDIFF(DAY, MIN(Date), MAX(Date)) / NULLIF(COUNT(*) , 0) > 0)


SELECT 
    -- Recency: lower values are better
    PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY recency) OVER () AS recency_20,
    PERCENTILE_DISC(0.4) WITHIN GROUP (ORDER BY recency) OVER () AS recency_40,
    PERCENTILE_DISC(0.6) WITHIN GROUP (ORDER BY recency) OVER () AS recency_60,
    PERCENTILE_DISC(0.8) WITHIN GROUP (ORDER BY recency) OVER () AS recency_80,

    -- Frequency: lower values are better
    PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY frequency) OVER () AS frequency_20,
    PERCENTILE_DISC(0.4) WITHIN GROUP (ORDER BY frequency) OVER () AS frequency_40,
    PERCENTILE_DISC(0.6) WITHIN GROUP (ORDER BY frequency) OVER () AS frequency_60,
    PERCENTILE_DISC(0.8) WITHIN GROUP (ORDER BY frequency) OVER () AS frequency_80,

    -- Monetary: higher values are better (negative order to reverse)
    -1 * PERCENTILE_DISC(0.2) WITHIN GROUP (ORDER BY monetary * -1) OVER () AS monetary_20,
    -1 * PERCENTILE_DISC(0.4) WITHIN GROUP (ORDER BY monetary * -1) OVER () AS monetary_40,
    -1 * PERCENTILE_DISC(0.6) WITHIN GROUP (ORDER BY monetary * -1) OVER () AS monetary_60,
    -1 * PERCENTILE_DISC(0.8) WITHIN GROUP (ORDER BY monetary * -1) OVER () AS monetary_80
INTO #percentile_values
FROM rfm_data;

--drop table #percentile_values
DECLARE @recency_20 INT, @recency_40 INT, @recency_60 INT, @recency_80 INT;
DECLARE @frequency_20 DECIMAL(10, 2), @frequency_40 DECIMAL(10, 2), @frequency_60 DECIMAL(10, 2), @frequency_80 DECIMAL(10, 2);
DECLARE @monetary_20 DECIMAL(10, 2), @monetary_40 DECIMAL(10, 2), @monetary_60 DECIMAL(10, 2), @monetary_80 DECIMAL(10, 2);

-- Gán giá trị từ bảng tạm vào biến
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

--drop table #percentile_values
select 
    @recency_20 as recency_20,
    @recency_40 as recency_40,
    @recency_60 as recency_60,
    @recency_80 as recency_80 ,
	 @frequency_20 as  frequency_20,
    @frequency_40 as  frequency_40,
    @frequency_60 as frequency_60,
    @frequency_80 as frequency_80,
    
    @monetary_20 as monetary_20,
    @monetary_40 as monetary_40,
    @monetary_60 as monetary_60,
    @monetary_80 as  monetary_80;


---

DECLARE @year INT = 2019;
DECLARE @start_date DATE = DATEFROMPARTS(@year, 1, 1);
DECLARE @end_date DATE = DATEADD(DAY, 1, DATEFROMPARTS(@year, 12, 31));

with RFM_data as (
 SELECT 
        customerno,
        DATEDIFF(DAY, MAX(date), @end_date) AS recency, 
DATEDIFF(DAY, MIN(date), MAX(date))/ COUNT(*)  AS frequency,
        SUM(price*quantity) / NULLIF(COUNT(*), 0) AS monetary
    FROM Uk_Sale_Transaction
    WHERE YEAR(date) = @year  
    GROUP BY customerno
    HAVING 
    DATEDIFF(DAY, MIN(Date), MAX(Date)) / NULLIF(COUNT(*) - 1, 0) > 0)

SELECT 
    CustomerNo,
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
FROM rfm_data;

---
select * from #rfm_scores

SELECT rfm_score,
  CASE 
        -- Champions
        WHEN rfm_score IN ('555', '554', '544', '545', '454', '455', '445') THEN 'Champions'
        -- Loyal Customers
        WHEN Rfm_score IN ('543', '444', '435', '355', '354', '345', '344', '335') THEN 'Loyal'
        -- Potential Loyalist
        WHEN Rfm_score IN ('553', '551', '552', '541', '542', '533', '532', '531', '452', '451', '442', '441', '431', '453', '433', '432', '423', '353', '352', '351', '342', '341', '333', '323') THEN 'Potential Loyalist'
        -- New Customers
        WHEN Rfm_score IN ('512', '511', '422', '421', '412', '411', '311') THEN 'New Customers'
        -- Promising
        WHEN Rfm_score IN ('525', '524', '523', '522', '521', '515', '514', '513', '425', '424', '413', '414', '415', '315', '314', '313') THEN 'Promising'
        -- Need Attention
        WHEN Rfm_score IN ('535', '534', '443', '434', '343', '334', '325', '324') THEN 'Need Attention'
        -- About to Sleep
        WHEN Rfm_score IN ('331', '321', '312', '221', '213', '231', '241', '251') THEN 'About to Sleep'
        -- Cannot Lose Them But Losing
        WHEN Rfm_score IN ('155', '154', '144', '214', '215', '115', '114', '113') THEN 'Cannot Lose Them But Losing'
        -- At Risk
        WHEN Rfm_score IN ('255', '254', '245', '244', '253', '252', '243', '242', '235', '234', '225', '224', '153', '152', '145', '143', '142', '135', '134', '133', '125', '124') THEN 'At Risk'
        -- Hibernating
        WHEN Rfm_score IN ('332', '322', '233', '232', '223', '222', '132', '123', '122', '212', '211') THEN 'Hibernating'
        -- Lost Customers
        WHEN Rfm_score IN ('111', '112', '121', '131', '141', '151') THEN 'Lost Customers'
        ELSE 'Unclassified'
 END AS rfm_segment
into #rfm_segment
FROM #rfm_scores










select distinct sc.CustomerNo , rs.rfm_score, rs.rfm_segment
from #rfm_segment  rs inner join #rfm_scores sc on rs.rfm_score=sc.rfm_score


SELECT 
    rs.rfm_segment,
    COUNT(DISTINCT r.CustomerNo) AS num_customers
   -- STRING_AGG(r.rfm_score, ', ') AS rfm_scores  
FROM #rfm_scores r
JOIN #rfm_segment rs ON r.rfm_score = rs.rfm_score
GROUP BY rs.rfm_segment
ORDER BY num_customers DESC;


-- Number customers by each rfm_score and total customers each rfm_segment 

SELECT 
    rs.rfm_segment,
    r.rfm_score,
    COUNT(DISTINCT r.CustomerNo) AS num_customers,
    SUM(COUNT(DISTINCT r.CustomerNo)) OVER (PARTITION BY rs.rfm_segment) AS total_segment_customers
FROM #rfm_scores r
JOIN #rfm_segment rs ON r.rfm_score = rs.rfm_score
GROUP BY rs.rfm_segment, r.rfm_score
ORDER BY rs.rfm_segment, num_customers DESC;
