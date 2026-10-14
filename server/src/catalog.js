import { Router } from 'express'
import { databaseErrorMessage, pool } from './db.js'

export const catalogRouter = Router()

catalogRouter.use((req, res, next) => {
  const user = req.session.user
  if (!user) {
    res.status(401).json({ error: 'Not signed in.' })
    return
  }
  if (user.role !== 'Super Admin') {
    res.status(403).json({ error: 'Only a super admin can change the catalog.' })
    return
  }
  next()
})

function asyncRoute(fn) {
  return (req, res) => {
    Promise.resolve(fn(req, res)).catch((err) => {
      if (err.status) {
        res.status(err.status).json({ error: err.message })
        return
      }
      console.error(err)
      res.status(500).json({ error: databaseErrorMessage(err) })
    })
  }
}

function badRequest(message) {
  const error = new Error(message)
  error.status = 400
  return error
}

function readProduct(body) {
  const sku = String(body?.sku ?? '').trim().toUpperCase()
  const name = String(body?.name ?? '').trim().replace(/\s+/g, ' ')
  const priceText = String(body?.price ?? '').trim()
  const categoryId = Number(body?.categoryId)

  if (!/^[A-Z0-9]+(?:-[A-Z0-9]+)*$/.test(sku) || sku.length > 100) {
    throw badRequest('Enter a SKU using letters, numbers, and hyphens.')
  }
  if (!name || name.length > 150) {
    throw badRequest('Enter a product name.')
  }
  if (!/^\d+(\.\d{1,2})?$/.test(priceText) || Number(priceText) > 9999999.99) {
    throw badRequest('Enter a price of zero or more, with at most two decimal places.')
  }
  if (!Number.isInteger(categoryId) || categoryId <= 0) {
    throw badRequest('Pick a category.')
  }

  return { sku, name, priceText, categoryId }
}

function mapProduct(row) {
  return {
    id: row.id,
    sku: row.sku,
    name: row.name,
    price: row.price,
    categoryId: row.category_id,
    categoryName: row.category_name,
  }
}

async function categoryName(categoryId) {
  const result = await pool.query(
    'SELECT name FROM central.categories WHERE id = $1',
    [categoryId],
  )
  if (!result.rows[0]) throw badRequest('Pick a category from the list.')
  return result.rows[0].name
}

async function withCityCopies(productId) {
  const result = await pool.query(
    `
      SELECT id, sku, name, price, category_id
      FROM central.products
      WHERE id = $1
    `,
    [productId],
  )
  const product = result.rows[0]
  if (!product) {
    const error = new Error('That product is not in the catalog.')
    error.status = 404
    throw error
  }

  const copies = await pool.query(
    `
      SELECT sku, name, price, category_id FROM karachi.products WHERE id = $1
      UNION ALL
      SELECT sku, name, price, category_id FROM lahore.products WHERE id = $1
    `,
    [productId],
  )
  const matched = copies.rows.filter((row) => (
    row.sku === product.sku
    && row.name === product.name
    && Number(row.price) === Number(product.price)
    && row.category_id === product.category_id
  ))
  if (matched.length !== 2) {
    const error = new Error('The product was saved, but a city copy does not match.')
    error.status = 500
    throw error
  }
  return product
}

function writeError(err) {
  if (err.code === '23505') return badRequest('That SKU is already in the catalog.')
  if (err.code === '23503') return badRequest('Pick a category from the list.')
  if (err.code === '23514') return badRequest('Price must be zero or more.')
  return err
}

catalogRouter.get('/categories', asyncRoute(async (req, res) => {
  const result = await pool.query(
    'SELECT id, name FROM central.categories ORDER BY name',
  )
  res.json({ categories: result.rows })
}))

catalogRouter.get('/products', asyncRoute(async (req, res) => {
  const result = await pool.query(`
    SELECT p.id, p.sku, p.name, p.price, p.category_id, c.name AS category_name
    FROM central.products p
    LEFT JOIN central.categories c ON c.id = p.category_id
    ORDER BY p.name
  `)
  res.json({ products: result.rows.map(mapProduct) })
}))

catalogRouter.post('/products', asyncRoute(async (req, res) => {
  const input = readProduct(req.body)
  const category = await categoryName(input.categoryId)
  let productId
  try {
    const inserted = await pool.query(
      `
        INSERT INTO central.products (sku, name, category_id, price, created_by, updated_by)
        VALUES ($1, $2, $3, $4::numeric, $5, $5)
        RETURNING id
      `,
      [input.sku, input.name, input.categoryId, input.priceText, req.session.user.id],
    )
    productId = inserted.rows[0].id
  } catch (err) {
    throw writeError(err)
  }

  const saved = await withCityCopies(productId)
  res.status(201).json({
    product: mapProduct({ ...saved, category_name: category }),
  })
}))

catalogRouter.patch('/products/:id', asyncRoute(async (req, res) => {
  const productId = Number(req.params.id)
  if (!Number.isInteger(productId) || productId <= 0) {
    throw badRequest('That product is not in the catalog.')
  }
  const input = readProduct(req.body)
  const category = await categoryName(input.categoryId)
  try {
    const updated = await pool.query(
      `
        UPDATE central.products
        SET sku = $1,
            name = $2,
            category_id = $3,
            price = $4::numeric,
            updated_by = $5,
            updated_at = now()
        WHERE id = $6
        RETURNING id
      `,
      [input.sku, input.name, input.categoryId, input.priceText, req.session.user.id, productId],
    )
    if (!updated.rows[0]) {
      const error = new Error('That product is not in the catalog.')
      error.status = 404
      throw error
    }
  } catch (err) {
    throw writeError(err)
  }

  const saved = await withCityCopies(productId)
  res.json({
    product: mapProduct({ ...saved, category_name: category }),
  })
}))
