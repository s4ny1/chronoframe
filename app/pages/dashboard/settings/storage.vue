<script lang="ts" setup>
import { UChip, UButton } from '#components'
import type { TableColumn } from '@nuxt/ui'
import {
  baiduStorageConfigSchema,
  alistStorageConfigSchema,
  s3StorageConfigSchema,
  localStorageConfigSchema,
  openListStorageConfigSchema,
  type StorageConfig,
} from '~~/shared/types/storage'

definePageMeta({
  layout: 'dashboard',
})

useHead({
  title: $t('title.storageSettings'),
})

const toast = useToast()

const { data: currentStorageProvider, refresh: refreshCurrentStorageProvider } =
  await useFetch<{
    namespace: string
    key: string
    value: SettingValue
  }>('/api/system/settings/storage/provider')

const { data: availableStorage, refresh: refreshAvailableStorage } =
  await useFetch<SettingStorageProvider[]>(
    '/api/system/settings/storage-config',
  )

const PROVIDER_ICON = {
  s3: 'tabler:brand-aws',
  local: 'tabler:database',
  baidu: 'tabler:brand-baidu',
  alist: 'tabler:stack',
  openlist: 'tabler:cloud',
}

const availableStorageColumns: TableColumn<SettingStorageProvider>[] = [
  {
    accessorKey: 'status',
    header: '',
    meta: {
      class: {
        th: 'w-10',
      },
    },
    cell: (cell) => {
      const isActive =
        currentStorageProvider.value?.value === cell.row.original.id
      return h(UChip, {
        size: 'md',
        inset: true,
        standalone: true,
        color: isActive ? 'success' : undefined,
        ui: {
          base: !isActive ? 'bg-neutral-200 dark:bg-neutral-700' : '',
        },
      })
    },
  },
  { accessorKey: 'name', header: 'Storage Name' },
  { accessorKey: 'provider', header: 'Storage Type' },
  {
    accessorKey: 'actions',
    header: 'Actions',
    cell: (cell) => {
      const row = cell.row.original
      const canTest = row.provider === 's3' || row.provider === 'baidu' || row.provider === 'alist' || row.provider === 'openlist'
      const isTesting = testingStorageId.value === row.id
      return h('div', { class: 'flex items-center gap-2' }, [
        canTest
          ? h(
              UButton,
              {
                size: 'sm',
                variant: 'soft',
                color: 'primary',
                icon: isTesting ? 'tabler:loader-2' : 'tabler:plug-connected',
                loading: isTesting,
                disabled: isTesting,
                onClick: () => onStorageTest(row.id),
              },
              { default: () => 'Test Connection' },
            )
          : null,
        h(
          UButton,
          {
            size: 'sm',
            variant: 'soft',
            color: 'error',
            icon: 'tabler:trash',
            disabled:
              currentStorageProvider.value?.value === row.id,
            onClick: () => onStorageDelete(row.id),
          },
          { default: () => 'Delete' },
        ),
      ])
    },
  },
]

const storageSettingsState = reactive<{
  storageConfigId?: number
}>({
  storageConfigId: currentStorageProvider.value
    ? (currentStorageProvider.value.value as number)
    : undefined,
})

const handleStorageSettingsSubmit = async (close?: () => void) => {
  try {
    await $fetch('/api/system/settings/storage/provider', {
      method: 'PUT',
      body: {
        value: storageSettingsState.storageConfigId,
      },
    })
    refreshCurrentStorageProvider()
    close?.()
    toast.add({
      title: 'Settings saved',
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Failed to save settings',
      description: (error as Error).message,
      color: 'error',
    })
  }
}

const providerOptions = [
  { label: 'AWS S3 Compatible', value: 's3', icon: PROVIDER_ICON.s3 },
  { label: 'Local Storage', value: 'local', icon: PROVIDER_ICON.local },
  { label: 'Baidu Netdisk', value: 'baidu', icon: PROVIDER_ICON.baidu },
  { label: 'AList', value: 'alist', icon: PROVIDER_ICON.alist },
]

const storageConfigState = reactive<{
  name: string
  provider: string
  config: Partial<StorageConfig>
}>({
  name: '',
  provider: 's3',
  config: {
    provider: 's3',
    region: 'auto',
    prefix: '/photos',
  } as any,
})

