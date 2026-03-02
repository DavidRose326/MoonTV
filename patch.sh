#!/bin/sh
set -e

echo "🚀 [Arch] 正在应用 V01 基础设施固化版"

# -----------------------------------------------------------------------------
# 1. UI屏蔽与图片中转配置 (解决CN无图问题)
# -----------------------------------------------------------------------------
sed -i 's|let imageProxy =.*|let imageProxy = "/api/image-proxy?url=";|g' src/app/layout.tsx
sed -i 's|let enableRegister =.*|let enableRegister = false;|g' src/app/layout.tsx
sed -i 's|: null;|: "/api/image-proxy?url=";|g' src/lib/utils.ts

# -----------------------------------------------------------------------------
# 2. 🚦 纯净透传 API 实现
# -----------------------------------------------------------------------------
mkdir -p src/app/api/search
cat << 'EOT' > src/app/api/search/route.ts
import { NextResponse } from 'next/server';
import { getAvailableApiSites, getCacheTime } from '@/lib/config';
import { searchFromApi } from '@/lib/downstream';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const query = searchParams.get('q');
  if (!query) return NextResponse.json({ results:[] });

  const apiSites = await getAvailableApiSites();
  try {
    const allResults = (await Promise.all(apiSites.map((s: any) => searchFromApi(s, query)))).flat();
    const cacheTime = await getCacheTime();
    return NextResponse.json({ results: allResults }, { headers: { 'Cache-Control': `public, max-age=${cacheTime}` } });
  } catch (error) { return NextResponse.json({ error: 'err' }, { status: 500 }); }
}
EOT

# 重写Search One API
mkdir -p src/app/api/search/one
cat << 'EOT' > src/app/api/search/one/route.ts
import { NextResponse } from 'next/server';
import { getAvailableApiSites, getCacheTime } from '@/lib/config';
import { searchFromApi } from '@/lib/downstream';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const query = searchParams.get('q');
  const resourceId = searchParams.get('resourceId');
  if (!query || !resourceId) return NextResponse.json({ results: [] });

  const apiSites = await getAvailableApiSites();
  const targetSite = apiSites.find((site: any) => site.key === resourceId);
  if (!targetSite) return NextResponse.json({ results: [] });

  try {
    const results = await searchFromApi(targetSite, query);
    const exactMatches = results.filter((r: any) => r.title === query);
    return NextResponse.json({ results: exactMatches });
  } catch (error) { return NextResponse.json({ results: [] }); }
}
EOT

# -----------------------------------------------------------------------------
# 3. 🧹 环境清理与构建优化
# -----------------------------------------------------------------------------

# 移除所有edge运行时声明
for f in $(find src/app -type f \( -name "*.ts" -o -name "*.tsx" \)); do
  grep -v "export const runtime = 'edge';" "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  grep -v 'export const runtime = "edge";' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
done

# 修复 downstream.ts 的 TypeScript 错误
sed -i 's/filter((item) =>/filter((item: any) =>/g' src/lib/downstream.ts

# 修复登录页面，强制显示用户名输入框
sed -i 's/const \[shouldAskUsername, setShouldAskUsername\] = useState(false);/const [shouldAskUsername, setShouldAskUsername] = useState(true);/' src/app/login/page.tsx

# 配置启动脚本和Next.js配置
# sed -i 's|/login|/|g' start.js
cat << 'EOT' > next.config.js
module.exports = require('next-pwa')({ dest: 'public', disable: process.env.NODE_ENV === 'development', register: true, skipWaiting: true })({
  output: 'standalone',
  typescript: { ignoreBuildErrors: true },
  eslint: { ignoreDuringBuilds: true },
  optimizeFonts: false,
  images: { unoptimized: true, remotePatterns:[{ protocol: 'https', hostname: '**' }] },
  webpack(config) {
    const fileLoaderRule = config.module.rules.find((rule) => rule.test?.test?.('.svg'));
    if (fileLoaderRule) {
      config.module.rules.push({ ...fileLoaderRule, test: /\.svg$/i, resourceQuery: /url/ }, { test: /\.svg$/i, issuer: { not: /\.(css|scss|sass)$/ }, resourceQuery: { not: /url/ }, loader: '@svgr/webpack', options: { dimensions: false, titleProp: true } });
      fileLoaderRule.exclude = /\.svg$/i;
    }
    config.resolve.fallback = { ...config.resolve.fallback, net: false, tls: false, crypto: false };
    return config;
  },
});
EOT

# ----------------------------------------------------------
# 4. 🧹 完成
# -----------------------------------------------------------------------------

echo "✅ [Arch] V01 补丁应用成功！"
