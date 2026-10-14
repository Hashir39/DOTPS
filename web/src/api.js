export async function request(path, options = {}) {
  let response
  try {
    response = await fetch(path, {
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      ...options,
    })
  } catch {
    const error = new Error('Cannot reach the API. Start the server on port 4000.')
    error.status = 0
    throw error
  }

  if (response.status === 204) return null

  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    const error = new Error(data.error || 'Request failed.')
    error.status = response.status
    throw error
  }
  return data
}

export function rupees(value) {
  return `Rs ${Number(value).toLocaleString('en-PK', { maximumFractionDigits: 2 })}`
}

export function clock(value) {
  return new Date(value).toLocaleTimeString('en-PK', {
    timeZone: 'Asia/Karachi',
    hour: '2-digit',
    minute: '2-digit',
  })
}