// Select schema based on provider.
const currentStorageSchema = computed(() => {
  const provider = storageConfigState.provider
  switch (provider) {
    case 'local':
      return localStorageConfigSchema
    case 'baidu':
      return baiduStorageConfigSchema
    case 'alist':
      return alistStorageConfigSchema
    case 'openlist':
      return openListStorageConfigSchema
    case 's3':
    default:
      return s3StorageConfigSchema
  }
})

// Default storage config by provider.
const getStorageConfigDefaults = (provider: string): Partial<StorageConfig> => {
  switch (provider) {
    case 'local':
      return {
        provider: 'local',
        basePath: '/data/storage',
        baseUrl: '/storage',
      } as any
    case 'baidu':
      return {
        provider: 'baidu',
        refreshToken: '',
        clientId: 'hq9yQ9w9kR4YHj1kyYafLygVocobh7Sf',
        clientSecret: 'YH2VpZcFJHYNnV6vLfHQXDBhcE7ZChyE',
        rootPath: '/apps/chronoframe',
      } as any
    case 'alist':
      return {
        provider: 'alist',
        uploadEndpoint: '/api/fs/put',
        listEndpoint: '/api/fs/list',
        deleteEndpoint: '/api/fs/remove',
        metaEndpoint: '/api/fs/get',
        pathField: 'path',
      } as any
    case 's3':
    default:
      return {
        provider: 's3',
        region: 'auto',
        prefix: '/photos',
      } as any
  }
}

// Build fields-config dynamically (with i18n keys).
const storageFieldsConfig = computed<Record<string, any>>(() => {
  const provider = storageConfigState.provider
  const baseKey = provider === 'alist'
    ? 'settings.storage.openlist'
    : `settings.storage.${provider}`

  switch (provider) {
    case 'local':
      return {
        provider: { hidden: true },
        basePath: {
          label: $t(`${baseKey}.basePath.label`),
          description: $t(`${baseKey}.basePath.description`),
        },
        baseUrl: {
          label: $t(`${baseKey}.baseUrl.label`),
          description: $t(`${baseKey}.baseUrl.description`),
        },
        prefix: {
          label: $t(`${baseKey}.prefix.label`),
          description: $t(`${baseKey}.prefix.description`),
        },
      }
    case 'baidu':
      return {
        provider: { hidden: true },
        refreshToken: {
          label: $t(`${baseKey}.refreshToken.label`),
          description: $t(`${baseKey}.refreshToken.description`),
        },
        clientId: {
          label: $t(`${baseKey}.clientId.label`),
          description: $t(`${baseKey}.clientId.description`),
        },
        clientSecret: {
          label: $t(`${baseKey}.clientSecret.label`),
          description: $t(`${baseKey}.clientSecret.description`),
        },
        rootPath: {
          label: $t(`${baseKey}.rootPath.label`),
          description: $t(`${baseKey}.rootPath.description`),
        },
        cdnUrl: {
          label: $t(`${baseKey}.cdnUrl.label`),
          description: $t(`${baseKey}.cdnUrl.description`),
        },
      }
    case 'alist':
      return {
        provider: { hidden: true },
        baseUrl: {
          label: $t(`${baseKey}.baseUrl.label`),
          description: $t(`${baseKey}.baseUrl.description`),
        },
        rootPath: {
          label: $t(`${baseKey}.rootPath.label`),
          description: $t(`${baseKey}.rootPath.description`),
        },
        token: {
          label: $t(`${baseKey}.token.label`),
          description: $t(`${baseKey}.token.description`),
        },
        username: {
          label: $t(`${baseKey}.username.label`),
          description: $t(`${baseKey}.username.description`),
        },
        password: {
          label: $t(`${baseKey}.password.label`),
          description: $t(`${baseKey}.password.description`),
        },
        otpCode: {
          label: $t(`${baseKey}.otpCode.label`),
          description: $t(`${baseKey}.otpCode.description`),
        },
        loginEndpoint: {
          label: $t(`${baseKey}.loginEndpoint.label`),
          description: $t(`${baseKey}.loginEndpoint.description`),
        },
        uploadEndpoint: {
          label: $t(`${baseKey}.uploadEndpoint.label`),
          description: $t(`${baseKey}.uploadEndpoint.description`),
        },
        downloadEndpoint: {
          label: $t(`${baseKey}.downloadEndpoint.label`),
          description: $t(`${baseKey}.downloadEndpoint.description`),
        },
        listEndpoint: {
          label: $t(`${baseKey}.listEndpoint.label`),
          description: $t(`${baseKey}.listEndpoint.description`),
        },
        deleteEndpoint: {
          label: $t(`${baseKey}.deleteEndpoint.label`),
          description: $t(`${baseKey}.deleteEndpoint.description`),
        },
        metaEndpoint: {
          label: $t(`${baseKey}.metaEndpoint.label`),
          description: $t(`${baseKey}.metaEndpoint.description`),
        },
        pathField: {
          label: $t(`${baseKey}.pathField.label`),
          description: $t(`${baseKey}.pathField.description`),
        },
        cdnUrl: {
          label: $t(`${baseKey}.cdnUrl.label`),
          description: $t(`${baseKey}.cdnUrl.description`),
        },
      }
    case 's3':
    default:
      return {
        provider: { hidden: true },
        bucket: {
          label: $t(`${baseKey}.bucket.label`),
          description: $t(`${baseKey}.bucket.description`),
        },
        region: {
          label: $t(`${baseKey}.region.label`),
          description: $t(`${baseKey}.region.description`),
        },
        endpoint: {
          label: $t(`${baseKey}.endpoint.label`),
          description: $t(`${baseKey}.endpoint.description`),
        },
        prefix: {
          label: $t(`${baseKey}.prefix.label`),
          description: $t(`${baseKey}.prefix.description`),
        },
        cdnUrl: {
          label: $t(`${baseKey}.cdnUrl.label`),
          description: $t(`${baseKey}.cdnUrl.description`),
        },
        accessKeyId: {
          label: $t(`${baseKey}.accessKeyId.label`),
          description: $t(`${baseKey}.accessKeyId.description`),
        },
        secretAccessKey: {
          label: $t(`${baseKey}.secretAccessKey.label`),
          description: $t(`${baseKey}.secretAccessKey.description`),
        },
        forcePathStyle: {
          label: $t(`${baseKey}.forcePathStyle.label`),
          description: $t(`${baseKey}.forcePathStyle.description`),
        },
        maxKeys: {
          label: $t(`${baseKey}.maxKeys.label`),
          description: $t(`${baseKey}.maxKeys.description`),
        },
      }
  }
})

