#!/usr/bin/env node
import { migrate } from 'drizzle-orm/better-sqlite3/migrator'
import { drizzle } from 'drizzle-orm/better-sqlite3'
import Database from 'better-sqlite3'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import { existsSync, mkdirSync } from 'fs'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

console.log('Running database migrations...')

try {
  const databasePath = process.env.DATABASE_URL || './data/app.sqlite3'
  const requireExisting = process.env.DATABASE_REQUIRE_EXISTING === 'true'

  if (!databasePath.startsWith('file:') && !databasePath.startsWith(':memory:')) {
    const normalizedPath = databasePath.replace(/\\/g, '/')
    const lastSlash = normalizedPath.lastIndexOf('/')
    if (lastSlash > 0) {
      const dbDir = normalizedPath.slice(0, lastSlash)
      if (!existsSync(dbDir)) {
        mkdirSync(dbDir, { recursive: true })
      }
    }

    if (requireExisting && !existsSync(databasePath)) {
      throw new Error(`Database file not found: ${databasePath}`)
    }
  }

  console.log(`Using database: ${databasePath}`)
  const sqlite = new Database(databasePath)
  const db = drizzle(sqlite)

  await migrate(db, {
    migrationsFolder: join(__dirname, '../server/database/migrations'),
  })

  console.log('Database migrations completed successfully!')
  sqlite.close()
} catch (error) {
  console.error('Migration failed:', error)
  process.exit(1)
}
