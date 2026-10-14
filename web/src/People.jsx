import { useEffect, useState } from 'react'
import { request } from './api.js'

const emptyForm = {
  username: '',
  fullName: '',
  email: '',
  password: '',
  roleId: '',
  storeId: '',
}

export default function People({ selfId }) {
  const [people, setPeople] = useState([])
  const [roles, setRoles] = useState([])
  const [stores, setStores] = useState([])
  const [form, setForm] = useState(emptyForm)
  const [editingId, setEditingId] = useState(null)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)

  function withDefaults(current, nextRoles, nextStores) {
    const roleId = current.roleId || (nextRoles[0] ? String(nextRoles[0].id) : '')
    const role = nextRoles.find((item) => String(item.id) === roleId)
    const storeId = role?.needsStore
      ? (current.storeId || (nextStores[0] ? String(nextStores[0].id) : ''))
      : ''
    return { ...current, roleId, storeId }
  }

  useEffect(() => {
    let cancelled = false
    request('/api/users')
      .then((data) => {
        if (cancelled) return
        setPeople(data.users)
        setRoles(data.roles)
        setStores(data.stores)
        setForm((current) => withDefaults(current, data.roles, data.stores))
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

  function onRole(roleId) {
    const role = roles.find((item) => String(item.id) === roleId)
    setForm((current) => ({
      ...current,
      roleId,
      storeId: role?.needsStore
        ? (current.storeId || (stores[0] ? String(stores[0].id) : ''))
        : '',
    }))
  }

  function onEdit(person) {
    const role = roles.find((item) => item.id === person.roleId)
    setEditingId(person.id)
    setForm({
      username: person.username,
      fullName: person.fullName,
      email: person.email,
      password: '',
      roleId: String(person.roleId),
      storeId: role?.needsStore && person.storeId ? String(person.storeId) : '',
    })
    setNotice('')
    setError('')
  }

  function onCancel() {
    setEditingId(null)
    setForm(withDefaults({ ...emptyForm }, roles, stores))
    setError('')
  }

  const selectedRole = roles.find((item) => String(item.id) === form.roleId)
  const needsStore = Boolean(selectedRole?.needsStore)
  const editingSelf = editingId === selfId

  async function onSave(event) {
    event.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    const body = JSON.stringify({
      username: form.username,
      fullName: form.fullName,
      email: form.email,
      password: form.password,
      roleId: Number(form.roleId),
      storeId: needsStore ? Number(form.storeId) : null,
    })
    try {
      const data = editingId
        ? await request(`/api/users/${editingId}`, { method: 'PATCH', body })
        : await request('/api/users', { method: 'POST', body })
      setPeople((current) => {
        const next = current.filter((item) => item.id !== data.user.id)
        next.push(data.user)
        next.sort((a, b) => a.username.localeCompare(b.username))
        return next
      })
      const place = data.user.storeName
        ? `${data.user.storeName} · ${data.user.city}`
        : 'Head office'
      setNotice(`${editingId ? 'Updated' : 'Added'} ${data.user.fullName}. ${place}.`)
      onCancel()
    } catch (err) {
      setError(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="report catalog">
      <h2>{editingId ? 'Edit user' : 'Add a user'}</h2>
      <p className="muted">Saved in central.users. A store role takes that store's city. Head office has no store.</p>
      <form className="catalog-form people-form" onSubmit={onSave}>
        <div>
          <label htmlFor="user-username">Username</label>
          <input
            id="user-username"
            value={form.username}
            onChange={(event) => updateField('username', event.target.value)}
            autoComplete="off"
            required
          />
        </div>
        <div>
          <label htmlFor="user-name">Name</label>
          <input
            id="user-name"
            value={form.fullName}
            onChange={(event) => updateField('fullName', event.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="user-email">Email</label>
          <input
            id="user-email"
            type="email"
            value={form.email}
            onChange={(event) => updateField('email', event.target.value)}
            required
          />
        </div>
        <div>
          <label htmlFor="user-password">Password</label>
          <input
            id="user-password"
            type="password"
            value={form.password}
            onChange={(event) => updateField('password', event.target.value)}
            autoComplete="new-password"
            required={!editingId}
          />
        </div>
        <div>
          <label htmlFor="user-role">Role</label>
          <select
            id="user-role"
            value={form.roleId}
            onChange={(event) => onRole(event.target.value)}
            disabled={editingSelf}
            required
          >
            {roles.map((role) => (
              <option key={role.id} value={role.id}>{role.name}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="user-store">Store</label>
          <select
            id="user-store"
            value={needsStore ? form.storeId : ''}
            onChange={(event) => updateField('storeId', event.target.value)}
            disabled={!needsStore}
            required={needsStore}
          >
            {!needsStore && <option value="">No store</option>}
            {stores.map((store) => (
              <option key={store.id} value={store.id}>{store.name} · {store.city}</option>
            ))}
          </select>
        </div>
        <div className="catalog-actions span-row">
          <button type="submit" disabled={saving || roles.length === 0}>
            {saving ? 'Saving…' : editingId ? 'Save' : 'Add user'}
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
            <th>Username</th>
            <th>Name</th>
            <th>Role</th>
            <th>Place</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {people.map((person) => (
            <tr key={person.id}>
              <td>{person.username}</td>
              <td>{person.fullName}</td>
              <td>{person.role}</td>
              <td>{person.storeName ? `${person.storeName} · ${person.city}` : 'Head office'}</td>
              <td className="num">
                <button type="button" className="quiet" onClick={() => onEdit(person)}>Edit</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}