const onStorageConfigSubmit = async (
  event: { data: Partial<StorageConfig> },
  close?: () => void,
) => {
  try {
    const payload = {
      name: storageConfigState.name,
      provider: storageConfigState.provider,
      config: event.data,
    }

    await $fetch('/api/system/settings/storage-config', {
      method: 'POST',
      body: payload,
    })
    refreshAvailableStorage()
    toast.add({
      title: 'Storage configuration created',
      color: 'success',
    })
    // Reset form state
    storageConfigState.name = ''
    storageConfigState.provider = 's3'
    storageConfigState.config = getStorageConfigDefaults('s3')
    close?.()
  } catch (error) {
    toast.add({
      title: 'Failed to create storage configuration',
      description: (error as Error).message,
      color: 'error',
    })
  }
}

const testingStorageId = ref<number | null>(null)

const onStorageTest = async (storageId: number) => {
  testingStorageId.value = storageId
  try {
    const result = await $fetch<{ success: boolean; message: string }>(
      `/api/system/settings/storage-config/${storageId}/test`,
      { method: 'POST' },
    )
    toast.add({
      title: result.message,
      color: 'success',
      icon: 'tabler:circle-check',
    })
  } catch (error: any) {
    toast.add({
      title: 'Connection test failed',
      description: error?.data?.statusMessage || error?.message || 'Unknown error',
      color: 'error',
      icon: 'tabler:circle-x',
    })
  } finally {
    testingStorageId.value = null
  }
}

