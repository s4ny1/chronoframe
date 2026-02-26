import { ListObjectsCommand, S3Client } from '@aws-sdk/client-s3'
import { z } from 'zod'
import { settingsManager } from '~~/server/services/settings/settingsManager'

type AListTestConfig = {
  baseUrl?: string
  rootPath?: string
  token?: string
  username?: string
  password?: string
  otpCode?: string
  loginEndpoint?: string
  metaEndpoint?: string
  pathField?: string
}

type BaiduTestConfig = {
  refreshToken?: string
  clientId?: string
  clientSecret?: string
  rootPath?: string
  tokenEndpoint?: string
  xpanFileEndpoint?: string
}

const DEFAULT_BAIDU_CLIENT_ID = 'hq9yQ9w9kR4YHj1kyYafLygVocobh7Sf'
const DEFAULT_BAIDU_CLIENT_SECRET = 'YH2VpZcFJHYNnV6vLfHQXDBhcE7ZChyE'

async function loginAList(config: AListTestConfig): Promise<string> {
  if (config.token?.trim()) {
    return config.token.trim()
  }

  if (!config.username || !config.password) {
    throw new Error('AList auth requires token or username/password.')
  }

  const loginEndpoint = config.loginEndpoint || '/api/auth/login'
  const loginUrl = `${config.baseUrl!.replace(/\/$/, '')}${loginEndpoint}`
  const response = await fetch(loginUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: config.username,
      password: config.password,
      otp_code: config.otpCode || '',
    }),
    signal: AbortSignal.timeout(10_000),
  })

  if (!response.ok) {
    const text = await response.text().catch(() => '')
    throw new Error(`AList login failed: HTTP ${response.status}${text ? ` - ${text.slice(0, 200)}` : ''}`)
  }

  const payload = await response.json().catch(() => null) as any
  if (payload?.code !== 200 || !payload?.data?.token) {
    throw new Error(`AList login failed: ${payload?.message || 'invalid response'}`)
  }
  return payload.data.token as string
}

async function loginBaidu(config: BaiduTestConfig): Promise<string> {
  if (!config.refreshToken) {
    throw new Error('Missing required Baidu config: refreshToken.')
  }

  const params = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: config.refreshToken,
    client_id: config.clientId || DEFAULT_BAIDU_CLIENT_ID,
    client_secret: config.clientSecret || DEFAULT_BAIDU_CLIENT_SECRET,
  })

  const endpoint = config.tokenEndpoint || 'https://openapi.baidu.com/oauth/2.0/token'
  const response = await fetch(`${endpoint}?${params.toString()}`, {
    method: 'GET',
    signal: AbortSignal.timeout(10_000),
  })

  if (!response.ok) {
    const text = await response.text().catch(() => '')
    const lower = text.toLowerCase()
    if (lower.includes('expired_token') || lower.includes('refresh token has been used')) {
      throw new Error('Baidu refresh_token is invalid or already used. Please generate a new refresh_token using the same client_id/client_secret.')
    }
    if (lower.includes('trigger security policy')) {
      throw new Error('Baidu OAuth request was blocked by security policy. Please retry later or use your own OAuth client credentials.')
    }
    throw new Error(`Baidu token refresh failed: HTTP ${response.status}${text ? ` - ${text.slice(0, 200)}` : ''}`)
  }

  const payload = await response.json().catch(() => null) as any
  if (!payload?.access_token) {
    throw new Error(`Baidu token refresh failed: ${payload?.error_description || payload?.error || 'invalid response'}`)
  }
  return payload.access_token as string
}

