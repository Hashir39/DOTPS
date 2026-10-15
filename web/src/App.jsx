import { useEffect, useState } from 'react'
import { request } from './api.js'
import Office from './Office.jsx'
import StoreDesk from './StoreDesk.jsx'

function placeLabel(user) {
  if (user.storeName) {
    return user.city ? `${user.storeName} · ${user.city}` : user.storeName
  }
  if (user.city) return user.city
  return 'Head office · all cities'
}

export default function App() {
  const [phase, setPhase] = useState('checking')
  const [user, setUser] = useState(null)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
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
        <p className="brand">DOTMS</p>
        <p className="brand-full">Distributed OmniCommerce Transaction Processing System</p>
        <img
          className="mart"
          src="/dotms-mart.jpg"
          alt="A stocked grocery aisle"
        />
        <h1>Sign in to your store</h1>
        <p className="lede">
          Checkout for Karachi and Lahore branches.
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
            <div className="password-field">
              <input
                id="password"
                name="password"
                type={showPassword ? 'text' : 'password'}
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required
              />
              <button
                type="button"
                className="view-password"
                aria-pressed={showPassword}
                aria-label={showPassword ? 'Hide password' : 'View password'}
                onClick={() => setShowPassword((current) => !current)}
              >
                {showPassword ? (
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                    <path d="M1 1l22 22" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
                  </svg>
                ) : (
                  <svg viewBox="0 0 24 24" aria-hidden="true">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                    <circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" strokeWidth="1.8" />
                  </svg>
                )}
              </button>
            </div>

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
