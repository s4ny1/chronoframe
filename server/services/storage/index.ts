export { StorageProvider, StorageObject } from './interfaces'

export {
  s3StorageConfigSchema,
  localStorageConfigSchema,
  alistStorageConfigSchema,
  openListStorageConfigSchema,
  storageConfigSchema,
} from '~~/shared/types/storage'

export {
  S3StorageConfig,
  LocalStorageConfig,
  AListStorageConfig,
  AListCompatibleStorageConfig,
  OpenListStorageConfig,
  StorageConfig,
} from '~~/shared/types/storage'

export { StorageProviderFactory, StorageManager } from './manager'

export type { StorageManagerEventType, StorageManagerEventListener, StorageManagerEvent } from './manager'

export { S3StorageProvider } from './providers/s3'
export { LocalStorageProvider } from './providers/local'
export { AListStorageProvider } from './providers/openlist'
export { OpenListStorageProvider } from './providers/openlist'

export {
  setGlobalStorageManager,
  getGlobalStorageManager,
  isStorageManagerInitialized,
} from './events'

