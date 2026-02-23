<script lang="ts" setup>
definePageMeta({
  layout: 'dashboard',
})

useHead({
  title: $t('title.securitySettings'),
})

const toast = useToast()

const { data: accessStatus, refresh: refreshStatus } = await useFetch<{
  enabled: boolean
  verified: boolean
}>('/api/access/check')

const isEnabled = computed(() => accessStatus.value?.enabled ?? false)

const oldPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const isLoading = ref(false)

const canSubmit = computed(() => {
  if (isEnabled.value && !oldPassword.value) return false
  // 允许新密码为空（表示清除密码）
  if (newPassword.value && newPassword.value !== confirmPassword.value) return false
  return true
})

const onSubmit = async () => {
  if (!canSubmit.value) return

  if (newPassword.value && newPassword.value !== confirmPassword.value) {
    toast.add({
      color: 'error',
      title: $t('access.settings.passwordMismatch'),
    })
    return
  }

  isLoading.value = true
  try {
    await $fetch('/api/access/password', {
      method: 'PUT',
      body: {
        password: newPassword.value,
        oldPassword: oldPassword.value || undefined,
      },
    })
    toast.add({
      color: 'success',
      title: newPassword.value
        ? $t('access.settings.passwordSet')
        : $t('access.settings.passwordCleared'),
    })
    // Reset form
    oldPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    await refreshStatus()
  } catch (error: any) {
    toast.add({
      color: 'error',
      title: $t('access.settings.saveFailed'),
      description: error?.data?.statusMessage,
    })
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="$t('title.securitySettings')" />
    </template>

    <template #body>
      <div class="space-y-6 max-w-6xl">
        <UCard variant="outline">
          <template #header>
            <div class="flex items-center gap-2">
              <UIcon
                name="tabler:shield-lock"
                class="text-lg"
              />
              <span>{{ $t('access.settings.title') }}</span>
            </div>
          </template>

          <div class="space-y-2 mb-4">
            <div class="flex items-center gap-2">
              <UChip
                :color="isEnabled ? 'success' : 'neutral'"
                size="md"
                inset
                standalone
              />
              <span class="text-sm text-(--ui-text-muted)">
                {{ isEnabled ? $t('access.settings.statusEnabled') : $t('access.settings.statusDisabled') }}
              </span>
            </div>
            <p class="text-sm text-(--ui-text-dimmed)">
              {{ $t('access.settings.description') }}
            </p>
          </div>

          <form
            id="accessPasswordForm"
            class="space-y-4"
            @submit.prevent="onSubmit"
          >
            <UFormField
              v-if="isEnabled"
              :label="$t('access.settings.oldPassword')"
            >
              <UInput
                v-model="oldPassword"
                type="password"
                :placeholder="$t('access.settings.oldPasswordPlaceholder')"
                class="w-full max-w-md"
              />
            </UFormField>

            <UFormField :label="$t('access.settings.newPassword')">
              <UInput
                v-model="newPassword"
                type="password"
                :placeholder="$t('access.settings.newPasswordPlaceholder')"
                class="w-full max-w-md"
              />
              <template #hint>
                <span class="text-xs text-(--ui-text-dimmed)">
                  {{ $t('access.settings.newPasswordHint') }}
                </span>
              </template>
            </UFormField>

            <UFormField
              v-if="newPassword"
              :label="$t('access.settings.confirmPassword')"
            >
              <UInput
                v-model="confirmPassword"
                type="password"
                :placeholder="$t('access.settings.confirmPasswordPlaceholder')"
                class="w-full max-w-md"
              />
            </UFormField>
          </form>

          <template #footer>
            <UButton
              :loading="isLoading"
              :disabled="!canSubmit"
              type="submit"
              form="accessPasswordForm"
              variant="soft"
              icon="tabler:device-floppy"
            >
              {{ $t('access.settings.save') }}
            </UButton>
          </template>
        </UCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
