import { createHash } from 'node:crypto'
import path from 'node:path'
import type { BaiduStorageConfig } from '~~/shared/types/storage'
import { settingsManager } from '../../settings/settingsManager'
import type { Logger } from '../../../utils/logger'
import type { StorageObject, StorageProvider } from '../interfaces'

const DEFAULT_BAIDU_CLIENT_ID = 'hq9yQ9w9kR4YHj1kyYafLygVocobh7Sf'
const DEFAULT_BAIDU_CLIENT_SECRET = 'YH2VpZcFJHYNnV6vLfHQXDBhcE7ZChyE'
const BAIDU_TOKEN_REFRESH_TIMEOUT_MS = 10_000
const BAIDU_TOKEN_RETRY_COOLDOWN_MS = 5 * 60_000
const BAIDU_LIST_PAGE_LIMIT = 200

type BaiduApiResponse<T = any> = {
  errno?: number
  errmsg?: string
  error_code?: string | number
  error_msg?: string
  list?: T[]
  [key: string]: any
}

type BaiduListEntry = {
  fs_id?: number
  path?: string
  server_filename?: string
  size?: number
  md5?: string
  server_mtime?: number
  isdir?: 0 | 1
}

export class BaiduStorageProvider implements StorageProvider {
  config: BaiduStorageConfig
  private logger?: Logger['storage']
  private accessToken?: string
  private accessTokenExpiresAt = 0
  private refreshLock?: Promise<string>
  private tokenRefreshBlockedUntil = 0
  private tokenRefreshBlockedReason?: string

  constructor(config: BaiduStorageConfig, logger?: Logger['storage']) {
    this.config = config
    this.logger = logger
  }

  private get clientId(): string {
    return this.config.clientId || DEFAULT_BAIDU_CLIENT_ID
  }

  private get clientSecret(): string {
    return this.config.clientSecret || DEFAULT_BAIDU_CLIENT_SECRET
  }

  private get tokenEndpoint(): string {
    return this.config.tokenEndpoint || 'https://openapi.baidu.com/oauth/2.0/token'
  }

  private get xpanFileEndpoint(): string {
    return this.config.xpanFileEndpoint || 'https://pan.baidu.com/rest/2.0/xpan/file'
  }

  private get xpanMultimediaEndpoint(): string {
    return this.config.xpanMultimediaEndpoint || 'https://pan.baidu.com/rest/2.0/xpan/multimedia'
  }

  private get pcsUploadEndpoint(): string {
    return this.config.pcsUploadEndpoint || 'https://d.pcs.baidu.com/rest/2.0/pcs/superfile2'
  }

  private normalizedRoot(): string {
    return (this.config.rootPath || '/apps/chronoframe')
      .replace(/\/+$/g, '')
      .replace(/^\/+/, '')
  }

  private withRoot(key: string): string {
    const root = this.normalizedRoot()
    const trimmedKey = key.replace(/^\/+/, '')
    if (!root) return trimmedKey
    if (trimmedKey === root || trimmedKey.startsWith(`${root}/`)) return trimmedKey
    return `${root}/${trimmedKey}`
  }

  private toAbsolutePath(key: string): string {
    if (!key || key === '/') return '/'
    return key.startsWith('/') ? key : `/${key}`
  }

  private isSecurityPolicyError(payload: any, rawText: string): boolean {
    const merged = `${payload?.error || ''} ${payload?.error_description || ''} ${rawText}`.toLowerCase()
    return merged.includes('trigger security policy')
  }

  private isRefreshTokenExpired(payload: any, rawText: string): boolean {
    const merged = `${payload?.error || ''} ${payload?.error_description || ''} ${rawText}`.toLowerCase()
    return merged.includes('expired_token')
      || merged.includes('refresh token has been used')
      || merged.includes('invalid refresh token')
  }

  private async persistRefreshToken(previousRefreshToken: string, latestRefreshToken: string): Promise<void> {
    if (!previousRefreshToken || !latestRefreshToken || previousRefreshToken === latestRefreshToken) {
      return
    }

    try {
      const activeProvider = await settingsManager.storage.getActiveProvider()
      if (!activeProvider || activeProvider.provider !== 'baidu') return

      const currentConfig = (activeProvider.config || {}) as BaiduStorageConfig
      if (currentConfig.refreshToken !== previousRefreshToken) return

      await settingsManager.storage.updateProvider(activeProvider.id, {
        config: {
          ...currentConfig,
          refreshToken: latestRefreshToken,
        } as BaiduStorageConfig,
      } as any)

      this.logger?.info('Persisted refreshed Baidu refresh_token into active storage config')
    } catch (error) {
      this.logger?.warn('Failed to persist refreshed Baidu refresh_token', error)
    }
  }

