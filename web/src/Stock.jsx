import { useEffect, useState } from 'react'
import { request, rupees } from './api.js'

export default function Stock() {
  const [query, setQuery] = useState('')
  const [products, setProducts] = useState([])
  const [amounts, setAmounts] = useState({})
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const [busyId, setBusyId] = useState(null)

  async function load(nextQuery = query) {
    const data = await request(`/api/inventory?q=${encodeURIComponent(nextQuery)}`)
    setProducts(data.products)
  }

  useEffect(() => {
    load('').catch((err) => setError(err.message))
  }, [])

  async function onSearch(event) {
    event.preventDefault()
    setError('')
    try {
      await load(query)
    } catch (err) {
      setError(err.message)
    }
  }

  async function onReceive(event, product) {
    event.preventDefault()
    const quantity = Number(amounts[product.id])
    setError('')
    setNotice('')
    setBusyId(product.id)
    try {
      const data = await request('/api/inventory/receive', {
        method: 'POST',
        body: JSON.stringify({ productId: product.id, quantity }),
      })
      setProducts((current) => current.map((item) => (
        item.id === product.id ? { ...item, quantity: data.quantity } : item
      )))
      setAmounts((current) => ({ ...current, [product.id]: '' }))
      setNotice(`Received ${data.received}. ${data.name} is now ${data.quantity}.`)
    } catch (err) {
      setError(err.message)
    } finally {
      setBusyId(null)
    }
  }

  return (
    <div className="day">
      <section>
        <h2>Receive stock</h2>
        <form className="search" onSubmit={onSearch}>
          <label htmlFor="stock-search">Product</label>
          <div className="search-row">
            <input
              id="stock-search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Name or SKU"
            />
            <button type="submit">Search</button>
          </div>
        </form>
        {notice && <p className="chosen">{notice}</p>}
        {error && <p className="error" role="alert">{error}</p>}
        <ul className="shelf">
          {products.map((product) => (
            <li key={product.id}>
              <div>
                <strong>{product.name}</strong>
                <span>{product.sku} · {rupees(product.price)} · {product.quantity} on hand</span>
              </div>
              <form className="receive" onSubmit={(event) => onReceive(event, product)}>
                <input
                  type="number"
                  min="1"
                  max="10000"
                  inputMode="numeric"
                  aria-label={`Units of ${product.name} to receive`}
                  value={amounts[product.id] ?? ''}
                  onChange={(event) => setAmounts((current) => ({
                    ...current,
                    [product.id]: event.target.value,
                  }))}
                  required
                />
                <button type="submit" disabled={busyId === product.id}>
                  {busyId === product.id ? 'Saving…' : 'Receive'}
                </button>
              </form>
            </li>
          ))}
          {products.length === 0 && <li className="empty">No product matches that search.</li>}
        </ul>
      </section>
    </div>
  )
}
