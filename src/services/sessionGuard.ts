function normalizeAppBasePath(): string {
  const raw = import.meta.env.VITE_APP_BASE_PATH || '/'
  const withLeading = raw.startsWith('/') ? raw : `/${raw}`
  return withLeading.endsWith('/') ? withLeading : `${withLeading}/`
}

/** Ruta absoluta del login según VITE_APP_BASE_PATH (p. ej. `/scnexus-front/login`). */
export function getLoginPath(): string {
  const base = normalizeAppBasePath()
  if (base === '/') return '/login'
  return `${base.replace(/\/$/, '')}/login`
}

export function buildLoginRedirectUrl(): string {
  const explicit = import.meta.env.VITE_LOGIN_REDIRECT_URL as string
  if (explicit) return explicit
  const origin = typeof window !== 'undefined' ? window.location.origin : ''
  return `${origin}${getLoginPath()}`
}

export const LOGIN_REDIRECT_URL = buildLoginRedirectUrl()

function isLoginPath(pathname: string): boolean {
  const loginPath = getLoginPath()
  return pathname === loginPath || pathname.startsWith(`${loginPath}/`)
}

export function clearStoredSession(): void {
  localStorage.removeItem('token')
  localStorage.removeItem('user')
  sessionStorage.removeItem('token')
  sessionStorage.removeItem('user')
}

export function redirectToLogin(): void {
  if (typeof window === 'undefined') return
  if (isLoginPath(window.location.pathname)) return
  window.location.href = buildLoginRedirectUrl()
}

export function attachUnauthorizedRedirect(
  instance: any,
  options?: { ignoreUrlIncludes?: string[] }
): void {
  instance.interceptors.response.use(
    (response: any) => response,
    (error: any) => {
      const status = error?.response?.status
      const requestUrl = String(error?.config?.url || '').toLowerCase()
      const ignore = options?.ignoreUrlIncludes?.some((part) => requestUrl.includes(part.toLowerCase())) || false

      if (status === 401 && !ignore) {
        clearStoredSession()
        redirectToLogin()
      }
      return Promise.reject(error)
    }
  )
}
