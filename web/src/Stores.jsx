import { useEffect, useState } from 'react'
import { request } from './api.js'

const emptyForm = { code: '', name: '', cityId: '' }

export default function Stores() {
  const [stores, setStores] = useState([])
  const [cities, setCities] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [editingId, setEditingId] = useState(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false
    request('/api/stores')
      .then((data) => {
        if (cancelled) return
        setStores(data.stores)
        setCities(data.cities)
        if (data.cities[0]) {
          setForm((current) => (
            current.cityId ? current : { ...current, cityId: String(data.cities[0].id) }
          ))
        }
      })
      .catch((err) => {
        if (!cancelled) setError(err.message)
      })
    return () => {
      cancelled = true
    }
  }, [])

  function updateField(field, value) {
    setForm((current) => ({ ...current, [field]: value }))
  }

  function onEdit(store) {
    setEditingId(store.id)
    setForm({
      code: store.code,
      name: store.name,
      cityId: String(store.cityId),
    })
    setNotice('')
    setError('')
  }

  function onCancel() {
    setEditingId(null)
    setForm({
      ...emptyForm,
      cityId: cities[0] ? String(cities[0].id) : '',
    })
    setError('')
  }

  async function onSave(event) {
    event.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    const body = JSON.stringify({
      code: form.code,
      name: form.name,
      cityId: Number(form.cityId),
    })
    try {
      const data = editingId
        ? await request(`/api/stores/${editingId}`, { method: 'PATCH', body })
        : await request('/api/stores', { method: 'POST', body })
      setStores((current) => {
        const next = current.filter((item) => item.id !== data.store.id)
        next.push(data.store)
        next.sort((a, b) => a.city.localeCompare(b.city) || a.name.localeCompare(b.name))
        return next
      })
      setNotice(`${editingId ? 'Updated' : 'Added'} ${data.store.name}. Copied to ${data.store.city} only.`)
      onCancel()
    } catch (err) {
      setError(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="report catalog">
      <h2>{editingId ? 'Edit store' : 'Add a store'}</h2>
      <p className="muted">Saved in central.stores. The trigger copies it to that city only.</p>
      <form className="catalog-form stores-form" onSubmit={onSave}>
        <div>
          <label htmlFor="store-code">Code</label>
          <input
            id="store-code"
            value={form.code}
            onChange={(event) => updateField('code', event.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="store-name">Name</label>
          <input
            id="store-name"
            value={form.name}
            onChange={(event) => updateField('name', event.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="store-city">City</label>
          <select
            id="store-city"
            value={form.cityId}
            onChange={(event) => updateField('cityId', event.target.value)}
            required
          >
            {cities.map((city) => (
              <option key={city.id} value={city.id}>{city.name}</option>
            ))}
          </select>
        </div>
        <div className="catalog-actions">
          <button type="submit" disabled={saving || cities.length === 0}>
            {saving ? 'Saving…' : editingId ? 'Save' : 'Add store'}
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
            <th>Code</th>
            <th>Store</th>
            <th>City</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {stores.map((store) => (
            <tr key={store.id}>
              <td>{store.code}</td>
              <td>{store.name}</td>
              <td>{store.city}</td>
              <td className="num">
                <button type="button" className="quiet" onClick={() => onEdit(store)}>Edit</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}
