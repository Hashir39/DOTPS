import { useState } from 'react'
import OrderBook from './OrderBook.jsx'
import Orders from './Orders.jsx'
import Register from './Register.jsx'
import Stock from './Stock.jsx'

export default function StoreDesk({ user, onLogout }) {
  const canSell = user.role === 'Cashier' || user.role === 'Store Manager'
  const canStock = user.role === 'Inventory Clerk' || user.role === 'Store Manager'
  const canCityOrders = user.role === 'Store Manager'
  const [view, setView] = useState(canSell ? 'register' : 'stock')

  return (
    <div className="register">
      <header className="topbar">
        <div>
          <p className="brand">DOTMS</p>
          <strong>{user.storeName}</strong>
          <span>{user.city} · {user.fullName}</span>
        </div>
        <nav>
          {canSell && (
            <button
              type="button"
              className={view === 'register' ? 'nav selected' : 'nav'}
              onClick={() => setView('register')}
            >
              Register
            </button>
          )}
          {canSell && (
            <button
              type="button"
              className={view === 'orders' ? 'nav selected' : 'nav'}
              onClick={() => setView('orders')}
            >
              Today
            </button>
          )}
          {canCityOrders && (
            <button
              type="button"
              className={view === 'history' ? 'nav selected' : 'nav'}
              onClick={() => setView('history')}
            >
              Orders
            </button>
          )}
          {canStock && (
            <button
              type="button"
              className={view === 'stock' ? 'nav selected' : 'nav'}
              onClick={() => setView('stock')}
            >
              Stock
            </button>
          )}
        </nav>
        <button type="button" className="text-button" onClick={onLogout}>Sign out</button>
      </header>

      {canSell && (
        <div hidden={view !== 'register'}>
          <Register />
        </div>
      )}
      {canSell && view === 'orders' && <Orders />}
      {canCityOrders && view === 'history' && (
        <OrderBook
          title={`${user.storeName} orders`}
          note={`Sales at ${user.storeName} only.`}
          listPath="/api/city-orders"
        />
      )}
      {canStock && view === 'stock' && <Stock />}
    </div>
  )
}
