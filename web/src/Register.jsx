import { useEffect, useState } from 'react'
import { request, rupees } from './api.js'

const METHODS = ['Cash', 'Card', 'Online']

export default function Register() {
  const [query, setQuery] = useState('')
  const [products, setProducts] = useState([])
  const [cart, setCart] = useState([])
  const [phone, setPhone] = useState('')
  const [matches, setMatches] = useState([])
  const [customer, setCustomer] = useState(null)
  const [newName, setNewName] = useState('')
  const [method, setMethod] = useState('Cash')
  const [receipt, setReceipt] = useState(null)
  const [searched, setSearched] = useState(false)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function loadProducts(nextQuery = query) {
    const data = await request(`/api/products?q=${encodeURIComponent(nextQuery)}`)
    setProducts(data.products)
  }

  useEffect(() => {
    loadProducts('').catch((err) => setError(err.message))
  }, [])

  function addProduct(product) {
    setError('')
    setReceipt(null)
    setCart((current) => {
      const existing = current.find((line) => line.productId === product.id)
      const nextQty = (existing?.quantity ?? 0) + 1
      if (nextQty > product.quantity) return current
      if (existing) {
        return current.map((line) => (
          line.productId === product.id ? { ...line, quantity: nextQty } : line
        ))
      }
      return [...current, {
        productId: product.id,
        name: product.name,
        price: product.price,
        quantity: 1,
        stock: product.quantity,
      }]
    })
  }

  function changeQty(productId, quantity) {
    setCart((current) => current.flatMap((line) => {
      if (line.productId !== productId) return [line]
      if (quantity <= 0) return []
      return [{ ...line, quantity: Math.min(quantity, line.stock) }]
    }))
  }

  async function onSearchProducts(event) {
    event.preventDefault()
    setError('')
    try {
      await loadProducts(query)
    } catch (err) {
      setError(err.message)
    }
  }

  async function onSearchCustomers(event) {
    event.preventDefault()
    setError('')
    setCustomer(null)
    setMatches([])
    setSearched(false)
    try {
      const data = await request(`/api/customers?q=${encodeURIComponent(phone)}`)
      setMatches(data.customers)
      setSearched(true)
      if (data.customers.length === 1) setCustomer(data.customers[0])
    } catch (err) {
      setError(err.message)
    }
  }

  async function onAddCustomer(event) {
    event.preventDefault()
    setError('')
    setBusy(true)
    try {
      const data = await request('/api/customers', {
        method: 'POST',
        body: JSON.stringify({ name: newName, phone }),
      })
      setCustomer(data.customer)
      setMatches([])
      setNewName('')
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  async function onPay() {
    setError('')
    setBusy(true)
    try {
      const data = await request('/api/orders', {
        method: 'POST',
        body: JSON.stringify({
          customerId: customer.id,
          method,
          items: cart.map((line) => ({ productId: line.productId, quantity: line.quantity })),
        }),
      })
      setReceipt(data.receipt)
      setCart([])
      await loadProducts(query)
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  const total = cart.reduce((sum, line) => sum + Number(line.price) * line.quantity, 0)

  return (
      <div className="counter">
        <section>
          <form className="search" onSubmit={onSearchProducts}>
            <label htmlFor="product-search">Product</label>
            <div className="search-row">
              <input
                id="product-search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Name or SKU"
              />
              <button type="submit">Search</button>
            </div>
          </form>

          <ul className="shelf">
            {products.map((product) => (
              <li key={product.id}>
                <div>
                  <strong>{product.name}</strong>
                  <span>{product.sku} · {product.quantity} in stock</span>
                </div>
                <div className="shelf-actions">
                  <span>{rupees(product.price)}</span>
                  <button
                    type="button"
                    onClick={() => addProduct(product)}
                    disabled={product.quantity <= 0}
                  >
                    Add
                  </button>
                </div>
              </li>
            ))}
            {products.length === 0 && <li className="empty">No product matches that search.</li>}
          </ul>
        </section>

        <aside className="ticket">
          {receipt ? (
            <div>
              <p className="eyebrow">Sale complete</p>
              <h2>{receipt.trackingCode}</h2>
              <p>{receipt.customer.name} · store order {receipt.storeOrderId}</p>
              <ul className="lines">
                {receipt.items.map((item) => (
                  <li key={item.name}>
                    <span>{item.name} × {item.quantity}</span>
                    <span>{rupees(Number(item.price) * item.quantity)}</span>
                  </li>
                ))}
              </ul>
              <p className="total"><span>Paid with {receipt.method}</span><span>{rupees(receipt.total)}</span></p>
              <button type="button" className="pay" onClick={() => setReceipt(null)}>New sale</button>
            </div>
          ) : (
            <div>
              <p className="eyebrow">Cart</p>
              <ul className="lines">
                {cart.map((line) => (
                  <li key={line.productId}>
                    <span>{line.name}</span>
                    <span className="qty">
                      <button type="button" onClick={() => changeQty(line.productId, line.quantity - 1)}>-</button>
                      {line.quantity}
                      <button type="button" onClick={() => changeQty(line.productId, line.quantity + 1)}>+</button>
                    </span>
                    <span>{rupees(Number(line.price) * line.quantity)}</span>
                  </li>
                ))}
                {cart.length === 0 && <li className="empty">Scan or add a product.</li>}
              </ul>
              <p className="total"><span>Total</span><span>{rupees(total)}</span></p>

              <form onSubmit={onSearchCustomers}>
                <label htmlFor="phone">Shopper phone or name</label>
                <div className="search-row">
                  <input
                    id="phone"
                    value={phone}
                    onChange={(event) => setPhone(event.target.value)}
                    placeholder="03001234567"
                  />
                  <button type="submit">Find</button>
                </div>
              </form>
              {customer && <p className="chosen">{customer.name} · {customer.phone}</p>}
              {matches.length > 1 && (
                <ul className="matches">
                  {matches.map((match) => (
                    <li key={match.id}>
                      <button type="button" className="text-button" onClick={() => setCustomer(match)}>
                        {match.name} · {match.phone}
                      </button>
                    </li>
                  ))}
                </ul>
              )}
              {searched && phone && matches.length === 0 && !customer && (
                <form onSubmit={onAddCustomer} className="new-shopper">
                  <label htmlFor="shopper-name">New shopper</label>
                  <input
                    id="shopper-name"
                    value={newName}
                    onChange={(event) => setNewName(event.target.value)}
                    placeholder="Name"
                    required
                  />
                  <button type="submit" disabled={busy}>Add shopper</button>
                </form>
              )}

              <div className="methods" role="group" aria-label="Payment method">
                {METHODS.map((item) => (
                  <button
                    key={item}
                    type="button"
                    className={item === method ? 'method selected' : 'method'}
                    onClick={() => setMethod(item)}
                  >
                    {item}
                  </button>
                ))}
              </div>
              {error && <p className="error" role="alert">{error}</p>}
              <button type="button" className="pay" onClick={onPay} disabled={busy || cart.length === 0 || !customer}>
                {busy ? 'Taking payment…' : `Pay ${rupees(total)}`}
              </button>
            </div>
          )}
        </aside>
      </div>
  )
}
