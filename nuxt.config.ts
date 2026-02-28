import pkg from './package.json'
import tailwindcss from '@tailwindcss/vite'
import type { AnalyticsConfig } from './shared/types/config'

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: false },

  modules: [
    'reka-ui/nuxt',
    '@nuxt/ui',
    '@nuxt/eslint',
    '@nuxt/fonts',
    '@nuxt/icon',
    '@nuxt/image',
    '@nuxt/test-utils',
    '@pinia/nuxt',
    'motion-v/nuxt',
    'nuxt-auth-utils',
    '@vueuse/nuxt',
    'dayjs-nuxt',
    '@nuxtjs/i18n',
    'nuxt-mapbox',
    'nuxt-maplibre',
    'nuxt-og-image',
    'nuxt-gtag',
  ],

  css: ['~/assets/css/tailwind.css'],

  components: [{ path: '~/components/ui', pathPrefix: false }, '~/components'],

  runtimeConfig: {
    public: {
      VERSION: pkg.version,
      mapbox: {
        accessToken: '',
      },
      app: {
        title: 'ChronoFrame',
        slogan: '',
        author: '',
        avatarUrl: '',
      },
      map: {
        provider: 'maplibre' as 'mapbox' | 'maplibre',
        mapbox: {
          style: ''
        },
        maplibre: {
          token: '',
          style: '',
        }
      },
      analytics: {
        matomo: {
          enabled: false,
          url: '',
          siteId: '',
        },
      } satisfies AnalyticsConfig,
      oauth: {
        github: {
          enabled: false,
        },
      },
    },
    mapbox: {
      accessToken: '',
    },
    nominatim: {
      baseUrl: 'https://nominatim.openstreetmap.org',
    },
    STORAGE_PROVIDER: 's3' satisfies 's3' | 'local' | 'baidu' | 'alist' | 'openlist',
    provider: {
      s3: {
        endpoint: '',
        bucket: '',
        region: 'auto',
        accessKeyId: '',
        secretAccessKey: '',
        prefix: '',
        cdnUrl: '',
        forcePathStyle: false,
      },
      local: {
        localPath: './data/storage',
        baseUrl: '/storage',
        prefix: 'photos/',
      },
      baidu: {
        refreshToken: process.env.NUXT_PROVIDER_BAIDU_REFRESH_TOKEN || '',
        clientId: process.env.NUXT_PROVIDER_BAIDU_CLIENT_ID || 'hq9yQ9w9kR4YHj1kyYafLygVocobh7Sf',
        clientSecret: process.env.NUXT_PROVIDER_BAIDU_CLIENT_SECRET || 'YH2VpZcFJHYNnV6vLfHQXDBhcE7ZChyE',
        rootPath: process.env.NUXT_PROVIDER_BAIDU_ROOT_PATH || '/apps/chronoframe',
        tokenEndpoint: process.env.NUXT_PROVIDER_BAIDU_TOKEN_ENDPOINT || 'https://openapi.baidu.com/oauth/2.0/token',
        xpanFileEndpoint: process.env.NUXT_PROVIDER_BAIDU_XPAN_FILE_ENDPOINT || 'https://pan.baidu.com/rest/2.0/xpan/file',
        xpanMultimediaEndpoint: process.env.NUXT_PROVIDER_BAIDU_XPAN_MULTIMEDIA_ENDPOINT || 'https://pan.baidu.com/rest/2.0/xpan/multimedia',
        pcsUploadEndpoint: process.env.NUXT_PROVIDER_BAIDU_PCS_UPLOAD_ENDPOINT || 'https://d.pcs.baidu.com/rest/2.0/pcs/superfile2',
        cdnUrl: process.env.NUXT_PROVIDER_BAIDU_CDN_URL || '',
      },
      alist: {
        baseUrl: process.env.NUXT_PROVIDER_ALIST_BASE_URL || process.env.NUXT_PROVIDER_OPENLIST_BASE_URL || '',
        rootPath: process.env.NUXT_PROVIDER_ALIST_ROOT_PATH || process.env.NUXT_PROVIDER_OPENLIST_ROOT_PATH || '',
        token: process.env.NUXT_PROVIDER_ALIST_TOKEN || process.env.NUXT_PROVIDER_OPENLIST_TOKEN || '',
        username: process.env.NUXT_PROVIDER_ALIST_USERNAME || '',
        password: process.env.NUXT_PROVIDER_ALIST_PASSWORD || '',
        otpCode: process.env.NUXT_PROVIDER_ALIST_OTP_CODE || '',
        loginEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_LOGIN || '/api/auth/login',
        uploadEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_UPLOAD || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_UPLOAD || '/api/fs/put',
        downloadEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_DOWNLOAD || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_DOWNLOAD || '',
        listEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_LIST || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_LIST || '/api/fs/list',
        deleteEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_DELETE || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_DELETE || '/api/fs/remove',
        metaEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_META || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_META || '/api/fs/get',
        pathField: process.env.NUXT_PROVIDER_ALIST_PATH_FIELD || process.env.NUXT_PROVIDER_OPENLIST_PATH_FIELD || 'path',
        cdnUrl: process.env.NUXT_PROVIDER_ALIST_CDN_URL || process.env.NUXT_PROVIDER_OPENLIST_CDN_URL || '',
      } as {
        baseUrl: string;
        rootPath: string;
        token: string;
        username: string;
        password: string;
        otpCode: string;
        loginEndpoint: string;
        uploadEndpoint: string;
        downloadEndpoint: string;
        listEndpoint: string;
        deleteEndpoint: string;
        metaEndpoint: string;
        pathField: string;
        cdnUrl: string;
      },
      // Deprecated alias for backward compatibility.
      openlist: {
        baseUrl: process.env.NUXT_PROVIDER_ALIST_BASE_URL || process.env.NUXT_PROVIDER_OPENLIST_BASE_URL || '',
        rootPath: process.env.NUXT_PROVIDER_ALIST_ROOT_PATH || process.env.NUXT_PROVIDER_OPENLIST_ROOT_PATH || '',
        token: process.env.NUXT_PROVIDER_ALIST_TOKEN || process.env.NUXT_PROVIDER_OPENLIST_TOKEN || '',
        username: process.env.NUXT_PROVIDER_ALIST_USERNAME || '',
        password: process.env.NUXT_PROVIDER_ALIST_PASSWORD || '',
        otpCode: process.env.NUXT_PROVIDER_ALIST_OTP_CODE || '',
        loginEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_LOGIN || '/api/auth/login',
        uploadEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_UPLOAD || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_UPLOAD || '/api/fs/put',
        downloadEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_DOWNLOAD || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_DOWNLOAD || '',
        listEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_LIST || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_LIST || '/api/fs/list',
        deleteEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_DELETE || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_DELETE || '/api/fs/remove',
        metaEndpoint: process.env.NUXT_PROVIDER_ALIST_ENDPOINT_META || process.env.NUXT_PROVIDER_OPENLIST_ENDPOINT_META || '/api/fs/get',
        pathField: process.env.NUXT_PROVIDER_ALIST_PATH_FIELD || process.env.NUXT_PROVIDER_OPENLIST_PATH_FIELD || 'path',
        cdnUrl: process.env.NUXT_PROVIDER_ALIST_CDN_URL || process.env.NUXT_PROVIDER_OPENLIST_CDN_URL || '',
      },
    },
    upload: {
      mime: {
        whitelistEnabled: true,
        whitelist:
          'image/jpeg,image/png,image/webp,image/gif,image/bmp,image/tiff,image/heic,image/heif,video/quicktime,video/mp4',
      },
      duplicateCheck: {
        enabled: true,
        mode: 'skip' as 'warn' | 'block' | 'skip',
      },
    },
    /** @deprecated Defaults to allow insecure cookies now */
    allowInsecureCookie: false,
  },

  nitro: {
    preset: 'node_server',
    experimental: {
      websocket: true,
      tasks: true,
    },
  },

  vite: {
    plugins: [tailwindcss() as any],
    optimizeDeps: {
      include: [
        'zod',
        'dayjs',
        'dayjs/plugin/updateLocale',
        'dayjs/locale/zh-cn',
        'dayjs/locale/zh-hk',
        'dayjs/locale/zh-tw',
        'dayjs/locale/en',
        'dayjs/plugin/relativeTime',
        'dayjs/plugin/utc',
        'dayjs/plugin/timezone',
        'dayjs/plugin/duration',
        'dayjs/plugin/localizedFormat',
        'dayjs/plugin/isBetween',
        '@yeger/vue-masonry-wall',
        'motion-v',
        'swiper/vue',
        'swiper/modules',
        'tailwind-merge',
        'thumbhash',
        'mapbox-gl',
        'maplibre-gl',
        '@indoorequal/vue-maplibre-gl',
        'file-type',
        'reka-ui',
        'es-toolkit',
        'tippy.js',
      ],
    },
    ssr: {
      noExternal: ['@indoorequal/vue-maplibre-gl'],
    },
    css: {
      devSourcemap: true,
    },
    build: {
      sourcemap: false,
      commonjsOptions: {
        include: [/maplibre-gl/, /node_modules/],
        transformMixedEsModules: true,
      },
    },
  },

  gtag: {
    enabled: process.env.NODE_ENV === 'production',
  },

  colorMode: {
    // preference: process.env.NUXT_PUBLIC_COLOR_MODE_PREFERENCE || 'dark',
    storageKey: 'cframe-color-mode',
  },

  icon: {
    clientBundle: {
      scan: true,
    },
  },

  fonts: {
    providers: {
      google: false,
      googleicons: false,
    },
  },

  ogImage: {},

  dayjs: {
    locales: ['zh-cn', 'zh-hk', 'en'],
    plugins: [
      'relativeTime',
      'utc',
      'timezone',
      'duration',
      'localizedFormat',
      'isBetween',
    ],
    defaultTimezone: 'Asia/Shanghai',
  },  i18n: {
    experimental: {
      // Explicitly disable server-side locale detector integration.
      localeDetector: '',
      // Disable i18n route cache wrapper because its bypass callback can run before i18n context exists.
      cacheLifetime: -1,
    },
    detectBrowserLanguage: {
      fallbackLocale: 'en',
      useCookie: false,
      cookieKey: 'chronoframe-locale',
    },
    strategy: 'no_prefix',
    defaultLocale: 'en',
    // Keep locales metadata only. Messages are loaded from i18n/i18n.config.ts
    // to avoid SSR runtime fetching /_i18n/* from localhost.
    locales: [
      { code: 'zh-Hans', name: 'Chinese Simplified', language: 'zh' },
      { code: 'zh-Hant-TW', name: 'Chinese Traditional (TW)', language: 'zh-TW' },
      { code: 'zh-Hant-HK', name: 'Chinese Traditional (HK)', language: 'zh-HK' },
      { code: 'en', name: 'English', language: 'en' },
      { code: 'ja', name: 'Japanese', language: 'ja' },
    ],
  },
})
