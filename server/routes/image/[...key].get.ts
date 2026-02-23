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

          // 百度网盘等需要特定 User-Agent / Referer，不能 302 重定向，改为服务端代理
          if (rawUrl) {
            try {
              const proxyResp = await fetch(rawUrl, {
                headers: { 'User-Agent': 'pan.baidu.com' },
                redirect: 'follow',
                signal: AbortSignal.timeout(30000),
              })
              if (proxyResp.ok && proxyResp.body) {
                setResponseHeader(event, 'Content-Type', proxyResp.headers.get('content-type') || guessContentType(key))
                const contentLength = proxyResp.headers.get('content-length')
                if (contentLength) setResponseHeader(event, 'Content-Length', contentLength)
                setResponseHeader(event, 'Cache-Control', 'public, max-age=86400')
                return proxyResp.body
              }
            } catch (e) {
              logger.chrono.warn('Proxy raw_url failed, falling back', e)
            }
          }

          // Fallback: 通过 AList /d/ 路径代理
          const signParam = sign ? `?sign=${encodeURIComponent(sign)}` : ''
          const encodedAbsolutePath = absolutePath.split('/').map(seg => encodeURIComponent(seg)).join('/')
          try {
            const dResp = await fetch(`${baseUrl}/d${encodedAbsolutePath}${signParam}`, {
              redirect: 'follow',
              signal: AbortSignal.timeout(30000),
            })
            if (dResp.ok && dResp.body) {
              setResponseHeader(event, 'Content-Type', dResp.headers.get('content-type') || guessContentType(key))
              const contentLength = dResp.headers.get('content-length')
              if (contentLength) setResponseHeader(event, 'Content-Length', contentLength)
              setResponseHeader(event, 'Cache-Control', 'public, max-age=86400')
              return dResp.body
            }
          } catch (e) {
            logger.chrono.warn('Proxy /d/ path failed, falling back to provider.get()', e)
          }
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
