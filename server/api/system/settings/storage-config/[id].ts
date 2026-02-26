import { z } from 'zod'
import { settingsManager } from '~~/server/services/settings/settingsManager'
import { getGlobalStorageManager } from '~~/server/services/storage/events'
import { logger } from '~~/server/utils/logger'
import {
  baiduStorageConfigSchema,
  alistStorageConfigSchema,
  localStorageConfigSchema,
  openListStorageConfigSchema,
  s3StorageConfigSchema,
} from '~~/server/services/storage'

export default eventHandler(async (event) => {
  const session = await requireUserSession(event)
  if (!session.user.isAdmin) {
    throw createError({
      statusCode: 403,
      statusMessage: 'Forbidden',
    })
  }

  const { id: storageConfigId } = await getValidatedRouterParams(
    event,
    z.object({
      id: z.string().transform((val) => parseInt(val, 10)),
    }).parse,
  )

  const storageConfig =
    await settingsManager.storage.getProviderById(storageConfigId)

  if (!storageConfig) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Storage configuration not found',
    })
  }

  switch (event.method) {
    case 'GET':
      return storageConfig
    case 'PUT': {
      const updatedStorageConfig = await readValidatedBody(
        event,
        z.discriminatedUnion('provider', [
          z.object({
            name: z.string().optional(),
            provider: z.literal('s3'),
            config: s3StorageConfigSchema.partial(),
          }),
          z.object({
            name: z.string().optional(),
            provider: z.literal('local'),
            config: localStorageConfigSchema.partial(),
          }),
          z.object({
            name: z.string().optional(),
            provider: z.literal('baidu'),
            config: baiduStorageConfigSchema.partial(),
          }),
          z.object({
            name: z.string().optional(),
            provider: z.literal('alist'),
            config: alistStorageConfigSchema.partial(),
          }),
          z.object({
            name: z.string().optional(),
            provider: z.literal('openlist'),
            config: openListStorageConfigSchema.partial(),
          }),
        ]).parse,
      )

      await settingsManager.storage.updateProvider(
        storageConfigId,
        updatedStorageConfig,
      )

      const activeProviderId = await settingsManager.get<number>('storage', 'provider')
      if (activeProviderId === storageConfigId) {
        const updatedProvider = await settingsManager.storage.getProviderById(storageConfigId)
        const storageManager = getGlobalStorageManager()
        if (updatedProvider && storageManager) {
          await storageManager.registerProvider(updatedProvider.config as any, logger.storage)
        }
      }

      return { success: true }
    }
    case 'DELETE': {
      await settingsManager.storage.deleteProvider(storageConfigId)
      return { success: true }
    }
    default: {
      throw createError({
        statusCode: 405,
        statusMessage: 'Method Not Allowed',
      })
    }
  }
})
