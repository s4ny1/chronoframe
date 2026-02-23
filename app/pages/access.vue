<script lang="ts" setup>
definePageMeta({
  layout: false,
})

useHead({
  title: $t('access.title'),
})

const toast = useToast()
const router = useRouter()
const route = useRoute()

const password = ref('')
const isLoading = ref(false)

const onSubmit = async () => {
  if (!password.value.trim()) return

  isLoading.value = true
  try {
    await $fetch('/api/access/verify', {
      method: 'POST',
      body: { password: password.value },
    })
    // 更新全局访问验证状态
    useState<boolean | null>('access-verified').value = true
    const redirect = route.query.redirect?.toString() || '/'
    router.push(redirect)
  } catch (error: any) {
    toast.add({
      color: 'error',
      title: $t('access.error'),
      description: error?.data?.statusMessage || $t('access.invalidPassword'),
    })
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <div class="w-full min-h-svh flex flex-col items-center justify-center p-4 pb-12 bg-(--ui-bg)">
    <div class="w-full max-w-sm space-y-6">
      <div class="text-center space-y-2">
        <UIcon
          name="tabler:lock"
          class="text-4xl text-(--ui-text-muted)"
        />
        <h1 class="text-2xl font-bold text-(--ui-text-highlighted)">
          {{ $t('access.title') }}
        </h1>
        <p class="text-sm text-(--ui-text-muted)">
          {{ $t('access.description') }}
        </p>
      </div>

      <UCard variant="outline">
        <form
          class="space-y-4"
          @submit.prevent="onSubmit"
        >
          <UFormField :label="$t('access.passwordLabel')">
            <UInput
              v-model="password"
              type="password"
              :placeholder="$t('access.passwordPlaceholder')"
              size="lg"
              class="w-full"
              autofocus
            />
          </UFormField>

          <UButton
            type="submit"
            block
            size="lg"
            :loading="isLoading"
            :disabled="!password.trim()"
            icon="tabler:arrow-right"
          >
            {{ $t('access.submit') }}
          </UButton>
        </form>
      </UCard>
    </div>
  </div>
</template>
