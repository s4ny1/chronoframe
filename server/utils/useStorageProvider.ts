import type { H3Event, EventHandlerRequest } from 'h3'
import type { StorageProvider } from '../services/storage'

export const useStorageProvider = (event: H3Event<EventHandlerRequest>) => {
  if (!event.context?.storage) {
    throw new Error(
      'Storage provider not found: storage manager was not initialized. '
      + 'Check server startup logs for storage configuration errors, '
      + 'or complete the onboarding wizard and restart the server.',
    )
  }
  const storageProvider =
    event.context.storage.getProvider() as StorageProvider
  if (!storageProvider) {
    throw new Error(
      'Storage provider not found: no active provider configured. '
      + 'Set an active storage provider in Settings or via environment variables.',
    )
  }
  return { storageProvider }
}
