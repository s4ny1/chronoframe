import en from './locales/en.json'
import ja from './locales/ja.json'
import zhHans from './locales/zh-Hans.json'
import zhHantHK from './locales/zh-Hant-HK.json'
import zhHantTW from './locales/zh-Hant-TW.json'

export default defineI18nConfig(() => {
  return {
    messages: {
      en,
      ja,
      'zh-Hans': zhHans,
      'zh-Hant-HK': zhHantHK,
      'zh-Hant-TW': zhHantTW,
    },
    fallbackLocale: {
      'zh-CN': ['zh-Hans'],
      'zh-SG': ['zh-Hans'],
      'zh': ['zh-Hans'],
      'zh-Hant': ['zh-Hant-TW', 'zh-Hant-HK'],
      'zh-TW': ['zh-Hant-TW'],
      'zh-HK': ['zh-Hant-HK'],
      'zh-MO': ['zh-Hant-HK'],
      'default': ['en'],
    },
  }
})
