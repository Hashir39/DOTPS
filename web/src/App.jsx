import { useEffect, useState } from 'react'
import { request } from './api.js'
import Office from './Office.jsx'
import StoreDesk from './StoreDesk.jsx'

function placeLabel(user) {
  if (user.storeName) {
    return user.city ? `${user.storeName} · ${user.city}` : user.storeName
  }
  return 'Head office · all cities'
}

export default function App() {
  const [phase, setPhase] = useState('checking')
  const [user, setUser] = useState(null)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    let cancelled = false
    request('/api/me')
      .then((data) => {
        if (cancelled) return
        setUser(data.user)
        setPhase('ready')
      })
      .catch((err) => {
        if (cancelled) return
        if (err.status !== 401) setError(err.message)
        setPhase('ready')
      })
    return () => {
      cancelled = true
    }
  }, [])

  async function onSubmit(event) {
    event.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      const data = await request('/api/login', {
        method: 'POST',
        body: JSON.stringify({ username, password }),
      })
      setUser(data.user)
      setPassword('')
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  async function onLogout() {
    setError('')
    setSubmitting(true)
    try {
      await request('/api/logout', { method: 'POST' })
      setUser(null)
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  if (phase === 'ready' && user?.storeId) {
    return <StoreDesk user={user} onLogout={onLogout} />
  }

  if (phase === 'ready' && user && (user.role === 'Super Admin' || user.role === 'Accountant')) {
    return <Office user={user} onLogout={onLogout} />
  }

  return (
    <main className="screen">
      <section className="intro">
        <p className="brand">POS Mart</p>
        <h1>Sign in to your store</h1>
        <p className="lede">
          Checkout for Karachi and Lahore. Your store decides the city. You do not pick a database.
        </p>
      </section>

      <section className="panel" aria-live="polite">
        {phase === 'checking' && <p className="muted">Checking your session…</p>}

        {phase === 'ready' && user && (
          <div className="session">
            <p className="eyebrow">Signed in</p>
            <h2>{user.fullName || user.username}</h2>
            <dl>
              <div>
                <dt>Role</dt>
                <dd>{user.role}</dd>
              </div>
              <div>
                <dt>Place</dt>
                <dd>{placeLabel(user)}</dd>
              </div>
              <div>
                <dt>Username</dt>
                <dd>{user.username}</dd>
              </div>
            </dl>
            <p className="muted">This account has no store, so the register stays closed.</p>
            {error && <p className="error" role="alert">{error}</p>}
            <button type="button" onClick={onLogout} disabled={submitting}>
              {submitting ? 'Signing out…' : 'Sign out'}
            </button>
          </div>
        )}

        {phase === 'ready' && !user && (
          <form onSubmit={onSubmit}>
            <label htmlFor="username">Username</label>
            <input
              id="username"
              name="username"
              autoComplete="username"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              required
            />

            <label htmlFor="password">Password</label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
            />

            {error && <p className="error" role="alert">{error}</p>}

            <button type="submit" disabled={submitting}>
              {submitting ? 'Signing in…' : 'Sign in'}
            </button>
            <p className="hint">
              Register: <span>khinnz01.cashier1</span> / <span>Demo@12345</span>.
              Lahore: <span>lheglb01.cashier1</span> / <span>Demo@12345</span>.
              Stock: <span>khinnz01.stock</span> / <span>Demo@12345</span>.
              Head office: <span>hq.admin</span> / <span>Demo@12345</span>.
            </p>
          </form>
        )}
      </section>
    </main>
  )
}
