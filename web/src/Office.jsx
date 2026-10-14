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

  return (
    <div className="register">
      <header className="topbar">
        <div>
          <p className="brand">POS Mart</p>
          <strong>Head office</strong>
          <span>{user.role} · {user.fullName}</span>
        </div>
        <nav>
          <button
            type="button"
            className={view === 'sales' ? 'nav selected' : 'nav'}
            onClick={() => setView('sales')}
          >
            Sales
          </button>
          {canCatalog && (
            <button
              type="button"
              className={view === 'products' ? 'nav selected' : 'nav'}
              onClick={() => setView('products')}
            >
              Products
            </button>
          )}
          {canCatalog && (
            <button
              type="button"
              className={view === 'stores' ? 'nav selected' : 'nav'}
              onClick={() => setView('stores')}
            >
              Stores
            </button>
          )}
          {canCatalog && (
            <button
              type="button"
              className={view === 'users' ? 'nav selected' : 'nav'}
              onClick={() => setView('users')}
            >
              Users
            </button>
          )}
        </nav>
        <button type="button" className="text-button" onClick={onLogout}>Sign out</button>
      </header>

      {canCatalog && view === 'products' && <Catalog />}
      {canCatalog && view === 'stores' && <Stores />}
      {canCatalog && view === 'users' && <People selfId={user.id} />}

      {view === 'sales' && <section className="report">
        <h2>Sales by product</h2>
        <p className="muted">Karachi and Lahore together, from central.product_sales.</p>
        {error && <p className="error" role="alert">{error}</p>}
        <table>
          <thead>
            <tr>
              <th>Product</th>
              <th className="num">Karachi</th>
              <th className="num">Lahore</th>
              <th className="num">Total</th>
            </tr>
          </thead>
          <tbody>
            {sales.map((row) => (
              <tr key={row.productId}>
                <td>{row.name}</td>
                <td className="num">{rupees(row.karachi)}</td>
                <td className="num">{rupees(row.lahore)}</td>
                <td className="num">{rupees(row.total)}</td>
              </tr>
            ))}
          </tbody>
          {sales.length > 0 && (
            <tfoot>
              <tr>
                <th>All products</th>
                <td className="num">{rupees(sales.reduce((sum, row) => sum + Number(row.karachi), 0))}</td>
                <td className="num">{rupees(sales.reduce((sum, row) => sum + Number(row.lahore), 0))}</td>
                <th className="num">{rupees(total)}</th>
              </tr>
            </tfoot>
          )}
        </table>
      </section>}
    </div>
  )
}