const onStorageDelete = async (storageId: number) => {
  try {
    await $fetch(`/api/system/settings/storage-config/${storageId}`, {
      method: 'DELETE',
    })
    refreshAvailableStorage()
    toast.add({
      title: 'Storage configuration deleted',
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Failed to delete storage configuration',
      description: (error as Error).message,
      color: 'error',
    })
  }
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="$t('title.storageSettings')" />
    </template>

    <template #body>
      <div class="space-y-6 max-w-6xl">
        <UCard variant="outline">
          <div class="space-y-4">
            <UFormField
              name="storageConfigId"
              label="Storage Profile"
              required
              :ui="{
                container: 'w-full sm:max-w-sm *:w-full',
              }"
            >
              <USelectMenu
                v-model="storageSettingsState.storageConfigId"
                :icon="
                  PROVIDER_ICON[
                    availableStorage?.find(
                      (item) =>
                        item.id === storageSettingsState.storageConfigId,
                    )?.provider || 'local'
                  ] || 'tabler:database'
                "
                :items="
                  availableStorage?.map((item) => ({
                    icon: PROVIDER_ICON[item.provider] || 'tabler:database',
                    label: item.name,
                    value: item.id,
                  }))
                "
                label-key="label"
                value-key="value"
                placeholder="Select a storage profile"
              />
            </UFormField>
          </div>

          <template #footer>
            <div class="flex items-center gap-3">
              <UModal
                title="Switch Storage Profile"
                :ui="{ footer: 'justify-end' }"
              >
                <UButton
                  variant="soft"
                  icon="tabler:device-floppy"
                >
                  Save Settings
                </UButton>

                <template #body>
                  <UAlert
                    color="neutral"
                    variant="subtle"
                    title="Notice"
                    description="Files uploaded after switching storage will be saved to the new provider. Existing files are not migrated automatically."
                    icon="tabler:arrows-exchange"
                  />
                </template>

                <template #footer="{ close }">
                  <UButton
                    label="Cancel"
                    color="neutral"
                    variant="outline"
                    @click="close"
                  />
                  <UButton
                    label="Continue"
                    variant="soft"
                    icon="tabler:arrows-exchange"
                    type="submit"
                    form="storageSettingsForm"
                    @click="handleStorageSettingsSubmit(close)"
                  />
                </template>
              </UModal>
            </div>
          </template>
        </UCard>

        <UCard
          variant="outline"
          :ui="{
            body: 'p-0 sm:p-0',
          }"
        >
          <template #header>
            <div class="w-full flex items-center justify-between">
              <span>Storage Profile Management</span>
              <div>
                <USlideover
                  title="Create Storage Profile"
                  :ui="{ footer: 'justify-end' }"
                >
                  <UButton
                    size="sm"
                    variant="soft"
                    icon="tabler:plus"
                  >
                    Add Storage
                  </UButton>

                  <template #body="{ close }">
                    <div class="space-y-4">
                      <!-- Provider selection -->
                      <UFormField
                        label="Storage Type"
                        class="w-full"
                        required
                        :ui="{
                          container: 'sm:max-w-full',
                        }"
                      >
                        <USelectMenu
                          v-model="storageConfigState.provider"
                          :icon="
                            PROVIDER_ICON[
                              storageConfigState.provider as keyof typeof PROVIDER_ICON
                            ] || 'tabler:database'
                          "
                          :items="providerOptions"
                          label-key="label"
                          value-key="value"
                          placeholder="Select a storage type"
                          @update:model-value="
                            (val: string) => {
                              storageConfigState.provider = val
                              storageConfigState.config =
                                getStorageConfigDefaults(val)
                            }
                          "
                        />
                      </UFormField>

                      <UFormField
                        label="Storage Name"
                        required
                        :ui="{
                          container: 'sm:max-w-full',
                        }"
                      >
                        <UInput v-model="storageConfigState.name" />
                      </UFormField>

                      <USeparator />

                      <AutoForm
                        id="createStorageForm"
                        :schema="currentStorageSchema"
                        :state="storageConfigState.config"
                        :fields-config="storageFieldsConfig"
                        @submit="onStorageConfigSubmit($event, close)"
                      />
                    </div>
                  </template>

                  <template #footer="{ close }">
                    <UButton
                      label="Cancel"
                      color="neutral"
                      variant="outline"
                      @click="close"
                    />
                    <UButton
                      label="Create Storage"
                      variant="soft"
                      icon="tabler:check"
                      type="submit"
                      form="createStorageForm"
                    />
                  </template>
                </USlideover>
              </div>
            </div>
          </template>

          <div>
            <UTable
              :columns="availableStorageColumns"
              :data="availableStorage"
            />
          </div>
        </UCard>
      </div>
    </template>
  </UDashboardPanel>
</template>

<style scoped></style>


