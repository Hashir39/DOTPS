import pg from 'pg'

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
})

pool.on('error', (err) => {
  console.error('Postgres pool error:', err.message)
})

const LOGIN_SQL = `
  SELECT
    u.id,
    u.username,
    u.full_name,
    u.email,
    r.role_name,
    u.store_id,
    s.name AS store_name,
    s.code AS store_code,
    c.name AS city_name
  FROM central.users u
  JOIN central.roles r ON r.id = u.role_id
  LEFT JOIN central.stores s ON s.id = u.store_id
  LEFT JOIN central.cities c ON c.id = s.city_id
  WHERE lower(u.username) = $1
    AND u.password_hash = public.crypt($2::text, u.password_hash)
`

export async function findUserByPassword(username, password) {
  const result = await pool.query(LOGIN_SQL, [username, password])
  const row = result.rows[0]
  if (!row) return null

  return {
    id: row.id,
    username: row.username,
    fullName: row.full_name,
    email: row.email,
    role: row.role_name,
    storeId: row.store_id,
    storeName: row.store_name,
    storeCode: row.store_code,
    city: row.city_name,
  }
}

export function databaseErrorMessage(err) {
  if (err.code === '42883') {
    return 'pgcrypto is missing. Run schema_level.sql before signing in.'
  }
  if (err.code === '42P01' || err.code === '3F000') {
    return 'The pos_ddb tables are missing. Run schema_level.sql, then seed_realistic_data.sql.'
  }
  if (err.code === '3D000') {
    return 'Database pos_ddb does not exist. Run schema_level.sql first.'
  }
  if (err.code === '28P01' || err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND') {
    return 'Cannot reach PostgreSQL. Check DATABASE_URL in server/.env.'
  }
  return 'Cannot reach the database. Check that PostgreSQL is running and pos_ddb is loaded.'
}
