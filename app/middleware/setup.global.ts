import { useSettingsStore } from '~/stores/settings'

export default defineNuxtRouteMiddleware(async (to, _from) => {
  const settingsStore = useSettingsStore()
  const accessVerified = useState<boolean | null>('access-verified', () => null)

  // Ensure settings are loaded
  if (!settingsStore.isReady) {
    try {
      await settingsStore.initSettings()
    } catch (e) {
      console.error('Failed to load settings in middleware', e)
    }
  }

  const isFirstLaunch = settingsStore.getSetting('system:firstLaunch')
  const isOnboarding = to.path.startsWith('/onboarding')

  if (isFirstLaunch === true) {
    if (!isOnboarding) {
      return navigateTo('/onboarding')
    }
  } else {
    if (isOnboarding) {
      // ignore
    }
  }

  // 访问密码保护 — 跳过 onboarding、access 和 signin 页面
  if (to.path === '/access' || to.path === '/signin' || isOnboarding) return

  // 如果已经确认验证通过，跳过后续检查
  if (accessVerified.value === true) return

  try {
    const headers: Record<string, string> = {}
    // SSR 时需要手动转发浏览器 cookie
    if (import.meta.server) {
      const event = useRequestEvent()
      const cookieHeader = event?.node?.req?.headers?.cookie
      if (cookieHeader) {
        headers.cookie = cookieHeader
      }
    }

    const { enabled, verified } = await $fetch<{ enabled: boolean, verified: boolean }>(
      '/api/access/check',
      { headers },
    )

    if (!enabled) {
      accessVerified.value = true
      return
    }

    if (verified) {
      accessVerified.value = true
      return
    }

    return navigateTo(`/access?redirect=${encodeURIComponent(to.fullPath)}`)
  } catch {
    // 如果检查失败，允许访问（避免锁死）
    accessVerified.value = true
  }
})
