import { Router } from 'express'
import { databaseErrorMessage, pool } from './db.js'

export const usersRouter = Router()

const HEAD_OFFICE = new Set(['Super Admin', 'Accountant'])
const STORE_ROLES = new Set(['Cashier', 'Inventory Clerk', 'Store Manager'])

usersRouter.use((req, res, next) => {
  const user = req.session.user
  if (!user) {
    res.status(401).json({ error: 'Not signed in.' })
    return
  }
  if (user.role !== 'Super Admin') {
    res.status(403).json({ error: 'Only a super admin can change users.' })
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

function readPerson(body, { passwordRequired }) {
  const username = String(body?.username ?? '').trim().toLowerCase()
  const fullName = String(body?.fullName ?? '').trim().replace(/\s+/g, ' ')
  const email = String(body?.email ?? '').trim().toLowerCase()
  const password = String(body?.password ?? '')
  const roleId = Number(body?.roleId)
  const rawStore = body?.storeId
  const storeId = rawStore === null || rawStore === undefined || rawStore === ''
    ? null
    : Number(rawStore)

  if (!/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(username) || username.length > 150) {
    throw badRequest('Enter a username using letters, numbers, dots, and hyphens.')
  }
  if (!fullName || fullName.length > 100) {
    throw badRequest('Enter the person\'s name.')
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 150) {
    throw badRequest('Enter an email address.')
  }
  if (passwordRequired || password) {
    if (password.length < 8 || password.length > 72) {
      throw badRequest('Enter a password of 8 to 72 characters.')
    }
  }
  if (!Number.isInteger(roleId) || roleId <= 0) {
    throw badRequest('Pick a role.')
  }
  if (storeId !== null && (!Number.isInteger(storeId) || storeId <= 0)) {
    throw badRequest('Pick a store.')
  }

  return { username, fullName, email, password, roleId, storeId }
}

async function roleById(roleId) {
  const result = await pool.query(
    'SELECT id, role_name FROM central.roles WHERE id = $1',
    [roleId],
  )
  const role = result.rows[0]
  if (!role || (!HEAD_OFFICE.has(role.role_name) && !STORE_ROLES.has(role.role_name))) {
    throw badRequest('Pick a role from the list.')
  }
  return {
    id: role.id,
    name: role.role_name,
    needsStore: STORE_ROLES.has(role.role_name),
  }
}

async function storeFor(role, storeId) {
  if (!role.needsStore) {
    if (storeId !== null) throw badRequest('Head office roles have no store.')
    return null
  }
  if (storeId === null) throw badRequest('Pick a store. The store decides the city.')
  const result = await pool.query(
    `
      SELECT s.id, s.name, c.name AS city
      FROM central.stores s
      JOIN central.cities c ON c.id = s.city_id
      WHERE s.id = $1
    `,
    [storeId],
  )
  if (!result.rows[0]) throw badRequest('Pick a store from the list.')
  return result.rows[0]
}

function mapUser(row) {
  return {
    id: row.id,
    username: row.username,
    fullName: row.full_name,
    email: row.email,
    roleId: row.role_id,
    role: row.role_name,
    storeId: row.store_id,
    storeName: row.store_name,
    city: row.city_name,
  }
}

async function loadUser(userId) {
  const result = await pool.query(
    `
      SELECT
        u.id, u.username, u.full_name, u.email, u.role_id, u.store_id,
        r.role_name, s.name AS store_name, c.name AS city_name
      FROM central.users u
      JOIN central.roles r ON r.id = u.role_id
      LEFT JOIN central.stores s ON s.id = u.store_id
      LEFT JOIN central.cities c ON c.id = COALESCE(s.city_id, u.city_id)
      WHERE u.id = $1
    `,
    [userId],
  )
  if (!result.rows[0]) {
    const error = new Error('That person is not on file.')
    error.status = 404
    throw error
  }
  return mapUser(result.rows[0])
}

function writeError(err) {
  if (err.code === '23505') {
    if (String(err.constraint || '').includes('email')) {
      return badRequest('That email is already in use.')
    }
    return badRequest('That username is already in use.')
  }
  if (err.code === '23503') return badRequest('Pick a role and store from the lists.')
  return err
}

usersRouter.get('/', asyncRoute(async (req, res) => {
  const [people, roles, stores] = await Promise.all([
    pool.query(`
      SELECT
        u.id, u.username, u.full_name, u.email, u.role_id, u.store_id,
        r.role_name, s.name AS store_name, c.name AS city_name
      FROM central.users u
      JOIN central.roles r ON r.id = u.role_id
      LEFT JOIN central.stores s ON s.id = u.store_id
      LEFT JOIN central.cities c ON c.id = COALESCE(s.city_id, u.city_id)
      ORDER BY u.username
    `),
    pool.query(`
      SELECT id, role_name
      FROM central.roles
      WHERE role_name IN ('Super Admin', 'Accountant', 'Store Manager', 'Cashier', 'Inventory Clerk')
      ORDER BY role_name
    `),
    pool.query(`
      SELECT s.id, s.name, s.code, c.name AS city
      FROM central.stores s
      JOIN central.cities c ON c.id = s.city_id
      ORDER BY c.name, s.name
    `),
  ])
  res.json({
    users: people.rows.map(mapUser),
    roles: roles.rows.map((role) => ({
      id: role.id,
      name: role.role_name,
      needsStore: STORE_ROLES.has(role.role_name),
    })),
    stores: stores.rows,
  })
}))

usersRouter.post('/', asyncRoute(async (req, res) => {
  const input = readPerson(req.body, { passwordRequired: true })
  const role = await roleById(input.roleId)
  await storeFor(role, input.storeId)
  let userId
  try {
    const inserted = await pool.query(
      `
        INSERT INTO central.users
          (username, email, password_hash, full_name, role_id, store_id, created_by, updated_by)
        VALUES
          ($1, $2, public.crypt($3, public.gen_salt('bf', 6)), $4, $5, $6, $7, $7)
        RETURNING id
      `,
      [
        input.username,
        input.email,
        input.password,
        input.fullName,
        role.id,
        input.storeId,
        req.session.user.id,
      ],
    )
    userId = inserted.rows[0].id
  } catch (err) {
    throw writeError(err)
  }
  res.status(201).json({ user: await loadUser(userId) })
}))

usersRouter.patch('/:id', asyncRoute(async (req, res) => {
  const userId = Number(req.params.id)
  if (!Number.isInteger(userId) || userId <= 0) {
    throw badRequest('That person is not on file.')
  }
  const input = readPerson(req.body, { passwordRequired: false })
  const role = await roleById(input.roleId)
  await storeFor(role, input.storeId)

  const existing = await pool.query(
    'SELECT id, role_id FROM central.users WHERE id = $1',
    [userId],
  )
  if (!existing.rows[0]) {
    const error = new Error('That person is not on file.')
    error.status = 404
    throw error
  }
  if (req.session.user.id === userId && existing.rows[0].role_id !== role.id) {
    throw badRequest('You cannot change your own role.')
  }

  try {
    if (input.password) {
      await pool.query(
        `
          UPDATE central.users
          SET username = $1,
              email = $2,
              full_name = $3,
              role_id = $4,
              store_id = $5,
              password_hash = public.crypt($6, public.gen_salt('bf', 6)),
              updated_by = $7,
              updated_at = now()
          WHERE id = $8
        `,
        [
          input.username,
          input.email,
          input.fullName,
          role.id,
          input.storeId,
          input.password,
          req.session.user.id,
          userId,
        ],
      )
    } else {
      await pool.query(
        `
          UPDATE central.users
          SET username = $1,
              email = $2,
              full_name = $3,
              role_id = $4,
              store_id = $5,
              updated_by = $6,
              updated_at = now()
          WHERE id = $7
        `,
        [
          input.username,
          input.email,
          input.fullName,
          role.id,
          input.storeId,
          req.session.user.id,
          userId,
        ],
      )
    }
  } catch (err) {
    throw writeError(err)
  }

  res.json({ user: await loadUser(userId) })
}))
