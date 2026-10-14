import { Router } from 'express'
import { databaseErrorMessage, pool } from './db.js'

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

reportsRouter.get('/sales', (req, res) => {
  pool.query(`
    SELECT
      s.product_id,
      s.product_name,
      COALESCE(k.total_sales, 0)::numeric(14,2) AS karachi_sales,
      COALESCE(l.total_sales, 0)::numeric(14,2) AS lahore_sales,
      s.total_sales
    FROM central.product_sales s
    LEFT JOIN (
      SELECT product_id, SUM(quantity * price) AS total_sales
      FROM karachi.order_items
      GROUP BY product_id
    ) k ON k.product_id = s.product_id
    LEFT JOIN (
      SELECT product_id, SUM(quantity * price) AS total_sales
      FROM lahore.order_items
      GROUP BY product_id
    ) l ON l.product_id = s.product_id
    ORDER BY s.total_sales DESC, s.product_name
  `).then((result) => {
    res.json({
      sales: result.rows.map((row) => ({
        productId: row.product_id,
        name: row.product_name,
        karachi: row.karachi_sales,
        lahore: row.lahore_sales,
        total: row.total_sales,
      })),
    })
  }).catch((err) => {
    console.error(err)
    res.status(500).json({ error: databaseErrorMessage(err) })
  })
})
