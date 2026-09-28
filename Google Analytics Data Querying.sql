--CHECKING WHAT SOURCES BRING THE MOST TRAFFIC
SELECT
  channelGrouping,
  COUNT(*) AS sessions
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_20170101`
GROUP BY channelGrouping
ORDER BY sessions DESC;

--NO. OF TRANSACTIONS PER CHANNEL AND TOTAL REVENUE 
SELECT
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS total_transactions,
  ROUND(SUM(totals.transactionRevenue) / 1000000, 2) AS total_revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_20170101`
GROUP BY channelGrouping
ORDER BY total_revenue_usd DESC;

--CONVERSION RATE PER CHANNEL
SELECT
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(CASE WHEN totals.transactions >= 1 THEN 1 ELSE 0 END) AS converted_sessions,
  ROUND(100.0 * SUM(CASE WHEN totals.transactions >= 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_20170101`
GROUP BY channelGrouping
ORDER BY conversion_rate_pct DESC;

--DEVICE CATEGORIES, AVG PAGEVIEWS BY DEVICES AND TOTAL REVENUE GENERATED
SELECT
  device.deviceCategory,
  COUNT(*) AS sessions,
  ROUND(AVG(totals.pageviews), 2) AS avg_pageviews,
  ROUND(SUM(totals.transactionRevenue) / 1000000, 2) AS total_revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_20170101`
GROUP BY device.deviceCategory
ORDER BY sessions DESC;

--SUM OF BOUNCED SESSIONS AND BOUNCE RATE PER CHANNEL
SELECT
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(totals.bounces) AS sum_of_bounced_sessions,
  ROUND(100 * SUM(totals.bounces) / COUNT(*), 2) AS bounce_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_20170101`
GROUP BY channelGrouping
ORDER BY bounce_rate_pct DESC;

--SIMPLE TRAFFIC SOURCE AND MEDIUM VISUALIZATION
SELECT
  trafficSource.source,
  trafficSource.medium,
  COUNT(*) AS sessions
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_20170101`
GROUP BY trafficSource.source, trafficSource.medium
ORDER BY sessions DESC
LIMIT 15;

--AS THE GA SAMPLE DATA IS DIVIDED TABLE PER DAY, TABLE SUFFIX LETS US LOOK AT 30 DAYS ALTOGETHER
SELECT channelGrouping, COUNT(*) AS sessions
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20170101' AND '20170331'
GROUP BY channelGrouping
ORDER BY sessions DESC;

----UNNEST flattens an array into rows, so every session row gets repeated per hit, this made me deduplicate to count sessions
--COUNTING HITS, THE ACTION TYPE IS NOT VERY HUMAN READABLE AFTER SEARCHING GOOGLE I HAVE FOUND EACH MEANING WILL DO A QUERY TO MAKE IT MORE HUMAN READABLE
SELECT
  h.eCommerceAction.action_type AS action_type,
  COUNT(*) AS hit_count
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
  UNNEST(hits) AS h
WHERE _TABLE_SUFFIX BETWEEN '20170101' AND '20170131'
GROUP BY action_type
ORDER BY action_type;

--setting up CTE for purchase funnel, collapsed hit-level data to one row per session with conditional flags, then aggregated the flags into funnel counts
WITH session_steps AS (
  SELECT
    --gluing together visitor id(unique), and visitid,unix timestamp when a user enters a website
    CONCAT(fullVisitorId, '-', CAST(visitId AS STRING)) AS session_id,
    channelGrouping,
    device.deviceCategory AS device_type,
    --query to if the user actually completed the specific action using boolean
    MAX(IF(h.eCommerceAction.action_type = '2', 1, 0)) AS viewed_product,
    MAX(IF(h.eCommerceAction.action_type = '3', 1, 0)) AS added_to_cart,
    MAX(IF(h.eCommerceAction.action_type = '6', 1, 0)) AS purchased
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
    UNNEST(hits) AS h
  WHERE _TABLE_SUFFIX BETWEEN '20170101' AND '20170331'
  GROUP BY session_id, channelGrouping, device_type
)
SELECT
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(viewed_product) AS product_views,
  SUM(added_to_cart)  AS cart_adds,
  SUM(purchased)      AS purchases,
  --using safe divide cuz there is a chance it might be divided by NULL
  ROUND(100 * SAFE_DIVIDE(SUM(added_to_cart), SUM(viewed_product)), 2) AS view_to_cart_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(purchased), SUM(added_to_cart)), 2)      AS cart_to_purchase_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(purchased), COUNT(*)), 2)                AS session_successfully_converted_pct
FROM session_steps
GROUP BY channelGrouping
ORDER BY sessions DESC;


--query of revenue share and rank per channel
--CTE FOR REVENUE PER CHANNEL
WITH rev_per_channel AS (
  SELECT
    channelGrouping,
    COALESCE(SUM(totals.transactionRevenue), 0) / 1000000 AS revenue
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
  WHERE _TABLE_SUFFIX BETWEEN '20170101' AND '20170331'
  GROUP BY channelGrouping
)
SELECT
  channelGrouping,
  ROUND(revenue, 2) AS revenue,
  ROUND(100 * revenue / SUM(revenue) OVER (), 2) AS total_rev_per_channel_pct,
  --WINDOWS FUNCTION (RANK)
  RANK() OVER (ORDER BY revenue DESC) AS rev_rank
FROM rev_per_channel
ORDER BY rev_rank;

--this query requires a second UNNEST, because products are nested inside hits.
SELECT
  p.v2ProductName AS product,
  SUM(p.productQuantity) AS units_sold,
  ROUND(SUM(p.productRevenue) / 1000000, 2) AS revenue
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
--two unnest cuz its session to hits to product attached to hits so unwrapping it
  UNNEST(hits) AS h,
  UNNEST(h.product) AS p
WHERE _TABLE_SUFFIX BETWEEN '20170101' AND '20170331'
  AND h.eCommerceAction.action_type = '6'
  AND p.productRevenue IS NOT NULL
GROUP BY product
ORDER BY revenue DESC
LIMIT 15;