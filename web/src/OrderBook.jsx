import { useEffect, useState } from 'react'
import { request, rupees } from './api.js'

function when(value) {
  return new Date(value).toLocaleString('en-PK', {
    timeZone: 'Asia/Karachi',
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export default function OrderBook({ title, note, listPath, showCity }) {
  const [page, setPage] = useState(1)
  const [data, setData] = useState(null)
  const [selectedId, setSelectedId] = useState(null)
  const [detail, setDetail] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false
    setError('')
    request(`${listPath}?page=${page}`)
      .then((payload) => {
        if (cancelled) return
        setData(payload)
        setSelectedId(null)
        setDetail(null)
      })
      .catch((err) => {
        if (!cancelled) setError(err.message)
      })
    return () => {
      cancelled = true
    }
  }, [listPath, page])

  useEffect(() => {
    if (!selectedId) {
      setDetail(null)
      return undefined
    }
    let cancelled = false
    request(`${listPath}/${selectedId}`)
      .then((payload) => {
        if (!cancelled) setDetail(payload.order)
      })
      .catch((err) => {
        if (!cancelled) setError(err.message)
      })
    return () => {
      cancelled = true
    }
  }, [listPath, selectedId])

  const total = data?.total ?? 0
  const pageSize = data?.pageSize ?? 50
  const pages = Math.max(1, Math.ceil(total / pageSize))

  return (
    <section className="report">
      <h2>{title}</h2>
      <p className="muted">{note} {total > 0 ? `${total.toLocaleString('en-PK')} orders.` : ''}</p>
      {error && <p className="error" role="alert">{error}</p>}
      <table className="orders">
        <thead>
          <tr>
            <th>Sale</th>
            <th>When</th>
            <th>Store</th>
            {showCity && <th>City</th>}
            <th>Customer</th>
            <th>Items</th>
            <th>Status</th>
            <th className="num">Total</th>
          </tr>
        </thead>
        <tbody>
          {data?.orders.map((order) => (
            <tr
              key={order.id}
              className={order.id === selectedId ? 'picked' : ''}
              onClick={() => setSelectedId(order.id)}
            >
              <td>{order.trackingCode}</td>
              <td>{when(order.orderDate)}</td>
              <td>{order.storeName}</td>
              {showCity && <td>{order.city}</td>}
              <td>{order.customerName || 'Walk-in'}</td>
              <td className="items">{order.items}</td>
              <td>{order.status}</td>
              <td className="num">{rupees(order.total)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {detail && (
        <aside className="ticket">
          <p className="eyebrow">{detail.storeName} · {detail.city}</p>
          <h2>{detail.trackingCode}</h2>
          <p>
            {detail.customerName || 'Walk-in'}
            {detail.customerPhone ? ` · ${detail.customerPhone}` : ''}
            {' · '}
            {when(detail.orderDate)}
          </p>
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
        </aside>
      )}
      <div className="pager">
        <button type="button" className="quiet" disabled={page <= 1} onClick={() => setPage(page - 1)}>
          Previous
        </button>
        <span>Page {page} of {pages.toLocaleString('en-PK')}</span>
        <button type="button" className="quiet" disabled={page >= pages} onClick={() => setPage(page + 1)}>
          Next
        </button>
      </div>
    </section>
  )
}
