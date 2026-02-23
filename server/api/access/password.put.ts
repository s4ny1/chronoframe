import { z } from 'zod'

/**
 * 设置/更新/清除访问密码
 * 需要管理员登录
 */
export default eventHandler(async (event) => {
  await requireUserSession(event)

  const { password, oldPassword } = await readValidatedBody(
    event,
    z.object({
      password: z.string(), // 空字符串表示清除密码
      oldPassword: z.string().optional(),
    }).parse,
  )

  const currentPassword = readAccessPassword()

  // 如果已设置密码，需要验证旧密码
  if (currentPassword && currentPassword !== oldPassword) {
    throw createError({ statusCode: 403, statusMessage: 'Old password is incorrect' })
  }

  writeAccessPassword(password)

  // 如果设置了新密码，更新验证 cookie
  if (password) {
    setCookie(event, 'cf-access-verified', hashAccessToken(password), {
      httpOnly: true,
      maxAge: 60 * 60 * 24 * 7,
      path: '/',
      sameSite: 'lax',
    })
  } else {
    // 清除密码时也清除 cookie
    deleteCookie(event, 'cf-access-verified', { path: '/' })
  }

  return { success: true }
})
