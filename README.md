### E-commerce Funnel \& Channel Analysis (Google BigQuery)

A purchase-funnel and traffic-channel analysis of a real online store's Google Analytics data, written in BigQuery SQL. It answers the questions a marketing analyst asks about a site: where do visitors drop off, which channels bring buyers, and how does revenue trend?

**Tools:** Google BigQuery (Standard SQL, free sandbox)
**Techniques:** wildcard tables, `UNNEST` (two levels), CTEs, conditional aggregation, window functions (`SUM() OVER`, `RANK`, `LAG`), `SAFE\_DIVIDE`

\---

### Why this project

Marketing teams want to understand better about campaigns using funnel and channel data, and BigQuery is one of the standard tools for it. I wanted experience with the hardest part of Google Analytics data: it is *nested*. Each session contains an array of hits, and each hit can contain an array of products, so counting things correctly takes care.

### Dataset

Google's public **Google Analytics sample dataset** (obfuscated data from the Google Merchandise Store), available in BigQuery as `bigquery-public-data.google\_analytics\_sample.ga\_sessions\_\*`.

* One table per day, covering **1 Aug 2016 to 1 Aug 2017**
* Nested, repeated fields (`hits`, and `hits.product` inside it)
* Money is stored in millionths of a currency unit, so revenue fields are divided by 1,000,000

I queried it directly in BigQuery.

### Questions

1. What kinds of actions happen on the site, and how often?
2. How many *sessions* reach each purchase step (product viewing, add to cart, checkout, purchase)?
3. Which traffic channels and device types convert best, and where does each lose visitors?
4. How is revenue split across channels, and how does it change month to month?
5. Which products earn the most?

### What I did

**1: Query many days at once.** The data is split into one table per day. I used (`ga\_sessions\_\*`) with `\_TABLE\_SUFFIX` to filter date ranges and control how much data each query scans.

**2: Explore hit-level actions with `UNNEST`.** Each session holds an array of hits. `UNNEST(hits)` turns that array into one row per hit, so I could count ecommerce actions. I also labelled the action codes I used: `2` product detail view, `3` add to cart, `5` checkout, `6` completed purchase(info available on google). After `UNNEST`, `COUNT(\*)` counts *hits*, not sessions, so I compared hit counts with distinct session counts to see the difference.

**3: Build the funnel per session.** A CTE collapses hit-level data to one row per session, with a 1/0 flag for each step:

```sql
MAX(IF(h.eCommerceAction.action\_type = '3', 1, 0)) AS added\_to\_cart
```

A session ID is `fullVisitorId` combined with `visitId`, because `visitId` alone is only unique per visitor. Summing the flags gives the number of sessions reaching each step.

**4: Funnel by channel and device.** The same CTE, grouped by `channelGrouping` and `device.deviceCategory`, with step-to-step rates calculated using `SAFE\_DIVIDE` so a zero denominator returns `NULL` instead of an error.

**5: Window functions.** Revenue share and rank by channel (`SUM(revenue) OVER ()`, `RANK()`), and month-over-month revenue change with `LAG()`.

**6 : Top products.** A second `UNNEST` (`hits`, then `hits.product`) filtered to purchase hits, aggregated by product.

## Validation

* The session counts from the funnel query for January 2017 {{matched / did not match, and by how much}} the distinct-session counts from the Stage 2 exploration.

## Limitations

* One store and one year of data (2016 to 2017), so the findings describe this dataset, not e-commerce in general.
* The data is obfuscated, and sessions and channels are defined by Google Analytics.
* Funnel steps are not strictly sequential. A session can record a purchase without a recorded cart add, so a step can occasionally exceed the step before it.
* Item-level and session-level revenue fields can differ, so I treat any cross-check between them as approximate.
* The data shows what happened, not why. It does not identify what caused any drop-off.

## How to reproduce

1. Sign in at [console.cloud.google.com/bigquery](https://console.cloud.google.com/bigquery) with a Google account
2. Open a new query and run the files in `queries/` in order. The dataset is public
3. Check the bytes estimate shown before each run, and adjust the date ranges in `\_TABLE\_SUFFIX` if needed.

## What I learned

* Nested data has to be flattened carefully. After `UNNEST`, rows repeat per hit, so counting sessions needs a session ID and conditional flags.
* The same `COUNT(\*)` can mean different things at different levels of the data.
* Window functions add a calculation to each row without collapsing rows the way `GROUP BY` does.
* Checking a result two independent ways is the fastest way to catch a mistake.

