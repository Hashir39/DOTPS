import { Router } from 'express'
import { databaseErrorMessage, pool } from './db.js'
import { listOrders, orderDetail } from './orderList.js'

export const registerRouter = Router()

const CHECKOUT_ROLES = new Set(['Cashier', 'Store Manager'])
const STOCK_ROLES = new Set(['Inventory Clerk', 'Store Manager'])
const CITY_SCHEMA = {
  Karachi: 'karachi',
  Lahore: 'lahore',
}

function citySchema(user) {
  const schema = CITY_SCHEMA[user.city]
  if (!schema) {
    const error = new Error('This store is not on a city node.')
    error.status = 400
    throw error
  }
  return schema
}

registerRouter.use((req, res, next) => {
  const user = req.session.user
  if (!user) {
    res.status(401).json({ error: 'Not signed in.' })
    return
  }
  if (!user.storeId) {
    res.status(403).json({ error: 'This account has no store.' })
    return
  }
  next()
})

function requireRole(roles, message) {
  return (req, res, next) => {
    if (!roles.has(req.session.user.role)) {
      res.status(403).json({ error: message })
      return
    }
    next()
  }
}

const checkout = requireRole(
  CHECKOUT_ROLES,
  'Only a cashier or store manager can use the register.',
)
const stock = requireRole(
  STOCK_ROLES,
  'Only an inventory clerk or store manager can receive stock.',
)

function likeQuery(value) {
  return `%${String(value).replace(/[\\%_]/g, '\\$&')}%`
}

function asyncRoute(fn) {
  return (req, res) => {
    Promise.resolve(fn(req, res)).catch((err) => {
      if (err.status) {
        res.status(err.status).json({ error: err.message })
        return
      }
      if (err.code === 'P0001') {
        res.status(400).json({ error: err.message })
        return
      }
      console.error(err)
      res.status(500).json({ error: databaseErrorMessage(err) })
    })
  }
}

registerRouter.get('/products', checkout, asyncRoute(async (req, res) => {
  const q = String(req.query.q ?? '').trim()
  const result = await pool.query(
    `
      SELECT
        p.id,
        p.sku,
        p.name,
        p.price,
        COALESCE(i.quantity, 0)::int AS quantity
      FROM central.products p
      LEFT JOIN central.inventory i
        ON i.product_id = p.id
       AND i.store_id = $1
      WHERE $2 = ''
         OR p.name ILIKE $3 ESCAPE '\\'
         OR p.sku ILIKE $3 ESCAPE '\\'
      ORDER BY p.name
      LIMIT 40
    `,
    [req.session.user.storeId, q, likeQuery(q)],
  )
  res.json({ products: result.rows })
}))

registerRouter.get('/customers', checkout, asyncRoute(async (req, res) => {
  const q = String(req.query.q ?? '').trim()
  if (!q) {
    res.json({ customers: [] })
    return
  }
  const result = await pool.query(
    `
      SELECT c.id, c.name, c.phone
      FROM central.customers c
      JOIN central.stores s ON s.city_id = c.city_id
      WHERE s.id = $1
        AND (c.name ILIKE $2 ESCAPE '\\' OR c.phone ILIKE $2 ESCAPE '\\')
      ORDER BY c.name
      LIMIT 8
    `,
    [req.session.user.storeId, likeQuery(q)],
  )
  res.json({ customers: result.rows })
}))

registerRouter.post('/customers', checkout, asyncRoute(async (req, res) => {
  const name = String(req.body?.name ?? '').trim()
  const phone = String(req.body?.phone ?? '').trim()
  if (!name || !phone) {
    res.status(400).json({ error: 'A shopper needs a name and a phone number.' })
    return
  }

  const store = await pool.query(
    'SELECT city_id FROM central.stores WHERE id = $1',
    [req.session.user.storeId],
  )
  const inserted = await pool.query(
    `
      INSERT INTO central.customers (city_id, name, phone, created_by, updated_by)
      VALUES ($1, $2, $3, $4, $4)
      RETURNING id, name, phone
    `,
    [store.rows[0].city_id, name, phone, req.session.user.id],
  )
  res.status(201).json({ customer: inserted.rows[0] })
}))

