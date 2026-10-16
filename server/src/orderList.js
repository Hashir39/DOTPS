import { pool } from './db.js'

const SCHEMAS = new Set(['central', 'karachi', 'lahore'])
const PAGE_SIZE = 50

function assertSchema(schema) {
  if (!SCHEMAS.has(schema)) {
    const error = new Error('That city is not available.')
    error.status = 400
    throw error
  }
}

function mapRow(row) {
  return {
    id: row.id,
    trackingCode: row.tracking_code,
    orderDate: row.order_date,
    total: row.total_amount,
    status: row.order_status,
    storeName: row.store_name,
    storeCode: row.store_code,
    city: row.city_name,
    customerName: row.customer_name,
    items: row.bought || '',
  }
}

export async function listOrders(schema, page) {
  assertSchema(schema)
  const safePage = Number.isInteger(page) && page > 0 ? page : 1
  const offset = (safePage - 1) * PAGE_SIZE
  const [count, result] = await Promise.all([
    pool.query(`SELECT count(*)::int AS n FROM ${schema}.orders`),
    pool.query(
      `
        SELECT
          o.id,
          o.tracking_code,
          o.order_date,
          o.total_amount,
          o.status AS order_status,
          s.name AS store_name,
          s.code AS store_code,
          c.name AS city_name,
          cu.name AS customer_name,
          bought.line AS bought
        FROM ${schema}.orders o
        JOIN central.stores s ON s.id = o.store_id
        JOIN central.cities c ON c.id = s.city_id
        LEFT JOIN ${schema}.customers cu ON cu.id = o.customer_id
        LEFT JOIN LATERAL (
          SELECT string_agg(
            COALESCE(p.name, 'Product') || ' × ' || oi.quantity::text,
            ', ' ORDER BY oi.id
          ) AS line
          FROM ${schema}.order_items oi
          LEFT JOIN ${schema}.products p ON p.id = oi.product_id
          WHERE oi.order_id = o.id
        ) bought ON true
        ORDER BY o.id DESC
        LIMIT $1 OFFSET $2
      `,
      [PAGE_SIZE, offset],
    ),
  ])
  return {
    page: safePage,
    pageSize: PAGE_SIZE,
    total: count.rows[0].n,
    orders: result.rows.map(mapRow),
  }
}

export async function orderDetail(schema, orderId) {
  assertSchema(schema)
  const order = await pool.query(
    `
      SELECT
        o.id,
        o.tracking_code,
        o.order_date,
        o.total_amount,
        o.status AS order_status,
        s.name AS store_name,
        s.code AS store_code,
        c.name AS city_name,
        cu.name AS customer_name,
        cu.phone AS customer_phone,
        pay.method AS payment_method,
        pay.status AS payment_status
      FROM ${schema}.orders o
      JOIN central.stores s ON s.id = o.store_id
      JOIN central.cities c ON c.id = s.city_id
      LEFT JOIN ${schema}.customers cu ON cu.id = o.customer_id
      LEFT JOIN LATERAL (
        SELECT method, status
        FROM ${schema}.payments p
        WHERE p.global_order_id = o.global_order_id
        ORDER BY p.id
        LIMIT 1
      ) pay ON true
      WHERE o.id = $1
    `,
    [orderId],
  )
  const row = order.rows[0]
  if (!row) return null

  const items = await pool.query(
    `
      SELECT oi.quantity, oi.price, p.name
      FROM ${schema}.order_items oi
      LEFT JOIN ${schema}.products p ON p.id = oi.product_id
      WHERE oi.order_id = $1
      ORDER BY oi.id
    `,
    [orderId],
  )

  return {
    ...mapRow(row),
    customerPhone: row.customer_phone,
    payment: row.payment_method
      ? { method: row.payment_method, status: row.payment_status }
      : null,
    items: items.rows.map((item) => ({
      name: item.name,
      quantity: item.quantity,
      price: item.price,
    })),
  }
}
