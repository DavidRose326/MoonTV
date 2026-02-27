cat << 'EOF' > patch.sh
#!/bin/sh
set -e

echo "🚀 [Arch] 正在应用 V01 基础设施固化版"

# -----------------------------------------------------------------------------
# 1. 🏗️ 基础设施固化 (免密、权限、UI 屏蔽) 禁止修改
# -----------------------------------------------------------------------------

# 劫持鉴权库 - 返回模拟认证信息
cat << 'EOT' > src/lib/auth.ts
import { NextRequest } from 'next/server';
const MOCK = { username: 'Admin', role: 'owner', signature: 'bypass', timestamp: Date.now() };
export function getAuthInfoFromCookie(_req?: NextRequest) { return MOCK; }
export function getAuthInfoFromBrowserCookie() { return MOCK; }
EOT

# 中间件 - 跳过所有认证检查
echo "import { NextResponse } from 'next/server'; export async function middleware() { return NextResponse.next(); } export const config = { matcher:[] };" > src/middleware.ts

# 伪造全套 API 通行证 (OrionTV 必备)
mkdir -p src/app/api/server-config src/app/api/login src/app/api/register src/app/api/logout src/app/api/searchhistory

# 服务器配置API - 返回无需密码
echo "import { NextResponse } from 'next/server'; export async function GET() { return NextResponse.json({ SiteName: process.env.SITE_NAME || '内网影院', StorageType: 'redis', needPassword: false }); }" > src/app/api/server-config/route.ts

# 登录API - 直接设置认证cookie
echo "import { NextResponse } from 'next/server'; export async function POST() { const r = NextResponse.json({ ok: true }); r.cookies.set('auth', encodeURIComponent(JSON.stringify({username:'Admin',role:'owner',signature:'bypass'})), { path: '/', maxAge: 31536000 }); return r; }" > src/app/api/login/route.ts

# 注册API - 直接返回成功
echo "import { NextResponse } from 'next/server'; export async function POST() { return NextResponse.json({ ok: true }); }" > src/app/api/register/route.ts

# 注销API - 直接返回成功
echo "import { NextResponse } from 'next/server'; export async function POST() { return NextResponse.json({ ok: true }); }" > src/app/api/logout/route.ts

# 搜索历史API - 返回空数组
echo "import { NextResponse } from 'next/server'; export async function GET() { return NextResponse.json([]); }" > src/app/api/searchhistory/route.ts

# 物理粉碎Admin权限校验 - 替换环境变量检查为模拟用户信息
find src/app/api/admin -name "*.ts" -exec sed -i "s/process.env.USERNAME/authInfo.username/g" {} +

# UI屏蔽与图片中转配置 (解决CN无图问题)
sed -i 's|let imageProxy =.*|let imageProxy = "/api/image-proxy?url=";|g' src/app/layout.tsx
sed -i 's|let enableRegister =.*|let enableRegister = false;|g' src/app/layout.tsx
sed -i 's|: null;|: "/api/image-proxy?url=";|g' src/lib/utils.ts
if [ -f "src/components/UserMenu.tsx" ]; then sed -i "s/storageType !== 'localstorage'/false/g" src/components/UserMenu.tsx; fi

# -----------------------------------------------------------------------------
# 2. 🚦 纯净透传 API 实现 禁止修改

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
    const allResults = (await Promise.all(apiSites.map((s) => searchFromApi(s, query)))).flat();
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
  const targetSite = apiSites.find((site) => site.key === resourceId);
  if (!targetSite) return NextResponse.json({ results: [] });

  try {
    const results = await searchFromApi(targetSite, query);
    const exactMatches = results.filter((r) => r.title === query);
    return NextResponse.json({ results: exactMatches });
  } catch (error) { return NextResponse.json({ results: [] }); }
}
EOT

# -----------------------------------------------------------------------------
# 3. 🧹 环境清理与构建优化 禁止修改
# -----------------------------------------------------------------------------

# 移除所有edge运行时声明
for f in $(find src/app -type f \( -name "*.ts" -o -name "*.tsx" \)); do
  grep -v "export const runtime = 'edge';" "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  grep -v 'export const runtime = "edge";' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
done

# 配置启动脚本和Next.js配置
sed -i 's|/login|/|g' start.js
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
# 4. 🧹 移除不需要的页面和API 禁止修改
# -----------------------------------------------------------------------------
rm -rf src/app/login src/app/warning src/app/api/change-password


# ----------------------------------------------------------
# 5. 🧹 完成
# -----------------------------------------------------------------------------

echo "✅ [Arch] V01 补丁应用成功！"
EOF

chmod +x patch.sh
bash ./patch.sh
