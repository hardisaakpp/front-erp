/** Sidebar, rutas Vue y pantallas del módulo (sin llamadas API). */
export const PROMOCION_SOBRES_VIEW_PERMISSION = 'promocion.sobres.view' as const

/** Consulta de beneficiario y registro de entrega (API + mismo acceso UI que view). */
export const PROMOCION_SOBRES_OPERATE_PERMISSION = 'promocion.sobres.operate' as const

/** Acceso a la interfaz: view u operate (cajeros con solo operate siguen viendo el menú). */
export const PROMOCION_SOBRES_UI_PERMISSIONS = [
  PROMOCION_SOBRES_VIEW_PERMISSION,
  PROMOCION_SOBRES_OPERATE_PERMISSION
] as const

/** Guard de rutas: mismos permisos que el sidebar. */
export const PROMOCION_SOBRES_ROUTE_PERMISSIONS = [...PROMOCION_SOBRES_UI_PERMISSIONS] as const

/** Llamadas HTTP al microservicio (operate; el backend también acepta view si está configurado). */
export const PROMOCION_SOBRES_OPERATE_PERMISSIONS = [PROMOCION_SOBRES_OPERATE_PERMISSION] as const

export function normalizePermission(value: string): string {
  return value.trim().toLowerCase()
}

export function hasPromocionSobresUiPermission(permissions: readonly string[]): boolean {
  return permissions.some((permission) => {
    const p = normalizePermission(permission)
    return (
      p === PROMOCION_SOBRES_VIEW_PERMISSION ||
      p === PROMOCION_SOBRES_OPERATE_PERMISSION ||
      p.startsWith('promocion.sobres.')
    )
  })
}
