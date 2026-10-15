import { useEffect, useState } from 'react'
import { request, rupees } from './api.js'
import Catalog from './Catalog.jsx'
import Stores from './Stores.jsx'
import People from './People.jsx'

export default function Office({ user, onLogout }) {
  const canCatalog = user.role === 'Super Admin'
  const [view, setView] = useState('sales')
  const [sales, setSales] = useState([])
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false
    request('/api/reports/sales')
      .then((data) => {
        if (!cancelled) setSales(data.sales)
      })
      .catch((err) => {
        if (!cancelled) setError(err.message)
      })
    return () => {
      cancelled = true
    }
  }, [])

  const total = sales.reduce((sum, row) => sum + Number(row.total), 0)
  const sold = sales.reduce((sum, row) => sum + Number(row.sold), 0)
  const showKarachi = user.city !== 'Lahore'
  const showLahore = user.city !== 'Karachi'
  const showBoth = showKarachi && showLahore

  return (
    <div className="register">
      <header className="topbar">
        <div>
          <p className="brand">DOTMS</p>
          <strong>Head office</strong>
          <span>{user.role} · {user.fullName}{user.city ? ` · ${user.city}` : ''}</span>
        </div>
        {canCatalog && (
          <nav>
            <button
              type="button"
              className={view === 'sales' ? 'nav selected' : 'nav'}
              onClick={() => setView('sales')}
            >
              Sales
            </button>
            <button
              type="button"
              className={view === 'products' ? 'nav selected' : 'nav'}
              onClick={() => setView('products')}
            >
              Products
            </button>
            <button
              type="button"
              className={view === 'stores' ? 'nav selected' : 'nav'}
              onClick={() => setView('stores')}
            >
              Stores
            </button>
            <button
              type="button"
              className={view === 'users' ? 'nav selected' : 'nav'}
              onClick={() => setView('users')}
            >
              Users
            </button>
          </nav>
        )}
        <button type="button" className="text-button" onClick={onLogout}>Sign out</button>
      </header>

      {canCatalog && view === 'products' && <Catalog />}
      {canCatalog && view === 'stores' && <Stores />}
      {canCatalog && view === 'users' && <People selfId={user.id} />}

      {view === 'sales' && <section className="report">
        <h2>Sales by product</h2>
        {error && <p className="error" role="alert">{error}</p>}
        <table>
          <thead>
            <tr>
              <th>Product</th>
              {showKarachi && <th className="num">Karachi</th>}
              {showLahore && <th className="num">Lahore</th>}
              {showBoth && <th className="num">Total</th>}
              <th className="num">Total sales</th>
            </tr>
          </thead>
          <tbody>
            {sales.map((row) => (
              <tr key={row.productId}>
                <td>{row.name}</td>
                {showKarachi && <td className="num">{rupees(row.karachi)}</td>}
                {showLahore && <td className="num">{rupees(row.lahore)}</td>}
                {showBoth && <td className="num">{rupees(row.total)}</td>}
                <td className="num">{Number(row.sold).toLocaleString('en-PK')}</td>
              </tr>
            ))}
          </tbody>
          {sales.length > 0 && (
            <tfoot>
              <tr>
                <th>All products</th>
                {showKarachi && <td className="num">{rupees(sales.reduce((sum, row) => sum + Number(row.karachi), 0))}</td>}
                {showLahore && <td className="num">{rupees(sales.reduce((sum, row) => sum + Number(row.lahore), 0))}</td>}
                {showBoth && <th className="num">{rupees(total)}</th>}
                <th className="num">{sold.toLocaleString('en-PK')}</th>
              </tr>
            </tfoot>
          )}
        </table>
      </section>}
    </div>
  )
}
