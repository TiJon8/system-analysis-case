-- Расчет конверсии платежей по методам оплаты
WITH payment_stats AS (
    SELECT 
        payment_method,
        status,
        COUNT(*) AS total_count,
        SUM(amount) AS total_amount
    FROM payments
    WHERE created_at >= NOW() - INTERVAL '30 days'
    GROUP BY payment_method, status
)
SELECT 
    payment_method,
    status,
    total_count,
    total_amount,
    ROUND(
        (total_count::NUMERIC / SUM(total_count) OVER (PARTITION BY payment_method)) * 100, 2
    ) AS status_percentage_by_method
FROM payment_stats
ORDER BY payment_method, status;

-- Поиск зависших транзакций
SELECT 
    p.payment_id,
    p.user_id,
    p.amount,
    p.status,
    EXTRACT(EPOCH FROM (NOW() - p.updated_at))/60 AS minutes_in_status
FROM payments p
WHERE p.status IN ('PENDING', 'PROCESSING')
  AND p.updated_at < NOW() - INTERVAL '15 minutes'
ORDER BY p.updated_at ASC;