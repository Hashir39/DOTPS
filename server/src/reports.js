import { Router } from 'express'
import { databaseErrorMessage, pool } from './db.js'
import { listOrders, orderDetail } from './orderList.js'

export const reportsRouter = Router()

const REPORT_ROLES = new Set(['Accountant', 'Super Admin'])

reportsRouter.use((req, res, next) => {
  const user = req.session.user
  if (!user) {
    res.status(401).json({ error: 'Not signed in.' })
    return
  }
  if (!REPORT_ROLES.has(user.role)) {
    res.status(403).json({ error: 'Only head office can open the sales report.' })
    return
  }
  next()
})

const EMPTY_CITY = `
  SELECT NULL::int AS product_id, 0::bigint AS units, 0::numeric AS total_sales
  WHERE false
`

function citySales(schema) {
  return `
    SELECT product_id, SUM(quantity) AS units, SUM(quantity * price) AS total_sales
    FROM ${schema}.order_items
    GROUP BY product_id
  `
}

reportsRouter.get('/sales', (req, res) => {
  const city = req.session.user.city
  const karachiSql = city === 'Lahore' ? EMPTY_CITY : citySales('karachi')
  const lahoreSql = city === 'Karachi' ? EMPTY_CITY : citySales('lahore')

  pool.query(`
    SELECT
      s.product_id,
      s.product_name,
      COALESCE(k.total_sales, 0)::numeric(14,2) AS karachi_sales,
      COALESCE(l.total_sales, 0)::numeric(14,2) AS lahore_sales,
      (COALESCE(k.total_sales, 0) + COALESCE(l.total_sales, 0))::numeric(14,2) AS total_sales,
      (COALESCE(k.units, 0) + COALESCE(l.units, 0))::int AS units_sold
    FROM central.product_sales s
    LEFT JOIN (${karachiSql}) k ON k.product_id = s.product_id
    LEFT JOIN (${lahoreSql}) l ON l.product_id = s.product_id
    ORDER BY total_sales DESC, s.product_name
  `).then((result) => {
    res.json({
      sales: result.rows.map((row) => ({
        productId: row.product_id,
        name: row.product_name,
        karachi: row.karachi_sales,
        lahore: row.lahore_sales,
        total: row.total_sales,
        sold: row.units_sold,
      })),
    })
  }).catch((err) => {
    console.error(err)
    res.status(500).json({ error: databaseErrorMessage(err) })
  })
})

function superAdmin(req, res) {
  if (req.session.user.role === 'Super Admin') return true
  res.status(403).json({ error: 'Only a super admin can open every order.' })
  return false
}

function pageNumber(req) {
  const page = Number(req.query.page)
  return Number.isInteger(page) && page > 0 ? page : 1
}

function orderId(req, res) {
  const id = Number(req.params.id)
  if (!Number.isInteger(id) || id <= 0) {
    res.status(400).json({ error: 'That sale number is not valid.' })
    return null
  }
  return id
}

reportsRouter.get('/orders', (req, res) => {
  if (!superAdmin(req, res)) return
  listOrders('central', pageNumber(req)).then((payload) => {
    res.json(payload)
  }).catch((err) => {
    console.error(err)
    res.status(500).json({ error: databaseErrorMessage(err) })
  })
})

reportsRouter.get('/orders/:id', (req, res) => {
  if (!superAdmin(req, res)) return
  const id = orderId(req, res)
  if (!id) return
  orderDetail('central', id).then((order) => {
    if (!order) {
      res.status(404).json({ error: 'That sale is not on file.' })
      return
    }
    res.json({ order })
  }).catch((err) => {
    console.error(err)
    res.status(500).json({ error: databaseErrorMessage(err) })
  })
})
