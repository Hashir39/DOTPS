import { useEffect, useState } from 'react'
import { clock, request, rupees } from './api.js'

export default function Orders() {
  const [orders, setOrders] = useState([])
  const [selectedId, setSelectedId] = useState(null)
  const [detail, setDetail] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false
    request('/api/orders')
      .then((data) => {
        if (cancelled) return
        setOrders(data.orders)
        setSelectedId(data.orders[0]?.id ?? null)
      })
      .catch((err) => {
        if (!cancelled) setError(err.message)
      })
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (!selectedId) {
      setDetail(null)
      return undefined
    }
    let cancelled = false
    request(`/api/orders/${selectedId}`)
      .then((data) => {
        if (!cancelled) setDetail(data.order)
      })
      .catch((err) => {
        if (!cancelled) setError(err.message)
      })
    return () => {
      cancelled = true
    }
  }, [selectedId])

  return (
    <div className="day">
      <section>
        <h2>Today</h2>
        {error && <p className="error" role="alert">{error}</p>}
        <ul className="sale-list">
          {orders.map((order) => (
            <li key={order.id}>
              <button
                type="button"
                className={order.id === selectedId ? 'sale selected' : 'sale'}
                onClick={() => setSelectedId(order.id)}
              >
                <span>
                  <strong>{order.trackingCode}</strong>
                  <span>{order.customerName || 'Walk-in'} · {clock(order.orderDate)}</span>
                </span>
                <span>
                  <strong>{rupees(order.total)}</strong>
                  <span>{order.status}</span>
                </span>
              </button>
            </li>
          ))}
          {orders.length === 0 && !error && <li className="empty">No sales at this store yet today.</li>}
        </ul>
      </section>

      <aside className="ticket">
        {detail ? (
          <div>
            <p className="eyebrow">Store order {detail.storeOrderId}</p>
            <h2>{detail.trackingCode}</h2>
            <p>{detail.customerName}{detail.customerPhone ? ` · ${detail.customerPhone}` : ''}</p>
            <ul className="lines">
              {detail.items.map((item) => (
                <li key={`${item.name}-${item.quantity}-${item.price}`}>
                  <span>{item.name || 'Product'} × {item.quantity}</span>
                  <span>{rupees(Number(item.price) * item.quantity)}</span>
                </li>
              ))}
            </ul>
            <p className="total">
              <span>{detail.payment ? `${detail.payment.status} with ${detail.payment.method}` : detail.status}</span>
              <span>{rupees(detail.total)}</span>
            </p>
          </div>
        ) : (
          <p className="empty">Select a sale.</p>
        )}
      </aside>
    </div>
  )
}
