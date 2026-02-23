import { z } from 'zod'

/**
 * 验证访问密码
 */
export default eventHandler(async (event) => {
  const { password } = await readValidatedBody(
    event,
    z.object({
      password: z.string().min(1),
    }).parse,
  )

  const storedPassword = readAccessPassword()

  if (!storedPassword) {
    throw createError({ statusCode: 400, statusMessage: 'Access password is not set' })
  }

  if (password !== storedPassword) {
    throw createError({ statusCode: 401, statusMessage: 'Invalid password' })
  }

  // 设置验证 cookie，7 天过期
  setCookie(event, 'cf-access-verified', hashAccessToken(storedPassword), {
    httpOnly: true,
    maxAge: 60 * 60 * 24 * 7,
    path: '/',
    sameSite: 'lax',
  })

  return { success: true }
})
