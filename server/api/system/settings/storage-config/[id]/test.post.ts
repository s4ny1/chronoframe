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
