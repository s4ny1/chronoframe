import type { AListCompatibleStorageConfig } from '~~/shared/types/storage'
import type { Logger } from '../../../utils/logger'
import type { StorageProvider, StorageObject } from '../interfaces'

type AListApiResponse<T = any> = {
  code?: number
  message?: string
  data?: T
}

export class AListStorageProvider implements StorageProvider {
  config: AListCompatibleStorageConfig
  private logger?: Logger['storage']
  private token?: string

  constructor(config: AListCompatibleStorageConfig, logger?: Logger['storage']) {
    this.config = config
    this.logger = logger
  }

  private get baseUrl() {
    return this.config.baseUrl.replace(/\/$/, '')
  }

  private get pathField(): string {
    return this.config.pathField || 'path'
  }

  private normalizedRoot(): string {
    return (this.config.rootPath || '').replace(/\/+$/g, '').replace(/^\/+/, '')
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

  private async parseApiResponse<T = any>(
    resp: Response,
    action: string,
  ): Promise<AListApiResponse<T> | null> {
    if (!resp.ok) {
      const text = await resp.text().catch(() => '')
      throw new Error(`AList ${action} failed: HTTP ${resp.status}${text ? ` - ${text.slice(0, 200)}` : ''}`)
    }

    const text = await resp.text().catch(() => '')
    if (!text) return null

    let payload: AListApiResponse<T>
    try {
      payload = JSON.parse(text) as AListApiResponse<T>
    } catch {
      throw new Error(`AList ${action} failed: invalid JSON response`)
    }

    // AList API success contract: code === 200.
    if (typeof payload.code === 'number' && payload.code !== 200) {
      throw new Error(`AList ${action} failed: [${payload.code}] ${payload.message || 'Unknown error'}`)
    }

    return payload
  }

  private async loginWithPassword(): Promise<string | null> {
    const username = this.config.username?.trim()
    const password = this.config.password
    if (!username || !password) return null

    const loginEndpoint = this.config.loginEndpoint || '/api/auth/login'
    const loginResp = await fetch(`${this.baseUrl}${loginEndpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username,
        password,
        otp_code: this.config.otpCode || '',
      }),
    })

    const payload = await this.parseApiResponse<{ token?: string }>(loginResp, 'login')
    const token = payload?.data?.token
    if (!token) {
      throw new Error('AList login failed: token missing in response')
    }
    this.token = token
    return token
  }

  private async ensureAuthToken(): Promise<string> {
    if (this.token) return this.token

    if (this.config.token?.trim()) {
      this.token = this.config.token.trim()
      return this.token
    }

    const token = await this.loginWithPassword()
    if (token) return token

    throw new Error('AList auth requires token or username/password credentials.')
  }

  private async request(path: string, init: RequestInit = {}): Promise<Response> {
    const token = await this.ensureAuthToken()
    const headers: Record<string, string> = {
      ...(init.headers as Record<string, string> | undefined),
      Authorization: token,
    }

    const url = `${this.baseUrl}${path}`
    const response = await fetch(url, { ...init, headers })

    // Retry once when token is obtained by username/password.
    if (
      response.status === 401
      && !this.config.token
      && this.config.username
      && this.config.password
    ) {
      this.token = undefined
      const refreshedToken = await this.ensureAuthToken()
      headers.Authorization = refreshedToken
      return fetch(url, { ...init, headers })
    }

    return response
  }

  async create(key: string, fileBuffer: Buffer, contentType?: string): Promise<StorageObject> {
    const rootedKey = this.withRoot(key)
    const absolutePath = this.toAbsolutePath(rootedKey)
    const uploadPath = this.config.uploadEndpoint || '/api/fs/put'

    const response = await this.request(uploadPath, {
      method: 'PUT',
      headers: {
        'Content-Type': contentType || 'application/octet-stream',
        'Content-Length': String(fileBuffer.length),
        // AList requires URL-encoded File-Path header for stream upload.
        'File-Path': encodeURIComponent(absolutePath),
      },
      body: new Uint8Array(fileBuffer),
    })
    await this.parseApiResponse(response, 'upload')

    const meta = await this.getFileMeta(rootedKey)
    return meta || {
      key: rootedKey,
      size: fileBuffer.length,
      lastModified: new Date(),
    }
  }

  async delete(key: string): Promise<void> {
    const deletePath = this.config.deleteEndpoint || '/api/fs/remove'
    const rootedKey = this.withRoot(key)
    const normalized = rootedKey.replace(/^\/+/, '')
    const slashIndex = normalized.lastIndexOf('/')
    const dir = this.toAbsolutePath(
      slashIndex >= 0 ? normalized.slice(0, slashIndex) : this.normalizedRoot(),
    )
    const name = slashIndex >= 0 ? normalized.slice(slashIndex + 1) : normalized

    const response = await this.request(deletePath, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ dir, names: [name] }),
    })
    await this.parseApiResponse(response, 'remove')
  }

  async get(key: string): Promise<Buffer | null> {
    const rootedKey = this.withRoot(key)

    if (this.config.downloadEndpoint) {
      const urlPath = `${this.config.downloadEndpoint}?${encodeURIComponent(this.pathField)}=${encodeURIComponent(rootedKey)}`
      const response = await this.request(urlPath, { method: 'GET' })
      if (!response.ok) return null
      const arrayBuffer = await response.arrayBuffer().catch(() => null)
      return arrayBuffer ? Buffer.from(arrayBuffer) : null
    }

    const absolutePath = this.toAbsolutePath(rootedKey)
    const meta = await this.getFileMetaWithRefresh(rootedKey)
    const rawUrl = (meta as any)?.raw_url as string | undefined
    const sign = (meta as any)?.sign as string | undefined

    if (rawUrl) {
      try {
        const response = await fetch(rawUrl, {
          headers: { 'User-Agent': 'pan.baidu.com' },
          redirect: 'follow',
        })
        if (response.ok) {
          const arrayBuffer = await response.arrayBuffer().catch(() => null)
          if (arrayBuffer && arrayBuffer.byteLength > 0) {
            return Buffer.from(arrayBuffer)
          }
        }
      } catch (error) {
        this.logger?.warn('AList raw_url fetch failed', error)
      }
    }

    const signQuery = sign ? `?sign=${encodeURIComponent(sign)}` : ''
    try {
      const response = await fetch(`${this.baseUrl}/d${absolutePath}${signQuery}`, {
        method: 'GET',
      })
      if (!response.ok) return null
      const arrayBuffer = await response.arrayBuffer().catch(() => null)
      return arrayBuffer ? Buffer.from(arrayBuffer) : null
    } catch (error) {
      this.logger?.warn('AList /d fetch failed', error)
      return null
    }
  }

  getPublicUrl(key: string): string {
    const rootedKey = this.withRoot(key)
    return `/image/${rootedKey}`
  }

  private async getFileMetaWithRefresh(rootedKey: string): Promise<StorageObject | null> {
    const metaPath = this.config.metaEndpoint || '/api/fs/get'
    const absolutePath = this.toAbsolutePath(rootedKey)
    const payload = {
      [this.pathField]: absolutePath,
      password: '',
      page: 1,
      per_page: 0,
      refresh: true,
    }

    const response = await this.request(metaPath, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })

    const result = await this.parseApiResponse<any>(response, 'get metadata')
    const node = result?.data
    if (!node) return null

    const output: StorageObject = {
      key: rootedKey,
      size: typeof node.size === 'number' ? node.size : undefined,
      lastModified: node.modified ? new Date(node.modified) : undefined,
      etag: typeof node.etag === 'string' ? node.etag : undefined,
    }
    ;(output as any).raw_url = typeof node.raw_url === 'string' ? node.raw_url : undefined
    ;(output as any).sign = typeof node.sign === 'string' ? node.sign : undefined
    return output
  }

  async getFileMeta(key: string): Promise<StorageObject | null> {
    const rootedKey = this.withRoot(key)
    const metaPath = this.config.metaEndpoint || '/api/fs/get'
    const payload = {
      [this.pathField]: this.toAbsolutePath(rootedKey),
      password: '',
      page: 1,
      per_page: 0,
      refresh: false,
    }

    const response = await this.request(metaPath, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })

    const result = await this.parseApiResponse<any>(response, 'get metadata')
    const node = result?.data
    if (!node) return null

    const output: StorageObject = {
      key: rootedKey,
      size: typeof node.size === 'number' ? node.size : undefined,
      lastModified: node.modified ? new Date(node.modified) : undefined,
      etag: typeof node.etag === 'string' ? node.etag : undefined,
    }
    ;(output as any).raw_url = typeof node.raw_url === 'string' ? node.raw_url : undefined
    ;(output as any).sign = typeof node.sign === 'string' ? node.sign : undefined
    return output
  }

  async listAll(): Promise<StorageObject[]> {
    const listPath = this.config.listEndpoint || '/api/fs/list'
    const rootPath = this.normalizedRoot()

    const response = await this.request(listPath, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        [this.pathField]: this.toAbsolutePath(rootPath),
        password: '',
        page: 1,
        per_page: 0,
        refresh: false,
      }),
    })

    const payload = await this.parseApiResponse<{ content?: any[] }>(response, 'list files')
    const content = payload?.data?.content
    if (!Array.isArray(content)) return []

    return content
      .map((item) => {
        const name = typeof item?.name === 'string' ? item.name : ''
        const rawPath = typeof item?.path === 'string' ? item.path.replace(/^\/+/, '') : ''
        const relativePath = rawPath || (rootPath ? `${rootPath}/${name}` : name)
        if (!relativePath) return null

        return {
          key: relativePath,
          size: typeof item?.size === 'number' ? item.size : undefined,
          lastModified: item?.modified ? new Date(item.modified) : undefined,
          etag: typeof item?.etag === 'string' ? item.etag : undefined,
        } as StorageObject
      })
      .filter(Boolean) as StorageObject[]
  }

  async listImages(): Promise<StorageObject[]> {
    const all = await this.listAll()
    return all.filter((obj) => /\.(jpe?g|png|webp|gif|bmp|tiff?|heic|heif)$/i.test(obj.key))
  }
}

export { AListStorageProvider as OpenListStorageProvider }