registerRouter.post('/orders', checkout, asyncRoute(async (req, res) => {
  const customerId = Number(req.body?.customerId)
  const method = String(req.body?.method ?? 'Cash')
  const items = Array.isArray(req.body?.items) ? req.body.items : []

  if (!Number.isInteger(customerId) || customerId <= 0) {
    res.status(400).json({ error: 'Choose a shopper before taking payment.' })
    return
  }
  if (!['Cash', 'Card', 'Online'].includes(method)) {
    res.status(400).json({ error: 'Payment method must be Cash, Card, or Online.' })
    return
  }
  if (items.length === 0) {
    res.status(400).json({ error: 'The cart is empty.' })
    return
  }

  const priced = []
  for (const item of items) {
    const productId = Number(item.productId)
    const quantity = Number(item.quantity)
    if (!Number.isInteger(productId) || productId <= 0 || !Number.isInteger(quantity) || quantity <= 0) {
      res.status(400).json({ error: 'Each item needs a product and a positive quantity.' })
      return
    }
    const product = await pool.query(
      'SELECT id, name, price FROM central.products WHERE id = $1',
      [productId],
    )
    if (!product.rows[0]) {
      res.status(400).json({ error: 'A product in the cart is no longer on the shelf.' })
      return
    }
    priced.push({
      product_id: productId,
      name: product.rows[0].name,
      quantity,
      price: product.rows[0].price,
    })
  }

  const client = await pool.connect()
  try {
    await client.query('BEGIN')
    const placed = await client.query(
      'SELECT central.ProcessOrder($1, $2, $3::jsonb, $4, $5) AS global_order_id',
      [
        req.session.user.storeId,
        customerId,
        JSON.stringify(priced.map(({ product_id, quantity, price }) => ({ product_id, quantity, price }))),
        req.session.user.id,
        method,
      ],
    )
    const order = await client.query(
      `
        SELECT o.total_amount, o.tracking_code, om.store_order_id
        FROM central.orders o
        JOIN central.order_mapping om ON om.global_order_id = o.global_order_id
        WHERE o.global_order_id = $1
      `,
      [placed.rows[0].global_order_id],
    )
    const customer = await client.query(
      'SELECT name, phone FROM central.customers WHERE id = $1',
      [customerId],
    )
    await client.query('COMMIT')

    res.status(201).json({
      receipt: {
        globalOrderId: placed.rows[0].global_order_id,
        storeOrderId: order.rows[0].store_order_id,
        trackingCode: order.rows[0].tracking_code,
        total: order.rows[0].total_amount,
        method,
        customer: customer.rows[0],
        items: priced.map((item) => ({
          name: item.name,
          quantity: item.quantity,
          price: item.price,
        })),
      },
    })
  } catch (err) {
    await client.query('ROLLBACK')
    throw err
  } finally {
    client.release()
  }
}))

const TODAY_SQL = `
  AND (o.order_date AT TIME ZONE 'Asia/Karachi')::date
    = (now() AT TIME ZONE 'Asia/Karachi')::date
`

registerRouter.get('/orders', checkout, asyncRoute(async (req, res) => {
  const schema = citySchema(req.session.user)
  const result = await pool.query(
    `
      SELECT
        o.id,
        o.tracking_code,
        o.order_date,
        o.total_amount,
        o.status AS order_status,
        c.name AS customer_name,
        om.store_order_id,
        pay.method AS payment_method,
        pay.status AS payment_status
      FROM ${schema}.orders o
      LEFT JOIN ${schema}.customers c ON c.id = o.customer_id
      LEFT JOIN central.order_mapping om ON om.global_order_id = o.global_order_id
      LEFT JOIN LATERAL (
        SELECT method, status
        FROM ${schema}.payments p
        WHERE p.global_order_id = o.global_order_id
        ORDER BY p.id
        LIMIT 1
      ) pay ON true
      WHERE o.store_id = $1
      ${TODAY_SQL}
      ORDER BY o.order_date DESC, o.id DESC
    `,
    [req.session.user.storeId],
  )
  res.json({
    orders: result.rows.map((row) => ({
      id: row.id,
      trackingCode: row.tracking_code,
      orderDate: row.order_date,
      total: row.total_amount,
      status: row.payment_status || row.order_status,
      customerName: row.customer_name,
      storeOrderId: row.store_order_id,
      paymentMethod: row.payment_method,
    })),
  })
}))

const cityHistory = requireRole(
  new Set(['Store Manager']),
  'Only a store manager can open this store\'s order list.',
)

function pageNumber(req) {
  const page = Number(req.query.page)
  return Number.isInteger(page) && page > 0 ? page : 1
}

registerRouter.get('/city-orders', cityHistory, asyncRoute(async (req, res) => {
  const user = req.session.user
  res.json(await listOrders(citySchema(user), pageNumber(req), user.storeId))
}))

registerRouter.get('/city-orders/:id', cityHistory, asyncRoute(async (req, res) => {
  const orderId = Number(req.params.id)
  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'That sale number is not valid.' })
    return
  }
  const user = req.session.user
  const order = await orderDetail(citySchema(user), orderId, user.storeId)
  if (!order) {
    res.status(404).json({ error: 'That sale is not at this store.' })
    return
  }
  res.json({ order })
}))

