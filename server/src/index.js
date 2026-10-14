import 'dotenv/config'
import cors from 'cors'
import express from 'express'
import session from 'express-session'
import { databaseErrorMessage, findUserByPassword, pool } from './db.js'
import { catalogRouter } from './catalog.js'
import { registerRouter } from './register.js'
import { reportsRouter } from './reports.js'
import { storesRouter } from './stores.js'
import { usersRouter } from './users.js'

const app = express()
const port = Number(process.env.PORT || 4000)

app.use(cors({
  origin: 'http://localhost:5173',
  credentials: true,
}))
app.use(express.json())
app.use(session({
  name: 'pos.sid',
  secret: process.env.SESSION_SECRET || 'dev-only-change-me',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: false,
    maxAge: 8 * 60 * 60 * 1000,
  },
}))

app.get('/api/me', (req, res) => {
  if (!req.session.user) {
    res.status(401).json({ error: 'Not signed in.' })
    return
  }
  res.json({ user: req.session.user })
})

app.post('/api/login', async (req, res) => {
  const username = String(req.body?.username ?? '').trim().toLowerCase()
  const password = String(req.body?.password ?? '')

  if (!username || !password) {
    res.status(400).json({ error: 'Username and password are required.' })
    return
  }

  try {
    const user = await findUserByPassword(username, password)
    if (!user) {
      res.status(401).json({ error: 'Invalid username or password.' })
      return
    }

    req.session.regenerate((err) => {
      if (err) {
        res.status(500).json({ error: 'Could not start a session.' })
        return
      }
      req.session.user = user
      res.json({ user })
    })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: databaseErrorMessage(err) })
  }
})

app.post('/api/logout', (req, res) => {
  req.session.destroy(() => {
    res.clearCookie('pos.sid')
    res.status(204).end()
  })
})

app.use('/api/reports', reportsRouter)
app.use('/api/catalog', catalogRouter)
app.use('/api/stores', storesRouter)
app.use('/api/users', usersRouter)
app.use('/api', registerRouter)

app.listen(port, () => {
  console.log(`API listening on http://localhost:${port}`)
  pool.query('SELECT 1').catch((err) => {
    console.error(`Postgres is not ready: ${err.message}`)
  })
})
