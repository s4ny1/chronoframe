import { z } from 'zod'

export const s3StorageConfigSchema = z.object({
  provider: z.literal('s3'),
  bucket: z.string(),
  region: z.string().default('auto'),
  endpoint: z.string(),
  prefix: z.string().default('/photos').optional(),
  cdnUrl: z.string().optional(),
  accessKeyId: z.string(),
  secretAccessKey: z.string(),
  forcePathStyle: z.boolean().optional(),
  maxKeys: z.number().optional(),
})

export const localStorageConfigSchema = z.object({
  provider: z.literal('local'),
  basePath: z.string().min(1),
  baseUrl: z.string().optional(),
  prefix: z.string().optional(),
})

const baiduStorageConfigFields = {
  refreshToken: z.string().min(1),
  clientId: z.string().min(1).optional(),
  clientSecret: z.string().min(1).optional(),
  rootPath: z.string().default('/apps/chronoframe').optional(),
  tokenEndpoint: z.string().default('https://openapi.baidu.com/oauth/2.0/token').optional(),
  xpanFileEndpoint: z.string().default('https://pan.baidu.com/rest/2.0/xpan/file').optional(),
  xpanMultimediaEndpoint: z.string().default('https://pan.baidu.com/rest/2.0/xpan/multimedia').optional(),
  pcsUploadEndpoint: z.string().default('https://d.pcs.baidu.com/rest/2.0/pcs/superfile2').optional(),
  cdnUrl: z.string().optional(),
} as const

export const baiduStorageConfigSchema = z.object({
  provider: z.literal('baidu'),
  ...baiduStorageConfigFields,
})

const aListStorageConfigFields = {
  baseUrl: z.string().min(1),
  rootPath: z.string().min(1),
  token: z.string().optional(),
  username: z.string().optional(),
  password: z.string().optional(),
  otpCode: z.string().optional(),
  loginEndpoint: z.string().default('/api/auth/login').optional(),
  uploadEndpoint: z.string().default('/api/fs/put').optional(),
  downloadEndpoint: z.string().optional(),
  listEndpoint: z.string().optional(),
  deleteEndpoint: z.string().default('/api/fs/remove').optional(),
  metaEndpoint: z.string().default('/api/fs/get').optional(),
  pathField: z.string().default('path').optional(),
  cdnUrl: z.string().optional(),
} as const

export const alistStorageConfigSchema = z.object({
  provider: z.literal('alist'),
  ...aListStorageConfigFields,
})

// Backward compatibility for existing OpenList configurations.
export const openListStorageConfigSchema = z.object({
  provider: z.literal('openlist'),
  ...aListStorageConfigFields,
})

export const storageConfigSchema = z.discriminatedUnion('provider', [
  s3StorageConfigSchema,
  localStorageConfigSchema,
  baiduStorageConfigSchema,
  alistStorageConfigSchema,
  openListStorageConfigSchema,
])

export type StorageConfig = z.infer<typeof storageConfigSchema>

export type S3StorageConfig = z.infer<typeof s3StorageConfigSchema>
export type LocalStorageConfig = z.infer<typeof localStorageConfigSchema>
export type BaiduStorageConfig = z.infer<typeof baiduStorageConfigSchema>
export type AListStorageConfig = z.infer<typeof alistStorageConfigSchema>
export type OpenListStorageConfig = z.infer<typeof openListStorageConfigSchema>
export type AListCompatibleStorageConfig = Omit<AListStorageConfig, 'provider'> & {
  provider: 'alist' | 'openlist'
}
