import { Router } from 'express'
import { databaseErrorMessage, pool } from './db.js'

export const storesRouter = Router()

const CITY_SCHEMA = {
  Karachi: 'karachi',
  Lahore: 'lahore',
}

storesRouter.use((req, res, next) => {
  const user = req.session.user
  if (!user) {
    res.status(401).json({ error: 'Not signed in.' })
    return
  }
  if (user.role !== 'Super Admin') {
    res.status(403).json({ error: 'Only a super admin can change stores.' })
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

function readStore(body) {
  const code = String(body?.code ?? '').trim().toUpperCase()
  const name = String(body?.name ?? '').trim().replace(/\s+/g, ' ')
  const cityId = Number(body?.cityId)

  if (!/^[A-Z0-9]+(?:-[A-Z0-9]+)*$/.test(code) || code.length > 50) {
    throw badRequest('Enter a store code using letters, numbers, and hyphens.')
  }
  if (!name || name.length > 100) {
    throw badRequest('Enter a store name.')
  }
  if (!Number.isInteger(cityId) || cityId <= 0) {
    throw badRequest('Pick Karachi or Lahore.')
  }

  return { code, name, cityId }
}

function mapStore(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    cityId: row.city_id,
    city: row.city_name,
  }
}

async function cityById(cityId) {
  const result = await pool.query(
    'SELECT id, name FROM central.cities WHERE id = $1',
    [cityId],
  )
  const city = result.rows[0]
  if (!city || !CITY_SCHEMA[city.name]) throw badRequest('Pick Karachi or Lahore.')
  return city
}

async function copyIn(schema, storeId) {
  const sql = schema === 'karachi'
    ? 'SELECT name, code, city_id FROM karachi.stores WHERE id = $1'
    : 'SELECT name, code, city_id FROM lahore.stores WHERE id = $1'
  const result = await pool.query(sql, [storeId])
  return result.rows
}

async function withCityCopy(storeId) {
  const result = await pool.query(
    `
      SELECT s.id, s.name, s.code, s.city_id, c.name AS city_name
      FROM central.stores s
      JOIN central.cities c ON c.id = s.city_id
      WHERE s.id = $1
    `,
    [storeId],
  )
  const store = result.rows[0]
  if (!store) {
    const error = new Error('That store is not on file.')
    error.status = 404
    throw error
  }

  const home = CITY_SCHEMA[store.city_name]
  const other = home === 'karachi' ? 'lahore' : 'karachi'
  const [homeRows, otherRows] = await Promise.all([
    copyIn(home, storeId),
    copyIn(other, storeId),
  ])
  const copy = homeRows[0]
  const matched = copy
    && copy.name === store.name
    && copy.code === store.code
    && copy.city_id === store.city_id
    && otherRows.length === 0
  if (!matched) {
    const error = new Error(`The store was saved, but the ${store.city_name} copy does not match.`)
    error.status = 500
    throw error
  }
  return store
}

function writeError(err) {
  if (err.code === '23505') return badRequest('That store code is already in use.')
  if (err.code === '23503') return badRequest('Pick Karachi or Lahore.')
  return err
}

storesRouter.get('/', asyncRoute(async (req, res) => {
  const [stores, cities] = await Promise.all([
    pool.query(`
      SELECT s.id, s.code, s.name, s.city_id, c.name AS city_name
      FROM central.stores s
      JOIN central.cities c ON c.id = s.city_id
      ORDER BY c.name, s.name
    `),
    pool.query(`
      SELECT id, name
      FROM central.cities
      WHERE name IN ('Karachi', 'Lahore')
      ORDER BY name
    `),
  ])
  res.json({
    stores: stores.rows.map(mapStore),
    cities: cities.rows,
  })
}))

storesRouter.post('/', asyncRoute(async (req, res) => {
  const input = readStore(req.body)
  const city = await cityById(input.cityId)
  let storeId
  try {
    const inserted = await pool.query(
      `
        INSERT INTO central.stores (code, name, city_id, created_by, updated_by)
        VALUES ($1, $2, $3, $4, $4)
        RETURNING id
      `,
      [input.code, input.name, input.cityId, req.session.user.id],
    )
    storeId = inserted.rows[0].id
  } catch (err) {
    throw writeError(err)
  }

  const saved = await withCityCopy(storeId)
  res.status(201).json({ store: mapStore({ ...saved, city_name: city.name }) })
}))

storesRouter.patch('/:id', asyncRoute(async (req, res) => {
  const storeId = Number(req.params.id)
  if (!Number.isInteger(storeId) || storeId <= 0) {
    throw badRequest('That store is not on file.')
  }
  const input = readStore(req.body)
  const city = await cityById(input.cityId)
  try {
    const updated = await pool.query(
      `
        UPDATE central.stores
        SET code = $1,
            name = $2,
            city_id = $3,
            updated_by = $4,
            updated_at = now()
        WHERE id = $5
        RETURNING id
      `,
      [input.code, input.name, input.cityId, req.session.user.id, storeId],
    )
    if (!updated.rows[0]) {
      const error = new Error('That store is not on file.')
      error.status = 404
      throw error
    }
  } catch (err) {
    throw writeError(err)
  }

  const saved = await withCityCopy(storeId)
  res.json({ store: mapStore({ ...saved, city_name: city.name }) })
}))
