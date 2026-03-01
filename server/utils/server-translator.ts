import en from '~~/i18n/locales/en.json'

type TranslateParams = Record<string, string | number | boolean | null | undefined>

export type ServerTranslator = (
  key: string,
  paramsOrFallback?: TranslateParams | string,
  fallback?: string,
) => string

const messages = en as Record<string, unknown>

function getByPath(source: Record<string, unknown>, path: string): unknown {
  const parts = path.split('.')
  let current: unknown = source
  for (const part of parts) {
    if (!current || typeof current !== 'object') return undefined
    current = (current as Record<string, unknown>)[part]
  }
  return current
}

function interpolate(template: string, params?: TranslateParams): string {
  if (!params) return template
  return template.replace(/\{([^}]+)\}/g, (_, token) => {
    const value = params[token]
    return value === undefined || value === null ? '' : String(value)
  })
}

/**
 * Server-safe translation helper that does not depend on @intlify/h3 middleware.
 */
export function getServerTranslator(_event?: unknown): ServerTranslator {
  return (key, paramsOrFallback, fallback) => {
    const params =
      paramsOrFallback && typeof paramsOrFallback === 'object'
        ? (paramsOrFallback as TranslateParams)
        : undefined
    const fallbackText =
      typeof paramsOrFallback === 'string'
        ? paramsOrFallback
        : typeof fallback === 'string'
          ? fallback
          : key

    const resolved = getByPath(messages, key)
    if (typeof resolved !== 'string' || resolved.length === 0) {
      return fallbackText
    }
    return interpolate(resolved, params)
  }
}