export default eventHandler(async (event) => {
  const session = await requireUserSession(event)
  if (!session.user.isAdmin) {
    throw createError({ statusCode: 403, statusMessage: 'Forbidden' })
  }

  const { id: storageConfigId } = await getValidatedRouterParams(
    event,
    z.object({
      id: z.string().transform((val) => parseInt(val, 10)),
    }).parse,
  )

  const storageConfig = await settingsManager.storage.getProviderById(storageConfigId)
  if (!storageConfig) {
    throw createError({ statusCode: 404, statusMessage: 'Storage configuration not found' })
  }

  const config = storageConfig.config as any

  try {
    if (storageConfig.provider === 's3') {
      const { accessKeyId, secretAccessKey, region, endpoint, bucket, forcePathStyle } = config
      if (!accessKeyId || !secretAccessKey || !bucket) {
        throw new Error('Missing required S3 config: accessKeyId, secretAccessKey, or bucket.')
      }

      const client = new S3Client({
        endpoint,
        region: region || 'auto',
        forcePathStyle: forcePathStyle ?? false,
        responseChecksumValidation: 'WHEN_REQUIRED',
        requestChecksumCalculation: 'WHEN_REQUIRED',
        credentials: { accessKeyId, secretAccessKey },
      })
      await client.send(new ListObjectsCommand({ Bucket: bucket, MaxKeys: 1 }))
      return { success: true, message: 'S3 storage connection successful' }
    }

    if (storageConfig.provider === 'alist' || storageConfig.provider === 'openlist') {
      const aListConfig = config as AListTestConfig
      if (!aListConfig.baseUrl) {
        throw new Error('Missing required AList config: baseUrl.')
      }

      const token = await loginAList(aListConfig)
      const endpoint = (aListConfig.metaEndpoint || '/api/fs/get').replace(/^\//, '')
      const url = `${aListConfig.baseUrl.replace(/\/$/, '')}/${endpoint}`
      const field = aListConfig.pathField || 'path'
      const root = aListConfig.rootPath || '/photos'
      const absolutePath = `/${root.replace(/^\/+/, '')}`

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: token,
        },
        body: JSON.stringify({
          [field]: absolutePath,
          password: '',
          page: 1,
          per_page: 1,
          refresh: false,
        }),
        signal: AbortSignal.timeout(10_000),
      })

      if (!response.ok) {
        const text = await response.text().catch(() => '')
        throw new Error(`AList service error: HTTP ${response.status}${text ? ` - ${text.slice(0, 200)}` : ''}`)
      }

      const payload = await response.json().catch(() => null) as any
      if (payload?.code !== 200) {
        throw new Error(`AList service error: [${payload?.code ?? 'unknown'}] ${payload?.message || 'invalid response'}`)
      }

      return { success: true, message: 'AList storage connection successful' }
    }

    if (storageConfig.provider === 'baidu') {
      const baiduConfig = config as BaiduTestConfig
      const accessToken = await loginBaidu(baiduConfig)
      const xpanEndpoint = baiduConfig.xpanFileEndpoint || 'https://pan.baidu.com/rest/2.0/xpan/file'
      const rootPath = baiduConfig.rootPath || '/apps/chronoframe'
      const normalizedRootPath = rootPath.startsWith('/') ? rootPath : `/${rootPath}`

      const url = new URL(xpanEndpoint)
      url.searchParams.set('method', 'list')
      url.searchParams.set('access_token', accessToken)
      url.searchParams.set('dir', normalizedRootPath)
      url.searchParams.set('web', 'web')
      url.searchParams.set('limit', '10')
      url.searchParams.set('start', '0')

      const response = await fetch(url.toString(), {
        method: 'GET',
        signal: AbortSignal.timeout(10_000),
      })

      if (!response.ok) {
        const text = await response.text().catch(() => '')
        throw new Error(`Baidu service error: HTTP ${response.status}${text ? ` - ${text.slice(0, 200)}` : ''}`)
      }

      const payload = await response.json().catch(() => null) as any
      if (payload?.errno !== 0) {
        throw new Error(`Baidu service error: errno=${payload?.errno ?? 'unknown'}${payload?.errmsg ? ` (${payload.errmsg})` : ''}`)
      }

      return { success: true, message: 'Baidu Netdisk connection successful' }
    }

    throw createError({
      statusCode: 400,
      statusMessage: `Unsupported storage provider for connection test: ${storageConfig.provider}`,
    })
  } catch (error: any) {
    if (error?.statusCode) throw error
    throw createError({
      statusCode: 502,
      statusMessage: error?.message || 'Connection test failed',
    })
  }
})
