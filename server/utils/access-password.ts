import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { createHash } from 'node:crypto'

const PASS_FILE = resolve(process.cwd(), 'data', 'pass.txt')

/**
 * 读取访问密码（从 data/pass.txt）
 * 如果文件不存在或为空，返回空字符串表示未设置密码
 */
export function readAccessPassword(): string {
  try {
    if (!existsSync(PASS_FILE)) return ''
    const content = readFileSync(PASS_FILE, 'utf-8').trim()
    return content
  } catch {
    return ''
  }
}

/**
 * 写入访问密码
 * 传入空字符串表示清除密码
 */
export function writeAccessPassword(password: string): void {
  writeFileSync(PASS_FILE, password.trim(), 'utf-8')
}

/**
 * 生成用于 cookie 验证的 hash token
 */
export function hashAccessToken(password: string): string {
  return createHash('sha256').update(`cf-access:${password}`).digest('hex').slice(0, 32)
}
