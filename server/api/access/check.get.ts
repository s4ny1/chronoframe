/**
 * 检查访问密码状态
 */
export default eventHandler(async (event) => {
  const password = readAccessPassword()
  const enabled = !!password

  if (!enabled) {
    return { enabled: false, verified: true }
  }

  const cookie = getCookie(event, 'cf-access-verified')
  const verified = cookie === hashAccessToken(password)

  return { enabled, verified }
})
