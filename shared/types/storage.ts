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
  alistStorageConfigSchema,
  openListStorageConfigSchema,
])

export type StorageConfig = z.infer<typeof storageConfigSchema>

export type S3StorageConfig = z.infer<typeof s3StorageConfigSchema>
export type LocalStorageConfig = z.infer<typeof localStorageConfigSchema>
export type AListStorageConfig = z.infer<typeof alistStorageConfigSchema>
export type OpenListStorageConfig = z.infer<typeof openListStorageConfigSchema>
export type AListCompatibleStorageConfig = Omit<AListStorageConfig, 'provider'> & {
  provider: 'alist' | 'openlist'
}