registerRouter.get('/orders/:id', checkout, asyncRoute(async (req, res) => {
  const orderId = Number(req.params.id)
  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'That sale number is not valid.' })
    return
  }

  const schema = citySchema(req.session.user)
  const order = await pool.query(
    `
      SELECT
        o.id,
        o.tracking_code,
        o.order_date,
        o.total_amount,
        o.status AS order_status,
        o.global_order_id,
        c.name AS customer_name,
        c.phone AS customer_phone,
        om.store_order_id,
        pay.method AS payment_method,
        pay.status AS payment_status,
        pay.amount AS payment_amount
      FROM ${schema}.orders o
      LEFT JOIN ${schema}.customers c ON c.id = o.customer_id
      LEFT JOIN central.order_mapping om ON om.global_order_id = o.global_order_id
      LEFT JOIN LATERAL (
        SELECT method, status, amount
        FROM ${schema}.payments p
        WHERE p.global_order_id = o.global_order_id
        ORDER BY p.id
        LIMIT 1
      ) pay ON true
      WHERE o.id = $1
        AND o.store_id = $2
        ${TODAY_SQL}
    `,
    [orderId, req.session.user.storeId],
  )
  if (!order.rows[0]) {
    res.status(404).json({ error: 'That sale is not on this store today.' })
    return
  }

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
  const row = order.rows[0]
  res.json({
    order: {
      id: row.id,
      trackingCode: row.tracking_code,
      orderDate: row.order_date,
      total: row.total_amount,
      status: row.payment_status || row.order_status,
      customerName: row.customer_name,
      customerPhone: row.customer_phone,
      storeOrderId: row.store_order_id,
      payment: row.payment_method
        ? { method: row.payment_method, status: row.payment_status, amount: row.payment_amount }
        : null,
      items: items.rows.map((item) => ({
        name: item.name,
        quantity: item.quantity,
        price: item.price,
      })),
    },
  })
}))

registerRouter.get('/inventory', stock, asyncRoute(async (req, res) => {
  const q = String(req.query.q ?? '').trim()
  const result = await pool.query(
    `
      SELECT
        p.id,
        p.sku,
        p.name,
        p.price,
        COALESCE(i.quantity, 0)::int AS quantity
      FROM central.products p
      LEFT JOIN central.inventory i
        ON i.product_id = p.id
       AND i.store_id = $1
      WHERE $2 = ''
         OR p.name ILIKE $3 ESCAPE '\\'
         OR p.sku ILIKE $3 ESCAPE '\\'
      ORDER BY p.name
      LIMIT 40
    `,
    [req.session.user.storeId, q, likeQuery(q)],
  )
  res.json({ products: result.rows })
}))

registerRouter.post('/inventory/receive', stock, asyncRoute(async (req, res) => {
  const productId = Number(req.body?.productId)
  const quantity = Number(req.body?.quantity)
  if (!Number.isInteger(productId) || productId <= 0) {
    res.status(400).json({ error: 'Choose a product to receive.' })
    return
  }
  if (!Number.isInteger(quantity) || quantity <= 0 || quantity > 10000) {
    res.status(400).json({ error: 'Receive between 1 and 10000 units.' })
    return
  }

  const product = await pool.query(
    'SELECT id, name, price FROM central.products WHERE id = $1',
    [productId],
  )
  if (!product.rows[0]) {
    res.status(400).json({ error: 'That product is not in the catalog.' })
    return
  }

  const updated = await pool.query(
    `
      UPDATE central.inventory
      SET quantity = quantity + $1,
          updated_at = now(),
          updated_by = $2
      WHERE product_id = $3
        AND store_id = $4
      RETURNING quantity
    `,
    [quantity, req.session.user.id, productId, req.session.user.storeId],
  )

  let onHand = updated.rows[0]?.quantity
  if (onHand === undefined) {
    const inserted = await pool.query(
      `
        INSERT INTO central.inventory (
          product_id, store_id, quantity, purchase_price, created_by, updated_by
        )
        VALUES ($1, $2, $3, round($4::numeric * 0.74, 2), $5, $5)
        RETURNING quantity
      `,
      [
        productId,
        req.session.user.storeId,
        quantity,
        product.rows[0].price,
        req.session.user.id,
      ],
    )
    onHand = inserted.rows[0].quantity
  }

  res.json({
    productId,
    name: product.rows[0].name,
    received: quantity,
    quantity: onHand,
  })
}))
