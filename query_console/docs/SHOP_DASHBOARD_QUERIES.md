# Shop dashboard queries

Copy-paste queries for the Lotus console (https://query.ysc.org) that cover the
merch shop: what is sitting in carts, how checkouts convert, revenue, margin,
products, customers and fulfilment. Each query is one panel; the suggested chart
is a hint for the Lotus dashboard widget.

All queries are read-only, single-statement, and have no variables, so they run
as-is. To change a window, edit the interval (`30 days`, `90 days`, ...).

## Definitions used throughout

| Term | Meaning |
|------|---------|
| Purchase | `merch_orders.kind = 'purchase'` (a member paid). `admin_comp` orders are club-paid and only appear in the "Club-paid" section. |
| Checkout started | A purchase order exists. Orders are created `pending` at the payment step. |
| Abandoned | `canceled`, or `pending` for over 24 hours (`StaleOrderWorker` cancels these). |
| Sold | A purchase whose status is **not** `pending`, `canceled` or `refunded`. This includes `failed` (paid, but Printful rejected it and an admin has to act). |
| Refunded | `status = 'refunded'`. Counted in gross, removed from net. |
| Billed | `submitting`, `submitted`, `in_production`, `shipped`, `delivered`: Printful has charged (or will charge) the club. |
| Cost | `COALESCE(printful_cost, estimated_cost)`, the same rule as `Ysc.Merch.Order.cost/1`. |

Money columns are `money_with_currency` composites; `(col).amount` is dollars.
Timestamps are stored as UTC without a zone, so the queries compare against
`now() AT TIME ZONE 'UTC'` and do not depend on the session time zone.

## Cart history comes from the event log

`merch_cart_items` only holds the cart as it is now: a row is deleted when the
member removes the line or when the order is fulfilled. History comes from
`merch_cart_events`, an append-only log written by `Ysc.Merch.Cart`
(`Ysc.Merch.CartEvents`):

| `action` | Written when | `quantity` |
|----------|--------------|------------|
| `added` | Add to cart | units added by that click (after the 25-unit cap) |
| `quantity_set` | Quantity changed on the cart page | the line's new quantity |
| `removed` | Member removes a line, or sets it to 0 | units that were in the line |
| `purchased` | Order fulfilled and the carted line is cleared | units that were in the line |

The log starts on the day the migration is deployed; there is nothing before
that, so section 2 is empty until members use the cart. A `purchased` event
only exists for variants that were in the member's cart when the order was
fulfilled, so it measures "carted lines that were bought", not every sale (use
sections 3 to 5 for sales).

---

## 1. Carts right now

### 1.1 Open carts (KPI row)

Chart: stat tiles.

```sql
-- Open carts right now
WITH carts AS (
  SELECT
    c.user_id,
    SUM(c.quantity) FILTER (WHERE v.available AND p.status = 'active') AS units,
    COALESCE(
      SUM(c.quantity * (v.retail_price).amount)
        FILTER (WHERE v.available AND p.status = 'active'),
      0
    ) AS value,
    SUM(c.quantity) FILTER (WHERE NOT (v.available AND p.status = 'active')) AS blocked_units,
    MAX(c.updated_at) AS last_activity
  FROM merch_cart_items c
  JOIN merch_variants v ON v.id = c.variant_id
  JOIN merch_products p ON p.id = v.product_id
  GROUP BY c.user_id
)
SELECT
  COUNT(*) FILTER (WHERE units > 0) AS open_carts,
  COALESCE(SUM(units), 0) AS purchasable_units,
  COALESCE(SUM(value), 0) AS cart_value_usd,
  ROUND(AVG(value) FILTER (WHERE units > 0), 2) AS avg_cart_value_usd,
  COUNT(*) FILTER (
    WHERE units > 0 AND last_activity < (now() AT TIME ZONE 'UTC') - interval '24 hours'
  ) AS idle_over_24h,
  COUNT(*) FILTER (
    WHERE units > 0 AND last_activity < (now() AT TIME ZONE 'UTC') - interval '7 days'
  ) AS idle_over_7d,
  COALESCE(SUM(blocked_units), 0) AS units_blocked_by_availability
FROM carts
```

### 1.2 How stale are open carts

Chart: bar. Buckets by the cart's most recent add or quantity change.

```sql
-- Open carts by age of last activity
WITH carts AS (
  SELECT
    c.user_id,
    SUM(c.quantity * (v.retail_price).amount) AS value,
    EXTRACT(EPOCH FROM (now() AT TIME ZONE 'UTC') - MAX(c.updated_at)) / 3600 AS idle_hours
  FROM merch_cart_items c
  JOIN merch_variants v ON v.id = c.variant_id
  JOIN merch_products p ON p.id = v.product_id
  WHERE v.available AND p.status = 'active'
  GROUP BY c.user_id
)
SELECT
  CASE
    WHEN idle_hours < 1 THEN '1) under 1 hour'
    WHEN idle_hours < 24 THEN '2) 1-24 hours'
    WHEN idle_hours < 168 THEN '3) 1-7 days'
    WHEN idle_hours < 720 THEN '4) 7-30 days'
    ELSE '5) over 30 days'
  END AS last_activity,
  COUNT(*) AS carts,
  SUM(value) AS cart_value_usd
FROM carts
GROUP BY 1
ORDER BY 1
```

### 1.3 Most carted products

Chart: horizontal bar on `units_in_carts`.

```sql
-- Products sitting in carts
SELECT
  p.name AS product,
  COUNT(DISTINCT c.user_id) AS carts,
  SUM(c.quantity) AS units_in_carts,
  SUM(c.quantity * (v.retail_price).amount) AS value_usd,
  MIN(c.inserted_at)::date AS oldest_add
FROM merch_cart_items c
JOIN merch_variants v ON v.id = c.variant_id
JOIN merch_products p ON p.id = v.product_id
WHERE v.available AND p.status = 'active'
GROUP BY p.id, p.name
ORDER BY units_in_carts DESC, carts DESC
```

### 1.4 Most carted variants (size / color)

Chart: table.

```sql
-- Variants sitting in carts
SELECT
  p.name AS product,
  v.color,
  v.size,
  COUNT(DISTINCT c.user_id) AS carts,
  SUM(c.quantity) AS units_in_carts,
  (v.retail_price).amount AS price_usd
FROM merch_cart_items c
JOIN merch_variants v ON v.id = c.variant_id
JOIN merch_products p ON p.id = v.product_id
WHERE v.available AND p.status = 'active'
GROUP BY p.name, v.id, v.color, v.size, v.retail_price
ORDER BY units_in_carts DESC, carts DESC
LIMIT 25
```

### 1.5 Demand blocked by availability

Chart: table. Carts holding a variant that is sold out, hidden or removed from
Printful: revenue the member can't currently complete.

```sql
-- Carted items that cannot be bought
SELECT
  p.name AS product,
  v.color,
  v.size,
  CASE
    WHEN p.status <> 'active' THEN 'product hidden'
    ELSE 'variant unavailable'
  END AS reason,
  COUNT(DISTINCT c.user_id) AS carts,
  SUM(c.quantity) AS units,
  SUM(c.quantity * (v.retail_price).amount) AS value_usd
FROM merch_cart_items c
JOIN merch_variants v ON v.id = c.variant_id
JOIN merch_products p ON p.id = v.product_id
WHERE NOT v.available OR p.status <> 'active'
GROUP BY p.name, v.id, v.color, v.size, p.status
ORDER BY value_usd DESC
```

### 1.6 Cart interest vs. real sales

Chart: table. A product with many carted units and few sales is a conversion
problem (price, shipping cost, sizing); the reverse is a restock or
promotion candidate.

```sql
-- Carted units vs. units sold, per product
WITH in_carts AS (
  SELECT v.product_id, COUNT(DISTINCT c.user_id) AS carts, SUM(c.quantity) AS units
  FROM merch_cart_items c
  JOIN merch_variants v ON v.id = c.variant_id
  GROUP BY v.product_id
),
sold AS (
  SELECT
    v.product_id,
    SUM(oi.quantity) FILTER (
      WHERE o.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days'
    ) AS units_30d,
    SUM(oi.quantity) AS units_all_time
  FROM merch_order_items oi
  JOIN merch_orders o ON o.id = oi.order_id
  JOIN merch_variants v ON v.id = oi.variant_id
  WHERE o.kind = 'purchase' AND o.status NOT IN ('pending', 'canceled', 'refunded')
  GROUP BY v.product_id
)
SELECT
  p.name AS product,
  p.status,
  COALESCE(ic.carts, 0) AS carts_now,
  COALESCE(ic.units, 0) AS carted_units_now,
  COALESCE(s.units_30d, 0) AS sold_units_30d,
  COALESCE(s.units_all_time, 0) AS sold_units_all_time,
  ROUND(ic.units::numeric / NULLIF(s.units_30d, 0), 2) AS carted_per_sold_30d
FROM merch_products p
LEFT JOIN in_carts ic ON ic.product_id = p.id
LEFT JOIN sold s ON s.product_id = p.id
WHERE p.removed_from_printful_at IS NULL
ORDER BY carted_units_now DESC, sold_units_30d DESC
```

---

## 2. Cart activity over time (event log)

### 2.1 Cart activity per day

Chart: line or stacked bar, last 30 days, zero-filled. `carts_started` is
members who added something that day.

```sql
-- Cart activity per day, last 30 days
WITH days AS (
  SELECT ((now() AT TIME ZONE 'UTC')::date - g) AS day
  FROM generate_series(0, 29) AS g
),
daily AS (
  SELECT
    inserted_at::date AS day,
    COUNT(DISTINCT user_id) FILTER (WHERE action = 'added') AS carts_started,
    COUNT(*) FILTER (WHERE action = 'added') AS add_events,
    COALESCE(SUM(quantity) FILTER (WHERE action = 'added'), 0) AS units_added,
    COALESCE(SUM(quantity) FILTER (WHERE action = 'removed'), 0) AS units_removed,
    COALESCE(SUM(quantity) FILTER (WHERE action = 'purchased'), 0) AS units_purchased
  FROM merch_cart_events
  WHERE inserted_at >= (now() AT TIME ZONE 'UTC')::date - 29
  GROUP BY 1
)
SELECT
  days.day,
  COALESCE(daily.carts_started, 0) AS carts_started,
  COALESCE(daily.add_events, 0) AS add_events,
  COALESCE(daily.units_added, 0) AS units_added,
  COALESCE(daily.units_removed, 0) AS units_removed,
  COALESCE(daily.units_purchased, 0) AS units_purchased
FROM days
LEFT JOIN daily ON daily.day = days.day
ORDER BY days.day
```

### 2.2 Cart-to-purchase funnel, last 30 days (KPI row)

Chart: funnel. Members who added to cart in the window, how many then started a
checkout, and how many paid. A checkout or payment counts only if it came after
the member's first add in the window.

```sql
-- Cart to purchase funnel, last 30 days
WITH adders AS (
  SELECT user_id, MIN(inserted_at) AS first_add
  FROM merch_cart_events
  WHERE action = 'added'
    AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days'
  GROUP BY user_id
),
outcomes AS (
  SELECT
    a.user_id,
    BOOL_OR(o.id IS NOT NULL) AS started_checkout,
    COALESCE(BOOL_OR(o.status NOT IN ('pending', 'canceled')), FALSE) AS paid,
    COALESCE(BOOL_OR(o.status NOT IN ('pending', 'canceled', 'refunded')), FALSE) AS kept
  FROM adders a
  LEFT JOIN merch_orders o
    ON o.user_id = a.user_id
   AND o.kind = 'purchase'
   AND o.inserted_at >= a.first_add
  GROUP BY a.user_id
)
SELECT
  COUNT(*) AS members_added_to_cart,
  COUNT(*) FILTER (WHERE started_checkout) AS started_checkout,
  COUNT(*) FILTER (WHERE paid) AS paid,
  COUNT(*) FILTER (WHERE kept) AS paid_and_not_refunded,
  ROUND(100.0 * COUNT(*) FILTER (WHERE started_checkout) / NULLIF(COUNT(*), 0), 1)
    AS cart_to_checkout_pct,
  ROUND(100.0 * COUNT(*) FILTER (WHERE paid) / NULLIF(COUNT(*), 0), 1)
    AS cart_to_paid_pct
FROM outcomes
```

### 2.3 Add, remove and buy by product

Chart: table or grouped bar. Last 30 days. `removed_pct` is how much of what
was added later came back out; `purchased_pct` is how much was still in the cart
when its order was fulfilled.

```sql
-- Cart activity by product, last 30 days
SELECT
  p.name AS product,
  COUNT(DISTINCT e.user_id) FILTER (WHERE e.action = 'added') AS members_added,
  COALESCE(SUM(e.quantity) FILTER (WHERE e.action = 'added'), 0) AS units_added,
  COALESCE(SUM(e.quantity) FILTER (WHERE e.action = 'removed'), 0) AS units_removed,
  COALESCE(SUM(e.quantity) FILTER (WHERE e.action = 'purchased'), 0) AS units_purchased,
  ROUND(
    100.0 * SUM(e.quantity) FILTER (WHERE e.action = 'removed')
    / NULLIF(SUM(e.quantity) FILTER (WHERE e.action = 'added'), 0),
    1
  ) AS removed_pct,
  ROUND(
    100.0 * SUM(e.quantity) FILTER (WHERE e.action = 'purchased')
    / NULLIF(SUM(e.quantity) FILTER (WHERE e.action = 'added'), 0),
    1
  ) AS purchased_pct
FROM merch_cart_events e
JOIN merch_variants v ON v.id = e.variant_id
JOIN merch_products p ON p.id = v.product_id
WHERE e.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days'
GROUP BY p.id, p.name
ORDER BY units_added DESC
```

### 2.4 Most added variants

Chart: table. Which sizes and colors get carted, last 30 days.

```sql
-- Most added variants, last 30 days
SELECT
  p.name AS product,
  v.color,
  v.size,
  COUNT(DISTINCT e.user_id) AS members,
  SUM(e.quantity) AS units_added
FROM merch_cart_events e
JOIN merch_variants v ON v.id = e.variant_id
JOIN merch_products p ON p.id = v.product_id
WHERE e.action = 'added'
  AND e.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days'
GROUP BY p.name, v.id, v.color, v.size
ORDER BY units_added DESC
LIMIT 25
```

### 2.5 Time from add to purchase

Chart: single stat, or table by product. For each carted line that was bought,
hours from the member's latest add of that variant before the purchase. Last 90
days.

```sql
-- Hours from add to purchase, last 90 days
WITH bought AS (
  SELECT
    e.user_id,
    e.variant_id,
    e.inserted_at AS purchased_at,
    (
      SELECT MAX(a.inserted_at)
      FROM merch_cart_events a
      WHERE a.user_id = e.user_id
        AND a.variant_id = e.variant_id
        AND a.action = 'added'
        AND a.inserted_at <= e.inserted_at
    ) AS added_at
  FROM merch_cart_events e
  WHERE e.action = 'purchased'
    AND e.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
),
gaps AS (
  SELECT EXTRACT(EPOCH FROM (purchased_at - added_at)) / 3600 AS hours
  FROM bought
  WHERE added_at IS NOT NULL
)
SELECT
  COUNT(*) AS purchased_lines,
  ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours))::numeric, 1) AS median_hours,
  ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY hours))::numeric, 1) AS p90_hours,
  ROUND(100.0 * COUNT(*) FILTER (WHERE hours < 1) / NULLIF(COUNT(*), 0), 1)
    AS bought_within_1h_pct
FROM gaps
```

### 2.6 When members add to cart

Chart: heatmap (weekday by hour), last 90 days, Pacific time.

```sql
-- Adds by weekday and hour (Pacific), last 90 days
SELECT
  EXTRACT(ISODOW FROM (e.inserted_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Los_Angeles')::int
    AS weekday_mon1,
  EXTRACT(HOUR FROM (e.inserted_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Los_Angeles')::int
    AS hour,
  COUNT(*) AS add_events,
  COUNT(DISTINCT e.user_id) AS members
FROM merch_cart_events e
WHERE e.action = 'added'
  AND e.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
GROUP BY 1, 2
ORDER BY 1, 2
```

---

## 3. Checkout funnel

### 3.1 Funnel, last 30 days (KPI row)

Chart: stat tiles / funnel. `payment_rate_pct` ignores checkouts still inside
their 24-hour window so a busy afternoon doesn't read as a drop. `refunded` and
`failed_after_payment` are subsets of `paid`, not extra steps.

```sql
-- Checkout funnel, last 30 days
SELECT
  COUNT(*) AS checkouts_started,
  COUNT(*) FILTER (
    WHERE status = 'pending' AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '24 hours'
  ) AS in_progress,
  COUNT(*) FILTER (WHERE status NOT IN ('pending', 'canceled')) AS paid,
  COUNT(*) FILTER (
    WHERE status = 'canceled'
       OR (status = 'pending' AND inserted_at < (now() AT TIME ZONE 'UTC') - interval '24 hours')
  ) AS abandoned,
  COUNT(*) FILTER (WHERE status = 'refunded') AS refunded,
  COUNT(*) FILTER (WHERE status = 'failed') AS failed_after_payment,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE status NOT IN ('pending', 'canceled'))
    / NULLIF(
        COUNT(*) FILTER (
          WHERE NOT (status = 'pending' AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '24 hours')
        ),
        0
      ),
    1
  ) AS payment_rate_pct
FROM merch_orders
WHERE kind = 'purchase'
  AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days'
```

### 3.2 Weekly funnel and abandoned value

Chart: line or stacked bar on `paid` / `abandoned`, last 12 weeks.

```sql
-- Weekly checkout funnel
SELECT
  date_trunc('week', inserted_at)::date AS week,
  COUNT(*) AS checkouts_started,
  COUNT(*) FILTER (WHERE status NOT IN ('pending', 'canceled')) AS paid,
  COUNT(*) FILTER (
    WHERE status = 'canceled'
       OR (status = 'pending' AND inserted_at < (now() AT TIME ZONE 'UTC') - interval '24 hours')
  ) AS abandoned,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE status NOT IN ('pending', 'canceled')) / COUNT(*),
    1
  ) AS payment_rate_pct,
  COALESCE(SUM((total_amount).amount) FILTER (
    WHERE status = 'canceled'
       OR (status = 'pending' AND inserted_at < (now() AT TIME ZONE 'UTC') - interval '24 hours')
  ), 0) AS abandoned_value_usd
FROM merch_orders
WHERE kind = 'purchase'
  AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '12 weeks'
GROUP BY 1
ORDER BY 1
```

### 3.3 Why checkouts end without payment

Chart: bar. `Abandoned checkout` is the sweeper; `Payment canceled` means Stripe
reported the PaymentIntent canceled.

```sql
-- Unpaid checkout outcomes, last 90 days
SELECT
  CASE
    WHEN status = 'pending' THEN 'Still pending after 24h (not yet swept)'
    ELSE COALESCE(failure_reason, 'Canceled, no reason recorded')
  END AS outcome,
  COUNT(*) AS orders,
  SUM((total_amount).amount) AS value_usd
FROM merch_orders
WHERE kind = 'purchase'
  AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
  AND (
    status = 'canceled'
    OR (status = 'pending' AND inserted_at < (now() AT TIME ZONE 'UTC') - interval '24 hours')
  )
GROUP BY 1
ORDER BY orders DESC
```

---

## 4. Revenue and margin

### 4.1 Last 30 days vs. the 30 before (KPI row)

Chart: stat tiles with the two rows as current / previous.

```sql
-- Revenue, last 30 days vs. previous 30
WITH paid AS (
  SELECT
    o.user_id,
    o.status,
    (o.total_amount).amount AS total,
    (o.shipping_amount).amount AS shipping,
    CASE
      WHEN o.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days' THEN 'last_30_days'
      ELSE 'previous_30_days'
    END AS period,
    COALESCE((SELECT SUM(oi.quantity) FROM merch_order_items oi WHERE oi.order_id = o.id), 0) AS units
  FROM merch_orders o
  WHERE o.kind = 'purchase'
    AND o.status NOT IN ('pending', 'canceled')
    AND o.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '60 days'
)
SELECT
  period,
  COUNT(*) FILTER (WHERE status <> 'refunded') AS orders,
  COALESCE(SUM(units) FILTER (WHERE status <> 'refunded'), 0) AS units,
  COALESCE(SUM(total), 0) AS gross_usd,
  COALESCE(SUM(total) FILTER (WHERE status = 'refunded'), 0) AS refunded_usd,
  COALESCE(SUM(total) FILTER (WHERE status <> 'refunded'), 0) AS net_revenue_usd,
  ROUND(AVG(total) FILTER (WHERE status <> 'refunded'), 2) AS avg_order_value_usd,
  ROUND(AVG(units) FILTER (WHERE status <> 'refunded'), 2) AS units_per_order,
  COALESCE(SUM(shipping) FILTER (WHERE status <> 'refunded'), 0) AS shipping_collected_usd,
  COUNT(DISTINCT user_id) FILTER (WHERE status <> 'refunded') AS unique_buyers
FROM paid
GROUP BY period
ORDER BY period
```

### 4.2 Daily net revenue

Chart: line (zero-filled, so quiet days show as zero).

```sql
-- Net revenue per day, last 90 days
WITH days AS (
  SELECT ((now() AT TIME ZONE 'UTC')::date - g) AS day
  FROM generate_series(0, 89) AS g
),
daily AS (
  SELECT
    inserted_at::date AS day,
    COUNT(*) AS orders,
    SUM((total_amount).amount) AS revenue
  FROM merch_orders
  WHERE kind = 'purchase'
    AND status NOT IN ('pending', 'canceled', 'refunded')
    AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
  GROUP BY 1
)
SELECT
  days.day,
  COALESCE(daily.orders, 0) AS orders,
  COALESCE(daily.revenue, 0) AS net_revenue_usd
FROM days
LEFT JOIN daily ON daily.day = days.day
ORDER BY days.day
```

### 4.3 Monthly revenue

Chart: bar on `net_revenue_usd`, line on `orders`.

```sql
-- Net revenue per month
SELECT
  date_trunc('month', o.inserted_at)::date AS month,
  COUNT(*) AS orders,
  SUM((o.total_amount).amount) AS net_revenue_usd,
  ROUND(AVG((o.total_amount).amount), 2) AS avg_order_value_usd,
  SUM((o.shipping_amount).amount) AS shipping_collected_usd
FROM merch_orders o
WHERE o.kind = 'purchase'
  AND o.status NOT IN ('pending', 'canceled', 'refunded')
GROUP BY 1
ORDER BY 1
```

### 4.4 Gross margin by month

Chart: bar on `margin_usd`, line on `margin_pct`. Revenue and cost are both
taken from billed orders only, so the two sides cover the same orders. Revenue
includes the shipping the member paid and cost includes Printful's shipping
charge. `orders_on_estimate` counts orders whose real Printful figure hasn't
arrived yet; those months are provisional.

```sql
-- Gross margin per month (billed purchase orders)
SELECT
  date_trunc('month', inserted_at)::date AS month,
  COUNT(*) AS orders,
  SUM((total_amount).amount) AS revenue_usd,
  SUM((COALESCE(printful_cost, estimated_cost)).amount) AS printful_cost_usd,
  SUM((total_amount).amount) - SUM((COALESCE(printful_cost, estimated_cost)).amount) AS margin_usd,
  ROUND(
    100.0 * (SUM((total_amount).amount) - SUM((COALESCE(printful_cost, estimated_cost)).amount))
    / NULLIF(SUM((total_amount).amount), 0),
    1
  ) AS margin_pct,
  COUNT(*) FILTER (WHERE printful_cost IS NULL) AS orders_on_estimate
FROM merch_orders
WHERE kind = 'purchase'
  AND status IN ('submitting', 'submitted', 'in_production', 'shipped', 'delivered')
GROUP BY 1
ORDER BY 1
```

---

## 5. Products

### 5.1 Top products, last 30 days

Chart: horizontal bar on `revenue_usd`.

```sql
-- Top products by revenue, last 30 days
SELECT
  p.name AS product,
  SUM(oi.quantity) AS units,
  COUNT(DISTINCT o.id) AS orders,
  SUM(oi.quantity * (oi.unit_price).amount) AS revenue_usd,
  ROUND(
    100.0 * SUM(oi.quantity * (oi.unit_price).amount)
    / SUM(SUM(oi.quantity * (oi.unit_price).amount)) OVER (),
    1
  ) AS share_of_item_revenue_pct
FROM merch_order_items oi
JOIN merch_orders o ON o.id = oi.order_id
JOIN merch_variants v ON v.id = oi.variant_id
JOIN merch_products p ON p.id = v.product_id
WHERE o.kind = 'purchase'
  AND o.status NOT IN ('pending', 'canceled', 'refunded')
  AND o.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '30 days'
GROUP BY p.id, p.name
ORDER BY revenue_usd DESC
```

### 5.2 Units sold by size

Chart: bar. Useful for deciding which sizes to keep available. Last 90 days.

```sql
-- Units sold by size, last 90 days
SELECT
  COALESCE(v.size, '(no size)') AS size,
  SUM(oi.quantity) AS units,
  ROUND(100.0 * SUM(oi.quantity) / SUM(SUM(oi.quantity)) OVER (), 1) AS pct_of_units
FROM merch_order_items oi
JOIN merch_orders o ON o.id = oi.order_id
JOIN merch_variants v ON v.id = oi.variant_id
WHERE o.kind = 'purchase'
  AND o.status NOT IN ('pending', 'canceled', 'refunded')
  AND o.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
GROUP BY 1
ORDER BY units DESC
```

### 5.3 Units sold by color

Chart: bar. Last 90 days.

```sql
-- Units sold by color, last 90 days
SELECT
  COALESCE(v.color, '(no color)') AS color,
  SUM(oi.quantity) AS units,
  ROUND(100.0 * SUM(oi.quantity) / SUM(SUM(oi.quantity)) OVER (), 1) AS pct_of_units
FROM merch_order_items oi
JOIN merch_orders o ON o.id = oi.order_id
JOIN merch_variants v ON v.id = oi.variant_id
WHERE o.kind = 'purchase'
  AND o.status NOT IN ('pending', 'canceled', 'refunded')
  AND o.inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
GROUP BY 1
ORDER BY units DESC
```

### 5.4 Catalog health and stale listings

Chart: table. Active products with no recent sale, products that vanished from
Printful, and how many variants are switched off.

```sql
-- Catalog health
WITH variant_stats AS (
  SELECT
    product_id,
    COUNT(*) AS variants,
    COUNT(*) FILTER (WHERE NOT available) AS unavailable_variants
  FROM merch_variants
  GROUP BY product_id
),
sales AS (
  SELECT
    v.product_id,
    MAX(o.inserted_at)::date AS last_sold,
    SUM(oi.quantity) AS units_all_time
  FROM merch_order_items oi
  JOIN merch_orders o ON o.id = oi.order_id
  JOIN merch_variants v ON v.id = oi.variant_id
  WHERE o.kind = 'purchase' AND o.status NOT IN ('pending', 'canceled', 'refunded')
  GROUP BY v.product_id
)
SELECT
  p.name AS product,
  p.status,
  COALESCE(vs.variants, 0) AS variants,
  COALESCE(vs.unavailable_variants, 0) AS unavailable_variants,
  s.last_sold,
  COALESCE(s.units_all_time, 0) AS units_all_time,
  p.synced_at::date AS last_synced,
  p.removed_from_printful_at::date AS removed_from_printful
FROM merch_products p
LEFT JOIN variant_stats vs ON vs.product_id = p.id
LEFT JOIN sales s ON s.product_id = p.id
ORDER BY (p.removed_from_printful_at IS NULL) DESC, s.last_sold ASC NULLS FIRST
```

---

## 6. Customers

### 6.1 New vs. returning buyers per month

Chart: stacked bar.

```sql
-- New vs. returning buyers per month
WITH sold AS (
  SELECT DISTINCT user_id, date_trunc('month', inserted_at) AS month
  FROM merch_orders
  WHERE kind = 'purchase'
    AND user_id IS NOT NULL
    AND status NOT IN ('pending', 'canceled', 'refunded')
),
firsts AS (
  SELECT user_id, MIN(month) AS first_month FROM sold GROUP BY user_id
)
SELECT
  s.month::date AS month,
  COUNT(*) FILTER (WHERE s.month = f.first_month) AS new_buyers,
  COUNT(*) FILTER (WHERE s.month > f.first_month) AS returning_buyers
FROM sold s
JOIN firsts f ON f.user_id = s.user_id
GROUP BY s.month
ORDER BY s.month
```

### 6.2 Repeat purchase rate

Chart: donut. How many members have bought once, twice, or three or more times.

```sql
-- Buyers by number of orders (all time)
WITH buyers AS (
  SELECT user_id, COUNT(*) AS orders, SUM((total_amount).amount) AS spent
  FROM merch_orders
  WHERE kind = 'purchase'
    AND user_id IS NOT NULL
    AND status NOT IN ('pending', 'canceled', 'refunded')
  GROUP BY user_id
)
SELECT
  CASE
    WHEN orders >= 3 THEN '3+ orders'
    WHEN orders = 2 THEN '2 orders'
    ELSE '1 order'
  END AS buyer_type,
  COUNT(*) AS buyers,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_buyers,
  SUM(spent) AS revenue_usd
FROM buyers
GROUP BY 1
ORDER BY 1
```

### 6.3 Where orders ship

Chart: bar or map. Last 90 days.

```sql
-- Orders by destination, last 90 days
SELECT
  country_code,
  COALESCE(state_code, '-') AS state,
  COUNT(*) AS orders,
  SUM((total_amount).amount) AS revenue_usd,
  ROUND(AVG((shipping_amount).amount), 2) AS avg_shipping_usd
FROM merch_orders
WHERE kind = 'purchase'
  AND status NOT IN ('pending', 'canceled', 'refunded')
  AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
GROUP BY 1, 2
ORDER BY orders DESC
LIMIT 20
```

### 6.4 Shipping method mix

Chart: bar. Shows whether shipping price steers members toward the cheapest
option, and what they pay for it.

```sql
-- Shipping method mix, last 90 days
SELECT
  COALESCE(shipping_method, '(none)') AS shipping_method,
  COUNT(*) AS orders,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
  ROUND(AVG((shipping_amount).amount), 2) AS avg_shipping_usd,
  ROUND(
    100.0 * AVG((shipping_amount).amount / NULLIF((total_amount).amount, 0)),
    1
  ) AS shipping_pct_of_order
FROM merch_orders
WHERE kind = 'purchase'
  AND status NOT IN ('pending', 'canceled', 'refunded')
  AND inserted_at >= (now() AT TIME ZONE 'UTC') - interval '90 days'
GROUP BY 1
ORDER BY orders DESC
```

---

## 7. Fulfilment

### 7.1 Orders by status

Chart: bar. `oldest_hours_in_status` is time since the last status change of the
oldest order in that status.

```sql
-- Orders by status
SELECT
  status,
  kind,
  COUNT(*) AS orders,
  ROUND(
    MAX(EXTRACT(EPOCH FROM (now() AT TIME ZONE 'UTC') - updated_at)) / 3600
  ) AS oldest_hours_in_status
FROM merch_orders
GROUP BY status, kind
ORDER BY orders DESC
```

### 7.2 Orders that need attention

Chart: table. Should normally be empty. Thresholds: paid but not accepted by
Printful for 30 minutes, in production for 10 days, shipped past the delivery
estimate, a checkout still `pending` after 24 hours (the sweeper should have
canceled it).

```sql
-- Orders needing attention
WITH o AS (
  SELECT m.*, (now() AT TIME ZONE 'UTC') AS now_utc FROM merch_orders m
),
flagged AS (
  SELECT
    o.*,
    CASE
      WHEN o.status = 'failed' THEN 'Paid, Printful submission failed'
      WHEN o.status IN ('paid', 'submitting') AND o.updated_at < o.now_utc - interval '30 minutes'
        THEN 'Paid, not accepted by Printful'
      WHEN o.status IN ('submitted', 'in_production') AND o.submitted_at < o.now_utc - interval '10 days'
        THEN 'In production over 10 days'
      WHEN o.status = 'shipped' AND o.delivery_estimate_max < o.now_utc::date
        THEN 'Shipped, past delivery estimate'
      WHEN o.status = 'pending' AND o.inserted_at < o.now_utc - interval '24 hours'
        THEN 'Pending checkout not canceled'
    END AS issue
  FROM o
)
SELECT
  reference_id,
  kind,
  status,
  issue,
  ROUND(EXTRACT(EPOCH FROM (now_utc - updated_at)) / 3600) AS hours_in_status,
  (total_amount).amount AS total_usd,
  failure_reason
FROM flagged
WHERE issue IS NOT NULL
ORDER BY hours_in_status DESC
```

### 7.3 Fulfilment speed and on-time delivery

Chart: line or table, per month of order.

```sql
-- Fulfilment speed per month (last 6 months)
WITH shipments AS (
  SELECT
    order_id,
    MIN(shipped_at) AS first_shipped_at,
    MAX(delivered_at) AS delivered_at
  FROM merch_shipments
  WHERE NOT reshipment
  GROUP BY order_id
)
SELECT
  date_trunc('month', o.inserted_at)::date AS month,
  COUNT(*) AS shipped_orders,
  ROUND(AVG(EXTRACT(EPOCH FROM (o.submitted_at - o.inserted_at)) / 3600)::numeric, 1)
    AS hours_order_to_printful,
  ROUND(AVG(EXTRACT(EPOCH FROM (s.first_shipped_at - o.submitted_at)) / 86400)::numeric, 1)
    AS days_printful_to_ship,
  ROUND(AVG(EXTRACT(EPOCH FROM (s.delivered_at - s.first_shipped_at)) / 86400)::numeric, 1)
    AS days_ship_to_delivery,
  ROUND(
    100.0 * COUNT(*) FILTER (
      WHERE s.delivered_at IS NOT NULL AND s.delivered_at::date <= o.delivery_estimate_max
    ) / NULLIF(
      COUNT(*) FILTER (
        WHERE s.delivered_at IS NOT NULL AND o.delivery_estimate_max IS NOT NULL
      ),
      0
    ),
    1
  ) AS on_time_delivery_pct
FROM merch_orders o
JOIN shipments s ON s.order_id = o.id
WHERE o.kind = 'purchase'
  AND o.inserted_at >= date_trunc('month', now() AT TIME ZONE 'UTC') - interval '5 months'
GROUP BY 1
ORDER BY 1
```

---

## 8. Club-paid orders

### 8.1 Club-paid spend by month

Chart: bar. Orders an admin placed (`admin_comp`) cost the club the Printful
charge; this uses the same cost rule as the admin pages.

```sql
-- Club-paid merch spend per month
SELECT
  date_trunc('month', inserted_at)::date AS month,
  COUNT(*) AS orders,
  SUM((COALESCE(printful_cost, estimated_cost)).amount) AS cost_usd,
  COUNT(*) FILTER (WHERE printful_cost IS NULL) AS orders_on_estimate
FROM merch_orders
WHERE kind = 'admin_comp'
  AND status IN ('submitting', 'submitted', 'in_production', 'shipped', 'delivered')
GROUP BY 1
ORDER BY 1
```

### 8.2 Club-paid spend by event

Chart: table. Orders tied to an event, matching the event cost statistics.

```sql
-- Club-paid merch spend per event
SELECT
  e.title AS event,
  COUNT(*) AS orders,
  SUM((COALESCE(o.printful_cost, o.estimated_cost)).amount) AS cost_usd
FROM merch_orders o
JOIN events e ON e.id = o.event_id
WHERE o.kind = 'admin_comp'
  AND o.status IN ('submitting', 'submitted', 'in_production', 'shipped', 'delivered')
GROUP BY e.id, e.title
ORDER BY cost_usd DESC
```
