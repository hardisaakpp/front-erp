/**
 * Utilidades para manejo consistente de errores del backend
 */

/**
 * Extrae mensaje de error del backend de forma consistente
 */
export function extractErrorMessage(error: any): string {
  const fallbackMessage = error.message || 'Error desconocido'

  if (error.response?.data && typeof error.response.data === 'object') {
    const data = error.response.data

    // Prioridad 1: Business exception
    if (data.type === 'business_exception') {
      return data.error || data.message || fallbackMessage
    }

    // Prioridad 2: Campo 'error'
    if (data.error) {
      return data.error
    }

    // Prioridad 3: Campo 'detail' (FastAPI)
    if (data.detail) {
      const detail = data.detail
      if (Array.isArray(detail)) {
        return detail.map((item: any) => {
          if (typeof item === 'string') return item
          if (item?.msg) return item.msg
          if (item?.loc && item?.msg) {
            const location = Array.isArray(item.loc) ? item.loc.join('.') : String(item.loc)
            return `${location}: ${item.msg}`
          }
          return JSON.stringify(item)
        }).join('\n')
      } else if (typeof detail === 'string') {
        return detail
      } else if (detail.message) {
        return detail.message
      }
      return String(detail)
    }

    // Prioridad 4: Campo 'message'
    if (data.message) {
      return data.message
    }
  }

  // Cuerpo string (p. ej. HTML de error) — intentar mensaje breve
  if (error.response?.data && typeof error.response.data === 'string') {
    const trimmed = error.response.data.trim()
    if (trimmed.length > 0 && trimmed.length < 500) {
      return trimmed
    }
  }

  // Hubo respuesta HTTP pero sin cuerpo útil (500 vacío, etc.).
  // Axios define `error.request` también cuando hubo respuesta; no confundir con fallo de red.
  if (error.response) {
    const status = error.response.status
    if (status >= 500) {
      return `Error del servidor MBA3 (${status}). Revisa los logs del API (p. ej. contenedor mba3-api / uvicorn) y la conexión a la base de datos.`
    }
    if (status === 401) {
      return 'No autorizado. Vuelve a iniciar sesión.'
    }
    if (status === 403) {
      return 'Acceso denegado para esta operación.'
    }
    return fallbackMessage
  }

  if (error.request) {
    if (error.code === 'ECONNABORTED' || error.message?.includes('timeout')) {
      return 'El servidor tardó demasiado en responder. El proceso de validación puede estar ejecutándose. Intenta nuevamente en unos minutos.'
    }
    return 'No se pudo conectar con el servidor. Verifica tu conexión a internet.'
  }

  return fallbackMessage
}

/**
 * Crea un error enriquecido con información del backend
 */
export function createEnrichedError(error: any, defaultMessage: string): Error {
  const message = extractErrorMessage(error)
  const enrichedError = new Error(message || defaultMessage) as any
  
  // Preservar información del response
  enrichedError.response = error.response
  enrichedError.isBusinessException = error.response?.data?.type === 'business_exception'
  enrichedError.businessError = error.response?.data?.error
  
  return enrichedError
}

/**
 * Normaliza respuesta de validación (validation -> validacion)
 */
export function normalizeValidationResponse(data: any): any {
  const normalized = { ...data }
  if (normalized.validation && !normalized.validacion) {
    normalized.validacion = normalized.validation
  }
  if (normalized.validation_sap && !normalized.validacion_sap) {
    normalized.validacion_sap = normalized.validation_sap
  }
  return normalized
}
