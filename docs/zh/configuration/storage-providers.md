# 存储提供器配置

ChronoFrame 支持多种存储后端来保存您的照片和缩略图。本文档将详细介绍如何配置不同的存储提供器。

| 提供器                            | 支持 | 适用场景           | 成本         |
| --------------------------------- | :--: | ------------------ | ------------ |
| [**S3 兼容存储**](#s3-兼容存储)   |  ✅  | 生产环境，云存储   | 按使用量计费 |
| [**本地文件系统**](#本地文件系统) |  ✅  | 测试环境，离线部署 | 免费         |
| [**AList**](#alist-存储)    |  ✅  | 个人云存储，NAS    | 免费         |

## S3 兼容存储

S3 兼容存储是最推荐的生产环境选项，支持所有主流云服务提供商。

### 基础配置

```bash
# 设置存储提供器为 S3
NUXT_STORAGE_PROVIDER=s3

# S3 基础配置
NUXT_PROVIDER_S3_ENDPOINT=https://your-s3-endpoint.com
NUXT_PROVIDER_S3_BUCKET=chronoframe-photos
NUXT_PROVIDER_S3_REGION=us-east-1
NUXT_PROVIDER_S3_ACCESS_KEY_ID=your-access-key-id
NUXT_PROVIDER_S3_SECRET_ACCESS_KEY=your-secret-access-key

# 可选配置
NUXT_PROVIDER_S3_PREFIX=photos/
NUXT_PROVIDER_S3_CDN_URL=https://cdn.example.com
NUXT_PROVIDER_S3_FORCE_PATH_STYLE=false
```

### 云服务商配置示例

#### AWS S3

```bash
NUXT_STORAGE_PROVIDER=s3
NUXT_PROVIDER_S3_ENDPOINT=https://s3.amazonaws.com
NUXT_PROVIDER_S3_BUCKET=my-chronoframe-bucket
NUXT_PROVIDER_S3_REGION=us-east-1
NUXT_PROVIDER_S3_ACCESS_KEY_ID=AKIA...
NUXT_PROVIDER_S3_SECRET_ACCESS_KEY=...
NUXT_PROVIDER_S3_CDN_URL=https://d1234567890.cloudfront.net
```

#### Cloudflare R2

```bash
NUXT_STORAGE_PROVIDER=s3
NUXT_PROVIDER_S3_ENDPOINT=https://[account-id].r2.cloudflarestorage.com
NUXT_PROVIDER_S3_BUCKET=chronoframe
NUXT_PROVIDER_S3_REGION=auto
NUXT_PROVIDER_S3_ACCESS_KEY_ID=...
NUXT_PROVIDER_S3_SECRET_ACCESS_KEY=...
NUXT_PROVIDER_S3_CDN_URL=https://photos.example.com
```

#### 阿里云 OSS

```bash
NUXT_STORAGE_PROVIDER=s3
NUXT_PROVIDER_S3_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
NUXT_PROVIDER_S3_BUCKET=chronoframe-photos
NUXT_PROVIDER_S3_REGION=oss-cn-hangzhou
NUXT_PROVIDER_S3_ACCESS_KEY_ID=LTAI...
NUXT_PROVIDER_S3_SECRET_ACCESS_KEY=...
NUXT_PROVIDER_S3_CDN_URL=https://cdn.example.com
```

#### 腾讯云 COS

```bash
NUXT_STORAGE_PROVIDER=s3
NUXT_PROVIDER_S3_ENDPOINT=https://cos.ap-beijing.myqcloud.com
NUXT_PROVIDER_S3_BUCKET=chronoframe-1234567890
NUXT_PROVIDER_S3_REGION=ap-beijing
NUXT_PROVIDER_S3_ACCESS_KEY_ID=AKID...
NUXT_PROVIDER_S3_SECRET_ACCESS_KEY=...
```

#### MinIO 自托管

```bash
NUXT_STORAGE_PROVIDER=s3
NUXT_PROVIDER_S3_ENDPOINT=https://minio.example.com
NUXT_PROVIDER_S3_BUCKET=chronoframe
NUXT_PROVIDER_S3_REGION=us-east-1
NUXT_PROVIDER_S3_ACCESS_KEY_ID=minioadmin
NUXT_PROVIDER_S3_SECRET_ACCESS_KEY=minioadmin
# MinIO 需要启用路径样式访问
NUXT_PROVIDER_S3_FORCE_PATH_STYLE=true
```

### 存储桶配置

#### CORS 设置

推荐的 CORS 配置：

```json
[
  {
    "AllowedOrigins": ["https://your-domain.com"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

## 本地文件系统

本地存储将文件保存在服务器文件系统中。

```bash
# 设置存储提供器为本地
NUXT_STORAGE_PROVIDER=local

# 本地存储配置
NUXT_PROVIDER_LOCAL_PATH=/app/data/storage
NUXT_PROVIDER_LOCAL_BASE_URL=/storage
```

## AList 存储

AList 是一个开源的文件管理系统，提供对各种云存储服务的 API 访问。此提供程序允许您使用与 AList 兼容的服务作为照片存储后端。

| 环境变量 | 类型 | 必需 | 默认值 | 描述 |
|---|---|---|---|---|
| `NUXT_PROVIDER_ALIST_BASE_URL` | string | 是 | - | AList 服务的基础 URL |
| `NUXT_PROVIDER_ALIST_ROOT_PATH` | string | 是 | - | 根存储路径 |
| `NUXT_PROVIDER_ALIST_TOKEN` | string | 可选 | - | API 令牌（推荐） |
| `NUXT_PROVIDER_ALIST_USERNAME` | string | 可选 | - | 登录用户名（未配置 token 时使用） |
| `NUXT_PROVIDER_ALIST_PASSWORD` | string | 可选 | - | 登录密码（未配置 token 时使用） |
| `NUXT_PROVIDER_ALIST_OTP_CODE` | string | 可选 | - | 双因素登录 OTP 验证码 |
| `NUXT_PROVIDER_ALIST_ENDPOINT_LOGIN` | string | 可选 | `/api/auth/login` | 登录端点 |
| `NUXT_PROVIDER_ALIST_ENDPOINT_UPLOAD` | string | 可选 | `/api/fs/put` | 上传端点 |
| `NUXT_PROVIDER_ALIST_ENDPOINT_DOWNLOAD` | string | 可选 | - | 下载端点 |
| `NUXT_PROVIDER_ALIST_ENDPOINT_LIST` | string | 可选 | `/api/fs/list` | 列表端点 |
| `NUXT_PROVIDER_ALIST_ENDPOINT_DELETE` | string | 可选 | `/api/fs/remove` | 删除端点 |
| `NUXT_PROVIDER_ALIST_ENDPOINT_META` | string | 可选 | `/api/fs/get` | 元数据端点 |
| `NUXT_PROVIDER_ALIST_PATH_FIELD` | string | 可选 | `path` | 路径字段名 |
| `NUXT_PROVIDER_ALIST_CDN_URL` | string | 可选 | - | CDN URL |

**认证：**

AList 支持两种认证方式：token 认证或账号登录认证。

```bash
# 推荐：Token 认证
NUXT_PROVIDER_ALIST_TOKEN=your-static-token

# 或：账号密码认证
NUXT_PROVIDER_ALIST_USERNAME=admin
NUXT_PROVIDER_ALIST_PASSWORD=your-password
NUXT_PROVIDER_ALIST_OTP_CODE=
```

### 基础配置

```bash
# 设置存储提供器为 AList
NUXT_STORAGE_PROVIDER=alist

# AList 基础配置
NUXT_PROVIDER_ALIST_BASE_URL=https://your-alist-server.com
NUXT_PROVIDER_ALIST_ROOT_PATH=/chronoframe/photos

# 认证配置 - token（推荐）或账号密码
NUXT_PROVIDER_ALIST_TOKEN=your-api-token
# NUXT_PROVIDER_ALIST_USERNAME=admin
# NUXT_PROVIDER_ALIST_PASSWORD=your-password

# 可选配置
NUXT_PROVIDER_ALIST_ENDPOINT_UPLOAD=/api/fs/put
NUXT_PROVIDER_ALIST_ENDPOINT_DOWNLOAD=
NUXT_PROVIDER_ALIST_ENDPOINT_LIST=/api/fs/list
NUXT_PROVIDER_ALIST_ENDPOINT_DELETE=/api/fs/remove
NUXT_PROVIDER_ALIST_ENDPOINT_META=/api/fs/get
NUXT_PROVIDER_ALIST_PATH_FIELD=path
NUXT_PROVIDER_ALIST_CDN_URL=
```

### 配置示例
#### AList（理论上Alist也可行）

```bash
NUXT_STORAGE_PROVIDER=alist
NUXT_PROVIDER_ALIST_BASE_URL=https://alist.example.com
NUXT_PROVIDER_ALIST_ROOT_PATH=/115pan/chronoframe
NUXT_PROVIDER_ALIST_TOKEN=your-static-token
```

## 常见问题

:::details `The AWS Access Key Id you provided does not exist in our records`
访问密钥错误，检查 `ACCESS_KEY_ID` 和 `SECRET_ACCESS_KEY` 是否正确。
:::

:::details `The specified bucket does not exist`
存储桶不存在，确认存储桶名称正确，且在指定区域存在
:::

:::details 可以上传但无法访问图片，控制台提示 `Access to fetch at '...' from origin '...' has been blocked by CORS policy`
存储桶 CORS 配置错误，参考 [CORS 设置](#CORS-设置) 进行配置。
:::
