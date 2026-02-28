type I18nLocaleConfig = {
  fallbacks: string[]
  cacheable: boolean
}

type I18nFallbackContext = {
  messages: Record<string, any>
  slp: Record<string, any>
  localeConfigs: Record<string, I18nLocaleConfig>
  trackMap: Record<string, Set<string>>
  vueI18nOptions?: unknown
  trackKey: (key: string, locale: string) => void
}

const FALLBACK_LOCALE_CONFIGS: Record<string, I18nLocaleConfig> = {
  'zh-Hans': { fallbacks: ['en'], cacheable: false },
  'zh-Hant-TW': { fallbacks: ['zh-Hans', 'en'], cacheable: false },
  'zh-Hant-HK': { fallbacks: ['zh-Hans', 'en'], cacheable: false },
  en: { fallbacks: [], cacheable: false },
  ja: { fallbacks: ['en'], cacheable: false },
}

function createFallbackContext(): I18nFallbackContext {
  return {
    messages: {},
    slp: {},
    localeConfigs: FALLBACK_LOCALE_CONFIGS,
    trackMap: {},
    trackKey(key: string, locale: string) {
      this.trackMap[locale] ??= new Set<string>()
      this.trackMap[locale].add(key)
    },
  }
}

export default defineEventHandler((event) => {
  // Workaround for @nuxtjs/i18n route cache callback reading nuxtI18n
  // context before it has been initialized on some deployments.
  if (!event.path.includes('/_i18n/')) return

  const ctx = event.context as Record<string, any>
  if (ctx.nuxtI18n != null) return

  ctx.nuxtI18n = createFallbackContext()
})

