import { useEffect, useState } from 'react'
import { request, rupees } from './api.js'

const emptyForm = { sku: '', name: '', categoryId: '', price: '' }

export default function Catalog() {
  const [products, setProducts] = useState([])
  const [categories, setCategories] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [editingId, setEditingId] = useState(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false
    Promise.all([
      request('/api/catalog/products'),
      request('/api/catalog/categories'),
    ]).then(([productData, categoryData]) => {
      if (cancelled) return
      setProducts(productData.products)
      setCategories(categoryData.categories)
      if (categoryData.categories[0]) {
        setForm((current) => (
          current.categoryId ? current : { ...current, categoryId: String(categoryData.categories[0].id) }
        ))
      }
    }).catch((err) => {
      if (!cancelled) setError(err.message)
    })
    return () => {
      cancelled = true
    }
  }, [])

  function updateField(field, value) {
    setForm((current) => ({ ...current, [field]: value }))
  }

  function onEdit(product) {
    setEditingId(product.id)
    setForm({
      sku: product.sku,
      name: product.name,
      categoryId: String(product.categoryId),
      price: String(product.price),
    })
    setNotice('')
    setError('')
  }

  function onCancel() {
    setEditingId(null)
    setForm({
      ...emptyForm,
      categoryId: categories[0] ? String(categories[0].id) : '',
    })
    setError('')
  }

  async function onSave(event) {
    event.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    const body = JSON.stringify({
      sku: form.sku,
      name: form.name,
      categoryId: Number(form.categoryId),
      price: form.price,
    })
    try {
      const data = editingId
        ? await request(`/api/catalog/products/${editingId}`, { method: 'PATCH', body })
        : await request('/api/catalog/products', { method: 'POST', body })
      setProducts((current) => {
        const next = current.filter((item) => item.id !== data.product.id)
        next.push(data.product)
        next.sort((a, b) => a.name.localeCompare(b.name))
        return next
      })
      setNotice(`${editingId ? 'Updated' : 'Added'} ${data.product.name}. Karachi and Lahore both have it.`)
      onCancel()
    } catch (err) {
      setError(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="report catalog">
      <h2>{editingId ? 'Edit product' : 'Add a product'}</h2>
      <p className="muted">Saved in central.products. The trigger copies the row to Karachi and Lahore.</p>
      <form className="catalog-form" onSubmit={onSave}>
        <div>
          <label htmlFor="product-sku">SKU</label>
          <input
            id="product-sku"
            value={form.sku}
            onChange={(event) => updateField('sku', event.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="product-name">Name</label>
          <input
            id="product-name"
            value={form.name}
            onChange={(event) => updateField('name', event.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="product-category">Category</label>
          <select
            id="product-category"
            value={form.categoryId}
            onChange={(event) => updateField('categoryId', event.target.value)}
            required
          >
            {categories.map((category) => (
              <option key={category.id} value={category.id}>{category.name}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="product-price">Price</label>
          <input
            id="product-price"
            inputMode="decimal"
            value={form.price}
            onChange={(event) => updateField('price', event.target.value)}
            required
          />
        </div>
        <div className="catalog-actions">
          <button type="submit" disabled={saving || categories.length === 0}>
            {saving ? 'Saving…' : editingId ? 'Save' : 'Add product'}
          </button>
          {editingId && (
            <button type="button" className="quiet" onClick={onCancel}>Cancel</button>
          )}
        </div>
      </form>
      {notice && <p className="chosen">{notice}</p>}
      {error && <p className="error" role="alert">{error}</p>}
      <table>
        <thead>
          <tr>
            <th>SKU</th>
            <th>Product</th>
            <th>Category</th>
            <th className="num">Price</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {products.map((product) => (
            <tr key={product.id}>
              <td>{product.sku}</td>
              <td>{product.name}</td>
              <td>{product.categoryName}</td>
              <td className="num">{rupees(product.price)}</td>
              <td className="num">
                <button type="button" className="quiet" onClick={() => onEdit(product)}>Edit</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}
