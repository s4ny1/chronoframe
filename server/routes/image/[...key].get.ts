import path from 'node:path'
import { getStorageManager } from '../../plugins/3.storage'
import { logger } from '../../utils/logger'

const guessContentType = (key: string) => {
  const ext = path.extname(key).toLowerCase()
  switch (ext) {
    case '.jpg': case '.jpeg': return 'image/jpeg'
    case '.png': return 'image/png'
    case '.webp': return 'image/webp'
    case '.gif': return 'image/gif'
    case '.bmp': return 'image/bmp'
    case '.tif': case '.tiff': return 'image/tiff'
    case '.heic': case '.heif': return 'image/heic'
    case '.mp4': return 'video/mp4'
    case '.mov': return 'video/quicktime'
    default: return 'application/octet-stream'
  }
}

export default eventHandler(async (event) => {
  const manager = getStorageManager()
  const provider = manager.getProvider() as any
  const rawKey = getRouterParam(event, 'key')

  if (!rawKey) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid key' })
  }

  const key = decodeURIComponent(rawKey)

  // AList/OpenList: get latest sign and redirect to avoid proxy traffic.
  if (provider?.config?.provider === 'alist' || provider?.config?.provider === 'openlist') {
    const baseUrl: string = (provider.config.baseUrl as string).replace(/\/$/, '')
    const metaPath: string = provider.config.metaEndpoint || '/api/fs/get'
    const token: string = provider.config.token || ''
    const rootPath: string = (provider.config.rootPath || '').replace(/\/+$/g, '').replace(/^\/+/, '')

    // 计算 rootedKey（与 withRoot 逻辑一致）
    const trimmedKey = key.replace(/^\/+/, '')
    const rootedKey = (!rootPath || trimmedKey === rootPath || trimmedKey.startsWith(`${rootPath}/`))
      ? trimmedKey
      : `${rootPath}/${trimmedKey}`
    const absolutePath = rootedKey.startsWith('/') ? rootedKey : `/${rootedKey}`

    try {
      const metaResp = await fetch(`${baseUrl}${metaPath}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: token },
        body: JSON.stringify({ path: absolutePath, password: '', page: 1, per_page: 0, refresh: true }),
        signal: AbortSignal.timeout(8000),
      })
      if (metaResp.ok) {
        const data = (await metaResp.json()) as any
        if (data?.code === 200) {
          const sign: string = typeof data.data?.sign === 'string' && data.data.sign ? data.data.sign : ''
          const rawUrl: string = typeof data.data?.raw_url === 'string' && data.data.raw_url ? data.data.raw_url : ''
          // 优先重定向到 raw_url（百度网盘直链，更快）
          if (rawUrl) {
            return sendRedirect(event, rawUrl, 302)
          }
          // 次选：/d/path?sign=xxx
          const signParam = sign ? `?sign=${encodeURIComponent(sign)}` : ''
          const encodedAbsolutePath = absolutePath.split('/').map(seg => encodeURIComponent(seg)).join('/')
          return sendRedirect(event, `${baseUrl}/d${encodedAbsolutePath}${signParam}`, 302)
        }
      }
    } catch (e) {
      logger.chrono.error('Failed to get AList signed URL for key:', key, e)
    }

    // Fallback：直接代理 Buffer
    const buf = await provider.get(key) as Buffer | null
    if (!buf) throw createError({ statusCode: 404, statusMessage: 'Not found' })
    setResponseHeader(event, 'Content-Type', guessContentType(key))
    return buf
  }

  // 其他 provider：代理 Buffer
  const { storageProvider } = useStorageProvider(event)
  const photo = await storageProvider.get(key)
  if (!photo) {
    throw createError({ statusCode: 404, statusMessage: 'Photo not found' })
  }
  setResponseHeader(event, 'Content-Type', guessContentType(key))
  logger.chrono.info('Serve image from key', key)
  return photo
})