  private async refreshAccessToken(): Promise<string> {
    if (Date.now() < this.tokenRefreshBlockedUntil) {
      throw new Error(this.tokenRefreshBlockedReason || 'Baidu token refresh temporarily blocked')
    }

    const previousRefreshToken = this.config.refreshToken
    const params = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: previousRefreshToken,
      client_id: this.clientId,
      client_secret: this.clientSecret,
    })

    const attemptRefresh = async () => {
      const response = await fetch(`${this.tokenEndpoint}?${params.toString()}`, {
        method: 'GET',
        signal: AbortSignal.timeout(BAIDU_TOKEN_REFRESH_TIMEOUT_MS),
      })

      const text = await response.text().catch(() => '')
      let payload: any = null
      if (text) {
        try {
          payload = JSON.parse(text)
        } catch {
          payload = null
        }
      }

      if (response.ok && payload?.access_token) {
        return { ok: true as const, payload, rawText: text }
      }

      const reason = payload?.error_description || payload?.error || text || `HTTP ${response.status}`
      return {
        ok: false as const,
        reason,
        status: response.status,
        payload,
        rawText: text,
        securityPolicy: this.isSecurityPolicyError(payload, text),
        expiredRefreshToken: this.isRefreshTokenExpired(payload, text),
      }
    }

    let result: Awaited<ReturnType<typeof attemptRefresh>>
    try {
      result = await attemptRefresh()
    } catch (error) {
      throw new Error(`Baidu token refresh failed: ${(error as Error)?.message || 'network error'}`)
    }

    // Follow AList behavior: retry once when response does not contain refresh_token.
    if (result.ok && !result.payload?.refresh_token) {
      try {
        result = await attemptRefresh()
      } catch (error) {
        throw new Error(`Baidu token refresh failed: ${(error as Error)?.message || 'network error'}`)
      }
    }

    if (!result.ok) {
      if (result.expiredRefreshToken) {
        this.tokenRefreshBlockedUntil = Date.now() + BAIDU_TOKEN_RETRY_COOLDOWN_MS
        this.tokenRefreshBlockedReason = 'Baidu refresh_token is invalid or already used. Please update storage config with the latest refresh_token generated from the same client_id/client_secret.'
        throw new Error(this.tokenRefreshBlockedReason)
      }
      if (result.securityPolicy) {
        this.tokenRefreshBlockedUntil = Date.now() + BAIDU_TOKEN_RETRY_COOLDOWN_MS
        this.tokenRefreshBlockedReason = 'Baidu token refresh blocked by security policy. Please use your own Baidu OAuth client and matching refresh_token, or retry later.'
        throw new Error(this.tokenRefreshBlockedReason)
      }
      throw new Error(`Baidu token refresh failed: HTTP ${result.status} - ${String(result.reason).slice(0, 200)}`)
    }

    const payload = result.payload

    this.accessToken = payload.access_token
    const expiresIn = Number(payload.expires_in || 0)
    this.accessTokenExpiresAt = Date.now() + Math.max(expiresIn - 60, 60) * 1000
    if (typeof payload.refresh_token === 'string' && payload.refresh_token.trim()) {
      const latestRefreshToken = payload.refresh_token.trim()
      this.config.refreshToken = latestRefreshToken
      await this.persistRefreshToken(previousRefreshToken, latestRefreshToken)
    }
    this.tokenRefreshBlockedUntil = 0
    this.tokenRefreshBlockedReason = undefined
    return this.accessToken
  }

  private async ensureAccessToken(): Promise<string> {
    if (this.accessToken && Date.now() < this.accessTokenExpiresAt) {
      return this.accessToken
    }

    if (!this.refreshLock) {
      this.refreshLock = this.refreshAccessToken()
        .finally(() => {
          this.refreshLock = undefined
        })
    }

    return this.refreshLock
  }

  private async parseApiResponse<T = any>(
    response: Response,
    action: string,
  ): Promise<BaiduApiResponse<T>> {
    if (!response.ok) {
      const text = await response.text().catch(() => '')
      throw new Error(`Baidu ${action} failed: HTTP ${response.status}${text ? ` - ${text.slice(0, 200)}` : ''}`)
    }

    const payload = (await response.json().catch(() => null)) as BaiduApiResponse<T> | null
    if (!payload) {
      throw new Error(`Baidu ${action} failed: invalid JSON response`)
    }

    if (payload.errno !== undefined && payload.errno !== 0) {
      throw new Error(`Baidu ${action} failed: errno=${payload.errno}${payload.errmsg ? ` (${payload.errmsg})` : ''}`)
    }

    if (payload.error_code !== undefined) {
      throw new Error(`Baidu ${action} failed: error_code=${payload.error_code}${payload.error_msg ? ` (${payload.error_msg})` : ''}`)
    }

    return payload
  }

  private isTokenExpiredError(error: unknown): boolean {
    const message = String((error as Error)?.message || '')
    return message.includes('errno=-6')
      || message.includes('errno=111')
      || message.includes('error_code=111')
      || message.includes('Access token invalid')
  }

  private async requestXpan(
    endpoint: string,
    methodName: string,
    method: 'GET' | 'POST',
    params: Record<string, string>,
    action: string,
    retry = true,
  ): Promise<BaiduApiResponse<any>> {
    const accessToken = await this.ensureAccessToken()
    const url = new URL(endpoint)
    url.searchParams.set('method', methodName)
    url.searchParams.set('access_token', accessToken)

    const options: RequestInit = { method }
    if (method === 'GET') {
      for (const [k, v] of Object.entries(params)) {
        url.searchParams.set(k, v)
      }
    } else {
      options.headers = { 'Content-Type': 'application/x-www-form-urlencoded' }
      options.body = new URLSearchParams(params).toString()
    }

    try {
      const response = await fetch(url.toString(), options)
      return await this.parseApiResponse(response, action)
    } catch (error) {
      if (retry && this.isTokenExpiredError(error)) {
        this.accessToken = undefined
        this.accessTokenExpiresAt = 0
        return this.requestXpan(endpoint, methodName, method, params, action, false)
      }
      throw error
    }
  }

  private async listDirectory(absoluteDir: string): Promise<BaiduListEntry[]> {
    const items: BaiduListEntry[] = []
    let start = 0

    while (true) {
      const params = {
        dir: absoluteDir,
        web: 'web',
        start: String(start),
        limit: String(BAIDU_LIST_PAGE_LIMIT),
      }

      let payload: BaiduApiResponse<BaiduListEntry>
      try {
        payload = await this.requestXpan(
          this.xpanFileEndpoint,
          'list',
          'GET',
          params,
          'list files',
        )
      } catch {
        payload = await this.requestXpan(
          this.xpanFileEndpoint,
          'list',
          'GET',
          {
            ...params,
            path: absoluteDir,
          },
          'list files',
        )
      }

      const list = Array.isArray(payload.list) ? payload.list : []
      if (list.length === 0) break
      items.push(...list)

      if (list.length < BAIDU_LIST_PAGE_LIMIT) break
      start += BAIDU_LIST_PAGE_LIMIT
    }

    return items
  }

  private async getFileEntryByPath(absolutePath: string): Promise<BaiduListEntry | null> {
    const parentDir = this.toAbsolutePath(path.posix.dirname(absolutePath))
    const baseName = path.posix.basename(absolutePath)
    const list = await this.listDirectory(parentDir)
    return list.find((entry) => {
      if (entry.isdir === 1) return false
      if (entry.path === absolutePath) return true
      return entry.server_filename === baseName
    }) || null
  }

  private toStorageObject(relativeKey: string, entry: BaiduListEntry): StorageObject {
    return {
      key: relativeKey,
      size: typeof entry.size === 'number' ? entry.size : undefined,
      etag: entry.md5,
      lastModified: typeof entry.server_mtime === 'number'
        ? new Date(entry.server_mtime * 1000)
        : undefined,
    }
  }

  async create(key: string, fileBuffer: Buffer, contentType?: string): Promise<StorageObject> {
    const rootedKey = this.withRoot(key)
    const absolutePath = this.toAbsolutePath(rootedKey)
    const fileMd5 = createHash('md5').update(fileBuffer).digest('hex')
    const blockList = JSON.stringify([fileMd5])

    const precreate = await this.requestXpan(
      this.xpanFileEndpoint,
      'precreate',
      'POST',
      {
        path: absolutePath,
        size: String(fileBuffer.length),
        isdir: '0',
        autoinit: '1',
        rtype: '3',
        block_list: blockList,
      },
      'precreate file',
    )

    const uploadId = precreate.uploadid as string | undefined
    if (!uploadId) {
      throw new Error('Baidu upload failed: missing uploadid from precreate')
    }

    const accessToken = await this.ensureAccessToken()
    const uploadUrl = new URL(this.pcsUploadEndpoint)
    uploadUrl.searchParams.set('method', 'upload')
    uploadUrl.searchParams.set('type', 'tmpfile')
    uploadUrl.searchParams.set('access_token', accessToken)
    uploadUrl.searchParams.set('path', absolutePath)
    uploadUrl.searchParams.set('uploadid', uploadId)
    uploadUrl.searchParams.set('partseq', '0')

    const formData = new FormData()
    formData.set(
      'file',
      new Blob([new Uint8Array(fileBuffer)], { type: contentType || 'application/octet-stream' }),
      path.posix.basename(absolutePath),
    )

    const uploadResponse = await fetch(uploadUrl.toString(), {
      method: 'POST',
      body: formData,
    })
    await this.parseApiResponse(uploadResponse, 'upload chunk')

    const createResponse = await this.requestXpan(
      this.xpanFileEndpoint,
      'create',
      'POST',
      {
        path: absolutePath,
        size: String(fileBuffer.length),
        isdir: '0',
        uploadid: uploadId,
        rtype: '3',
        block_list: blockList,
      },
      'create file',
    )

    return {
      key: rootedKey,
      size: typeof createResponse.size === 'number' ? createResponse.size : fileBuffer.length,
      etag: fileMd5,
      lastModified: new Date(),
    }
  }

  async delete(key: string): Promise<void> {
    const rootedKey = this.withRoot(key)
    const absolutePath = this.toAbsolutePath(rootedKey)

    await this.requestXpan(
      this.xpanFileEndpoint,
      'filemanager',
      'POST',
      {
        opera: 'delete',
        async: '0',
        filelist: JSON.stringify([{ path: absolutePath }]),
      },
      'delete file',
    )
  }

  async get(key: string): Promise<Buffer | null> {
    const rootedKey = this.withRoot(key)
    const absolutePath = this.toAbsolutePath(rootedKey)

    const entry = await this.getFileEntryByPath(absolutePath)
    if (!entry?.fs_id) return null

    const payload = await this.requestXpan(
      this.xpanMultimediaEndpoint,
      'filemetas',
      'GET',
      {
        fsids: JSON.stringify([entry.fs_id]),
        dlink: '1',
      },
      'get dlink',
    )

    const list = Array.isArray(payload.list) ? payload.list : []
    const dlink = typeof list[0]?.dlink === 'string' ? list[0].dlink : ''
    if (!dlink) return null

    const accessToken = await this.ensureAccessToken()
    const signedDlink = dlink.includes('access_token=')
      ? dlink
      : `${dlink}${dlink.includes('?') ? '&' : '?'}access_token=${encodeURIComponent(accessToken)}`

    // Align with AList official-mode flow: first resolve real download URL via HEAD.
    let downloadUrl = signedDlink
    try {
      const headResponse = await fetch(signedDlink, {
        method: 'HEAD',
        headers: {
          'User-Agent': 'pan.baidu.com',
        },
        redirect: 'manual',
      })
      const redirectedUrl = headResponse.headers.get('location')
      if (redirectedUrl) {
        downloadUrl = redirectedUrl
      }
    } catch {
      // Ignore and continue with signed dlink.
    }

    const response = await fetch(downloadUrl, {
      method: 'GET',
      headers: {
        'User-Agent': 'pan.baidu.com',
      },
      redirect: 'follow',
    })

    if (!response.ok) return null
    const arrayBuffer = await response.arrayBuffer().catch(() => null)
    return arrayBuffer ? Buffer.from(arrayBuffer) : null
  }

  getPublicUrl(key: string): string {
    const rootedKey = this.withRoot(key)
    if (this.config.cdnUrl) {
      const encoded = rootedKey.split('/').map(seg => encodeURIComponent(seg)).join('/')
      return `${this.config.cdnUrl.replace(/\/$/, '')}/${encoded}`
    }
    const encoded = rootedKey.split('/').map(seg => encodeURIComponent(seg)).join('/')
    return `/image/${encoded}`
  }

  async getFileMeta(key: string): Promise<StorageObject | null> {
    const rootedKey = this.withRoot(key)
    const absolutePath = this.toAbsolutePath(rootedKey)
    const entry = await this.getFileEntryByPath(absolutePath)
    if (!entry) return null
    return this.toStorageObject(rootedKey, entry)
  }

  async listAll(): Promise<StorageObject[]> {
    const root = this.toAbsolutePath(this.normalizedRoot())
    const result: StorageObject[] = []

    const walk = async (absoluteDir: string) => {
      const list = await this.listDirectory(absoluteDir)
      for (const entry of list) {
        const entryPath = typeof entry.path === 'string' ? entry.path : ''
        if (!entryPath) continue

        if (entry.isdir === 1) {
          await walk(entryPath)
          continue
        }

        const relativeKey = entryPath.replace(/^\/+/, '')
        result.push(this.toStorageObject(relativeKey, entry))
      }
    }

    await walk(root)
    return result
  }

  async listImages(): Promise<StorageObject[]> {
    const all = await this.listAll()
    return all.filter((obj) => /\.(jpe?g|png|webp|gif|bmp|tiff?|heic|heif)$/i.test(obj.key))
  }
}
