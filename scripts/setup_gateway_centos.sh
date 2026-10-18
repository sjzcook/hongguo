#!/usr/bin/env bash
#
# 红果短剧 · 自建网关 CentOS 一键部署脚本
#
# 做四件事：
#   1. 装 Node.js 运行时（官方/国内镜像 tarball，不依赖 yum 源和 npm registry）
#   2. 落盘一个零依赖的网关服务（只用 Node 标准库，没有 node_modules）
#   3. 注册 systemd 服务 + 可选 nginx 反向代理 + 防火墙/SELinux 放行
#   4. 自检并打印客户端接入参数
#
# 支持：CentOS 7 / 8 / Stream 9，以及 Rocky / AlmaLinux / RHEL 同版本
#
# 用法：
#   sudo bash setup_gateway_centos.sh                       # 默认 127.0.0.1:8080 + nginx:80
#   sudo bash setup_gateway_centos.sh --port 9000
#   sudo bash setup_gateway_centos.sh --domain api.example.com --email me@example.com
#   sudo bash setup_gateway_centos.sh --no-nginx            # 只跑内网，自己接反代
#   sudo bash setup_gateway_centos.sh --no-auth             # 关闭 X-API-Key 校验（不推荐）
#   bash setup_gateway_centos.sh --dry-run --prefix /tmp/gw # 只生成文件，不改系统
#   sudo bash setup_gateway_centos.sh --uninstall
#
set -euo pipefail

APP_NAME="hongguo-gateway"
APP_DIR="/opt/hongguo-gateway"
ETC_DIR="/etc/hongguo-gateway"
CONF_FILE="$ETC_DIR/config.env"
UNIT_FILE="/etc/systemd/system/${APP_NAME}.service"
NGINX_CONF="/etc/nginx/conf.d/${APP_NAME}.conf"
SVC_USER="hongguo"
NODE_ROOT="/usr/local/lib/nodejs"
REG_DIR="/usr/local/bin"

DEFAULT_PORT=8080
NODE_VER_EL7="18.20.5"   # Node 18 是最后支持 glibc 2.17（EL7）的 LTS
NODE_VER_MODERN="20.18.1"

PORT="$DEFAULT_PORT"
DOMAIN=""
EMAIL=""
USE_NGINX=1
USE_FIREWALL=1
FORCE_CONFIG=0
DISABLE_AUTH=0
DRY_RUN=0
PREFIX=""
ACTION="install"
NODE_VERSION=""

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'
  C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''
fi

log()  { printf '%s[..]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()   { printf '%s[OK]%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn() { printf '%s[!!]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
die()  { printf '%s[XX]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------- 参数解析

while [ $# -gt 0 ]; do
  case "$1" in
    --port)        PORT="${2:-}"; shift 2 ;;
    --domain)      DOMAIN="${2:-}"; shift 2 ;;
    --email)       EMAIL="${2:-}"; shift 2 ;;
    --node-version) NODE_VERSION="${2:-}"; shift 2 ;;
    --no-nginx)    USE_NGINX=0; shift ;;
    --no-firewall) USE_FIREWALL=0; shift ;;
    --no-auth)     DISABLE_AUTH=1; shift ;;
    --force-config) FORCE_CONFIG=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --prefix)      PREFIX="${2:-}"; shift 2 ;;
    --uninstall)   ACTION="uninstall"; shift ;;
    -h|--help)     usage ;;
    *)             die "未知参数：$1（-h 查看用法）" ;;
  esac
done

case "$PORT" in
  ''|*[!0-9]*) die "--port 需要是数字" ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "--port 超出范围"

# ---------------------------------------------------------------- 系统检测

OS_ID=""; OS_MAJOR=""
detect_os() {
  [ -r /etc/os-release ] || die "无法读取 /etc/os-release，这不是受支持的系统"
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_MAJOR="${VERSION_ID:-0}"
  OS_MAJOR="${OS_MAJOR%%.*}"
  case "$OS_ID" in
    centos|rhel|rocky|almalinux|ol|openeuler|kylin) : ;;
    *) warn "未在 $OS_ID 上测试过，继续执行可能失败" ;;
  esac
  ok "系统：$PRETTY_NAME（主版本 $OS_MAJOR）"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "需要 root 权限，请用 sudo 运行"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

# CentOS 7/8 已 EOL，官方 mirror.centos.org 失效，yum 会直接报 404。
fix_eol_repos() {
  case "$OS_MAJOR" in 7|8) : ;; *) return 0 ;; esac
  [ "$OS_ID" = "centos" ] || return 0
  local f
  ls /etc/yum.repos.d/CentOS-*.repo >/dev/null 2>&1 || return 0
  log "CentOS $OS_MAJOR 已 EOL，切换 yum 源到 vault.centos.org"
  for f in /etc/yum.repos.d/CentOS-*.repo; do
    [ -f "${f}.bak" ] || cp -a "$f" "${f}.bak"
    sed -i 's/^mirrorlist=/#mirrorlist=/' "$f"
    sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' "$f"
  done
  ok "yum 源已切换（原文件备份为 *.repo.bak）"
}

# ---------------------------------------------------------------- Node 安装

install_node() {
  if command -v node >/dev/null 2>&1; then
    local major
    major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
    if [ "${major:-0}" -ge 18 ]; then
      ok "已安装 Node $(node -v)，跳过"
      return 0
    fi
    warn "已有 Node $(node -v) 版本过低，将安装新版本到 $NODE_ROOT 并覆盖软链"
  fi

  local ver="$NODE_VER_MODERN"
  [ "$OS_MAJOR" = "7" ] && ver="$NODE_VER_EL7"
  [ -n "$NODE_VERSION" ] && ver="$NODE_VERSION"

  local arch="x64"
  case "$(uname -m)" in
    aarch64|arm64) arch="arm64" ;;
    armv7l)        arch="armv7l" ;;
  esac

  local pkg="node-v${ver}-linux-${arch}.tar.xz"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$NODE_ROOT"

  local base got=0
  for base in https://npmmirror.com/mirrors/node https://nodejs.org/dist; do
    log "下载 $base/v$ver/$pkg"
    if curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 10 -o "$tmp/$pkg" "$base/v$ver/$pkg"; then
      got=1; break
    fi
    warn "镜像不可用，换下一个"
  done
  [ "$got" -eq 1 ] || die "Node 下载失败，请检查网络或手动安装 Node 18+"

  command -v xz >/dev/null 2>&1 || yum install -y xz >/dev/null 2>&1 || true
  tar -xJf "$tmp/$pkg" -C "$NODE_ROOT" || die "解压失败（可能缺少 xz）"
  rm -rf "$tmp"

  local home="$NODE_ROOT/node-v${ver}-linux-${arch}"
  [ -x "$home/bin/node" ] || die "解压后未找到 node 可执行文件"
  ln -sfn "$home/bin/node" "$REG_DIR/node"
  [ -x "$home/bin/npm" ] && ln -sfn "$home/bin/npm" "$REG_DIR/npm"
  [ -x "$home/bin/npx" ] && ln -sfn "$home/bin/npx" "$REG_DIR/npx"

  if ! "$REG_DIR/node" -v >/dev/null 2>&1; then
    die "Node 无法执行，通常是 glibc 版本过低（EL7 需选用 18.x）"
  fi
  ok "Node $("$REG_DIR/node" -v) 已安装到 $home"
}

# ---------------------------------------------------------------- 应用文件

materialize_app() {
  local root="$1"
  mkdir -p "$root/lib/adapters"

  cat > "$root/server.js" <<'HONGUO_SERVER_JS'
#!/usr/bin/env node
/*
 * 红果短剧 · 自建网关
 *
 * 客户端约定（见 lib/data/source/hongguo_source.dart）：
 *   GET /feed?page=1&category=推荐
 *   GET /rank?type=hot&page=1        type: hot | new | finished | ai
 *   GET /search?q=关键词&page=1
 *   GET /drama/{id}
 *   GET /drama/{id}/episodes
 *   GET /categories                  可选
 *
 * 返回体：{"code":0,"data":...}；列表为 {"list":[...],"page":n,"has_more":bool}
 * 字段名与 lib/data/models/drama.dart 对齐（id / title / cover / episode_count …）。
 *
 * 零依赖：只用 Node 标准库，不需要 npm install。
 */
'use strict';

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const VERSION = '1.0.0';
const STARTED_AT = Date.now();

const envStr = (k, d) => {
  const v = process.env[k];
  return v === undefined || v === '' ? d : v;
};
const envNum = (k, d) => {
  const v = parseInt(envStr(k, ''), 10);
  return Number.isFinite(v) ? v : d;
};

const CONFIG = {
  port: envNum('PORT', 8080),
  bind: envStr('BIND', '127.0.0.1'),
  apiKey: envStr('API_KEY', ''),
  upstream: envStr('UPSTREAM', 'http').toLowerCase(),
  upstreamBase: envStr('UPSTREAM_BASE', '').replace(/\/+$/, ''),
  upstreamToken: envStr('UPSTREAM_TOKEN', ''),
  cacheTtl: envNum('CACHE_TTL', 60),
  pageSize: envNum('PAGE_SIZE', 24),
  rateLimit: envNum('RATE_LIMIT', 0),
  allowOrigin: envStr('ALLOW_ORIGIN', '*'),
  timeout: envNum('REQUEST_TIMEOUT', 10000),
  logLevel: envStr('LOG_LEVEL', 'info'),
  // 登录相关
  authSecret: envStr('AUTH_SECRET', ''),
  authCode: envStr('AUTH_CODE', ''),
  authTtlDays: envNum('AUTH_TTL_DAYS', 30),
  freeEpisodes: envNum('FREE_EPISODES', 10),
};

function log(level, msg, extra) {
  if (CONFIG.logLevel === 'error' && level !== 'error') return;
  const rec = Object.assign({ ts: new Date().toISOString(), level, msg }, extra || {});
  const line = JSON.stringify(rec) + '\n';
  if (level === 'error') process.stderr.write(line);
  else process.stdout.write(line);
}

/* ------------------------------------------------------------ 适配器加载 */

function loadAdapter() {
  const file = path.join(__dirname, 'lib', 'adapters', CONFIG.upstream + '.js');
  if (!fs.existsSync(file)) {
    throw new Error('未知的 UPSTREAM「' + CONFIG.upstream + '」，当前只支持 http');
  }
  const mod = require(file);
  if (typeof mod.create !== 'function') {
    throw new Error('适配器 ' + file + ' 缺少 create() 导出');
  }
  return mod.create(CONFIG);
}

/* ------------------------------------------------------------ 响应工具 */

function send(req, res, status, body) {
  const payload = Buffer.from(JSON.stringify(body), 'utf8');
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': String(payload.length),
    'Cache-Control': 'no-store',
    'X-Gateway-Version': VERSION,
    'X-Gateway-Adapter': CONFIG.upstream,
    'Vary': 'Origin',
  };
  if (CONFIG.allowOrigin) {
    headers['Access-Control-Allow-Origin'] = CONFIG.allowOrigin;
    headers['Access-Control-Allow-Headers'] = 'Content-Type, X-API-Key';
    headers['Access-Control-Allow-Methods'] = 'GET, HEAD, OPTIONS';
  }
  res.writeHead(status, headers);
  if (req.method === 'HEAD') res.end();
  else res.end(payload);
}

const okBody = (req, res, data) => send(req, res, 200, { code: 0, data });
const fail = (req, res, status, message) => send(req, res, status, { code: status, message });

/* ------------------------------------------------------------ 登录凭证 */

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function signToken(payload) {
  if (!CONFIG.authSecret) throw new Error('未配置 AUTH_SECRET，无法签发登录凭证');
  const body = b64url(JSON.stringify(payload));
  const mac = crypto.createHmac('sha256', CONFIG.authSecret).update(body).digest();
  return body + '.' + b64url(mac);
}

function verifyToken(token) {
  if (!token || token.indexOf('.') < 0) return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const expected = b64url(
    crypto.createHmac('sha256', CONFIG.authSecret).update(parts[0]).digest(),
  );
  const a = Buffer.from(parts[1]);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let payload;
  try {
    payload = JSON.parse(
      Buffer.from(parts[0].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'),
    );
  } catch (_) {
    return null;
  }
  if (!payload || !payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
  return payload;
}

/// 从 Authorization: Bearer 取当前登录用户，未登录返回 null。
function currentUser(req) {
  const raw = req.headers['authorization'] || '';
  const m = /^Bearer\s+(.+)$/i.exec(raw);
  return m ? verifyToken(m[1].trim()) : null;
}

function readJson(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > (limit || 16384)) {
        req.destroy();
        reject(new Error('请求体过大'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (_) {
        reject(new Error('请求体不是合法 JSON'));
      }
    });
    req.on('error', reject);
  });
}

const isPhone = (v) => /^1[3-9]\d{9}$/.test(String(v || '').trim());

function publicUser(payload) {
  return {
    uid: payload.uid,
    phone: payload.phone,
    nickname: payload.nickname,
    vip_level: payload.vip_level || 0,
    mode: 'gateway',
  };
}

function pageOf(url) {
  const raw = parseInt(url.searchParams.get('page') || '1', 10);
  return Number.isFinite(raw) && raw > 0 ? raw : 1;
}

function paginate(list, page, size) {
  const start = (page - 1) * size;
  return {
    list: list.slice(start, start + size),
    page,
    page_size: size,
    total: list.length,
    has_more: start + size < list.length,
  };
}

/**
 * 适配器有两种返回形态，这里统一成客户端要的结构：
 *   1. 数组        → 视为全量列表，由网关本地分页
 *   2. {list:...}  → 视为上游已经分好页，直接透传，避免二次切分
 */
function listPayload(data, page) {
  if (Array.isArray(data)) return paginate(data, page, CONFIG.pageSize);
  if (data && Array.isArray(data.list)) {
    const size = data.page_size || data.list.length || CONFIG.pageSize;
    return {
      list: data.list,
      page: data.page || page,
      page_size: size,
      total: typeof data.total === 'number' ? data.total : data.list.length,
      has_more: typeof data.has_more === 'boolean' ? data.has_more : data.list.length >= size,
    };
  }
  return paginate([], page, CONFIG.pageSize);
}

/* ------------------------------------------------------------ 缓存 / 限流 */

const cache = new Map();

async function withCache(key, producer) {
  if (CONFIG.cacheTtl <= 0) return producer();
  const hit = cache.get(key);
  const now = Date.now();
  if (hit && hit.expires > now) return hit.value;
  const value = await producer();
  cache.set(key, { value, expires: now + CONFIG.cacheTtl * 1000 });
  if (cache.size > 400) {
    for (const [k, v] of cache) if (v.expires <= now) cache.delete(k);
    if (cache.size > 400) cache.clear();
  }
  return value;
}

const buckets = new Map();

function rateLimited(ip) {
  if (CONFIG.rateLimit <= 0) return false;
  const now = Date.now();
  const b = buckets.get(ip) || { count: 0, resetAt: now + 60000 };
  if (now > b.resetAt) {
    b.count = 0;
    b.resetAt = now + 60000;
  }
  b.count += 1;
  buckets.set(ip, b);
  if (buckets.size > 5000) buckets.clear();
  return b.count > CONFIG.rateLimit;
}

/* ------------------------------------------------------------ 路由 */

let adapter;

async function handle(req, res) {
  const url = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));
  const pathname = url.pathname.replace(/\/{2,}/g, '/');
  const ip = (req.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
    req.socket.remoteAddress || '-';

  if (req.method === 'OPTIONS') return send(req, res, 204, {});
  const isAuthPost = req.method === 'POST' && pathname.indexOf('/auth/') === 0;
  if (!isAuthPost && req.method !== 'GET' && req.method !== 'HEAD') {
    return fail(req, res, 405, '仅支持 GET');
  }

  if (pathname === '/healthz') {
    let adapterOk = true;
    try {
      await adapter.categories();
    } catch (e) {
      adapterOk = false;
    }
    const body = {
      status: adapterOk ? 'ok' : 'degraded',
      adapter: CONFIG.upstream,
      version: VERSION,
      uptime: Math.floor((Date.now() - STARTED_AT) / 1000),
      auth: CONFIG.apiKey ? 'on' : 'off',
    };
    return send(req, res, adapterOk ? 200 : 503, body);
  }

  if (CONFIG.apiKey) {
    const given = req.headers['x-api-key'] || url.searchParams.get('key') || '';
    if (given !== CONFIG.apiKey) return fail(req, res, 401, 'API Key 校验失败');
  }

  if (rateLimited(ip)) return fail(req, res, 429, '请求过于频繁');

  /* ---------------------------- 认证 ---------------------------- */

  if (pathname === '/auth/sms') {
    if (req.method !== 'POST') return fail(req, res, 405, '请使用 POST');
    const body = await readJson(req);
    if (!isPhone(body.phone)) return fail(req, res, 400, '手机号格式不正确');
    const phone = String(body.phone).trim();
    log('info', 'auth sms', { phone: phone.slice(0, 3) + '****' + phone.slice(-2) });
    // No fake SMS is sent. Configure a real SMS provider before enabling login.
    if (!CONFIG.authCode) return fail(req, res, 503, '尚未配置真实短信验证码服务');
    return okBody(req, res, { sent: true, expire: 300, debug_code: undefined });
  }

  if (pathname === '/auth/login') {
    if (req.method !== 'POST') return fail(req, res, 405, '请使用 POST');
    const body = await readJson(req);
    const phone = String(body.phone || '').trim();
    const code = String(body.code || '').trim();
    if (!isPhone(phone)) return fail(req, res, 400, '手机号格式不正确');
    if (!CONFIG.authCode || code !== CONFIG.authCode) {
      return fail(req, res, 401, '验证码不正确');
    }
    const payload = {
      uid: 'u' + crypto.createHash('sha1').update(phone).digest('hex').slice(0, 10),
      phone,
      nickname: '果友' + phone.slice(-4),
      vip_level: 1,
      exp: Math.floor(Date.now() / 1000) + CONFIG.authTtlDays * 86400,
    };
    log('info', 'auth login', { uid: payload.uid });
    return okBody(req, res, { token: signToken(payload), user: publicUser(payload) });
  }

  if (pathname === '/auth/profile') {
    const user = currentUser(req);
    if (!user) return fail(req, res, 401, '登录已失效');
    return okBody(req, res, publicUser(user));
  }

  if (pathname === '/auth/logout') {
    // 凭证是无状态 HMAC，退出以后端无状态为准，由客户端丢弃 token。
    return okBody(req, res, { ok: true });
  }

  const key = pathname + '?' + url.searchParams.toString();

  if (pathname === '/categories' || pathname === '/categories/') {
    const data = await withCache('categories', () => adapter.categories());
    return okBody(req, res, data);
  }

  if (pathname === '/feed' || pathname === '/feed/') {
    const page = pageOf(url);
    const category = url.searchParams.get('category') || '';
    const data = await withCache(key, () => adapter.feed({ page, category }));
    return okBody(req, res, listPayload(data, page));
  }

  if (pathname === '/rank' || pathname === '/rank/') {
    const page = pageOf(url);
    const type = (url.searchParams.get('type') || 'hot').toLowerCase();
    const data = await withCache(key, () => adapter.ranking({ type, page }));
    return okBody(req, res, listPayload(data, page));
  }

  if (pathname === '/search' || pathname === '/search/') {
    const q = (url.searchParams.get('q') || '').trim();
    if (!q) return fail(req, res, 400, '缺少查询参数 q');
    const page = pageOf(url);
    const data = await withCache(key, () => adapter.search({ q, page }));
    return okBody(req, res, listPayload(data, page));
  }

  const mEpisodes = pathname.match(/^\/drama\/([^/]+)\/episodes\/?$/);
  if (mEpisodes) {
    const id = decodeURIComponent(mEpisodes[1]);
    const data = await withCache(key, () => adapter.episodes(id));
    if (!data) return fail(req, res, 404, '剧集不存在');
    // 未登录：前 FREE_EPISODES 集免费，其余标记为登录专享；登录后全部解锁。
    const user = currentUser(req);
    const list = user
      ? data.map((ep) => Object.assign({}, ep, { locked: false, is_vip: false }))
      : data.map((ep, i) =>
          Object.assign({}, ep, {
            locked: ep.locked === true || i >= CONFIG.freeEpisodes,
            is_vip: ep.is_vip === true || i >= CONFIG.freeEpisodes,
          }),
        );
    return okBody(req, res, { list, total: list.length, logged_in: !!user });
  }

  const mDetail = pathname.match(/^\/drama\/([^/]+)\/?$/);
  if (mDetail) {
    const id = decodeURIComponent(mDetail[1]);
    const data = await withCache(key, () => adapter.detail(id));
    if (!data) return fail(req, res, 404, '剧集不存在');
    return okBody(req, res, data);
  }

  return fail(req, res, 404, '无此接口：' + pathname);
}

/* ------------------------------------------------------------ 启动 */

function main() {
  try {
    adapter = loadAdapter();
  } catch (err) {
    log('error', err.message);
    process.exit(1);
  }

  const server = http.createServer((req, res) => {
    const began = Date.now();
    handle(req, res)
      .then(() => {
        log('info', 'request', {
          method: req.method,
          path: req.url,
          ms: Date.now() - began,
          status: res.statusCode,
        });
      })
      .catch((err) => {
        log('error', 'handler failed', { path: req.url, error: String(err && err.message || err) });
        if (!res.headersSent) fail(req, res, 502, '上游请求失败：' + (err && err.message || err));
        else res.end();
      });
  });

  server.headersTimeout = 20000;
  server.requestTimeout = CONFIG.timeout + 5000;
  server.keepAliveTimeout = 5000;

  server.on('error', (err) => {
    log('error', 'listen failed', { error: String(err && err.message || err) });
    process.exit(1);
  });

  server.listen(CONFIG.port, CONFIG.bind, () => {
    log('info', 'gateway started', {
      bind: CONFIG.bind,
      port: CONFIG.port,
      adapter: CONFIG.upstream,
      auth: CONFIG.apiKey ? 'on' : 'off',
      version: VERSION,
    });
  });

  const shutdown = (sig) => {
    log('info', 'shutting down', { signal: sig });
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 5000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main();
HONGUO_SERVER_JS


  cat > "$root/lib/adapters/http.js" <<'HONGUO_HTTP_JS'
'use strict';

/*
 * 上游转发适配器：把客户端请求原样转给你自己的上游服务（UPSTREAM_BASE）。
 *
 *   UPSTREAM=http
 *   UPSTREAM_BASE=https://your-upstream.example.com
 *   UPSTREAM_TOKEN=xxx        # 以 Authorization: Bearer 转发
 *
 * 上游需要返回同样的信封：{"code":0,"data":{...}} 或 {"data":{...}}。
 *
 * 关于签名：如果你手上有一个「需要签名的、你有权访问的」上游接口，
 * 在 signRequest() 里补请求头即可。本脚本不包含任何绕过第三方风控的
 * 签名算法——那类实现请自行评估合规性，且不属于本项目提供的功能。
 */

const http = require('http');
const https = require('https');

function create(config) {
  if (!config.upstreamBase) {
    throw new Error('UPSTREAM=http 时必须设置 UPSTREAM_BASE');
  }
  const base = new URL(config.upstreamBase);
  const lib = base.protocol === 'https:' ? https : http;

  // 在这里追加你自己的签名/鉴权头。默认只带 Token。
  function signRequest(_targetUrl) {
    const headers = { Accept: 'application/json' };
    if (config.upstreamToken) headers.Authorization = 'Bearer ' + config.upstreamToken;
    return headers;
  }

  function getOnce(targetUrl) {
    return new Promise((resolve, reject) => {
      const url = new URL(targetUrl);
      const req = lib.request(
        {
          protocol: url.protocol,
          hostname: url.hostname,
          port: url.port || (url.protocol === 'https:' ? 443 : 80),
          path: url.pathname + url.search,
          method: 'GET',
          headers: signRequest(url),
          timeout: config.timeout,
        },
        (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            resolve({ status: res.statusCode || 0, text });
          });
        },
      );
      req.on('timeout', () => req.destroy(new Error('上游超时')));
      req.on('error', reject);
      req.end();
    });
  }

  async function get(pathAndQuery) {
    const target = config.upstreamBase + pathAndQuery;
    let res;
    try {
      res = await getOnce(target);
    } catch (err) {
      res = await getOnce(target); // 失败重试一次
    }
    if (res.status !== 200) {
      throw new Error('上游返回 ' + res.status);
    }
    if (!res.text) throw new Error('上游响应为空');
    let body;
    try {
      body = JSON.parse(res.text);
    } catch (_) {
      throw new Error('上游返回的不是 JSON');
    }
    const data = body && typeof body === 'object' && 'data' in body ? body.data : body;
    return data;
  }

  function toList(data) {
    if (Array.isArray(data)) return data;
    if (data && Array.isArray(data.list)) return data.list;
    if (data && Array.isArray(data.items)) return data.items;
    return [];
  }

  const qs = (params) => {
    const sp = new URLSearchParams();
    Object.keys(params).forEach((k) => {
      const v = params[k];
      if (v !== undefined && v !== null && v !== '') sp.set(k, String(v));
    });
    const s = sp.toString();
    return s ? '?' + s : '';
  };

  return {
    name: 'http',

    async categories() {
      try {
        const data = await get('/categories');
        if (Array.isArray(data)) return data.map((x) => String(x));
      } catch (_) {
        /* 上游未实现时回落 */
      }
      return ['推荐', '都市', '甜宠', '逆袭', '古装', '悬疑', '萌宝'];
    },

    // 上游若返回 {list,total,has_more}，网关会原样透传，不再二次分页
    async feed({ page, category }) {
      return get('/feed' + qs({ page, category }));
    },

    async ranking({ type, page }) {
      return get('/rank' + qs({ type, page }));
    },

    async search({ q, page }) {
      return get('/search' + qs({ q, page }));
    },

    async detail(id) {
      const data = await get('/drama/' + encodeURIComponent(id));
      return data && typeof data === 'object' && !Array.isArray(data) ? data : null;
    },

    async episodes(id) {
      const data = await get('/drama/' + encodeURIComponent(id) + '/episodes');
      return toList(data);
    },
  };
}

module.exports = { create };
HONGUO_HTTP_JS

  echo "1.0.0" > "$root/VERSION"
}

write_config() {
  local key="$1" secret="$2"
  cat > "$CONF_FILE" <<HONGUO_CONFIG
# 红果短剧网关配置（修改后 systemctl restart ${APP_NAME}）
# 监听地址：有 nginx 时只监听本机，由 nginx 对外；没有 nginx 时改为 0.0.0.0
PORT=${PORT}
BIND=$([ "$USE_NGINX" -eq 1 ] && echo 127.0.0.1 || echo 0.0.0.0)

# 客户端需带 X-API-Key 头（或 ?key=）。留空则不做校验。
API_KEY=${key}

# 登录凭证的 HMAC 签名密钥，务必使用随机值（脚本已生成）
AUTH_SECRET=${secret}

# 真实短信服务未配置前留空；需实现真实短信发送与验证码校验
AUTH_CODE=
AUTH_TTL_DAYS=30

# 未登录时免费可看的集数，其余集标记为登录专享
FREE_EPISODES=10

# 上游必须配置为你有权使用的真实 API
UPSTREAM=http
UPSTREAM_BASE=
UPSTREAM_TOKEN=

# 列表每页条数 / 缓存秒数（0 关闭）/ 单 IP 每分钟上限（0 不限制）
PAGE_SIZE=24
CACHE_TTL=60
RATE_LIMIT=0

# CORS：Flutter Web 调试可用 *，上线建议写死域名
ALLOW_ORIGIN=*

# 上游请求超时（毫秒）
REQUEST_TIMEOUT=10000

# 分集付费标记策略由真实上游返回
MOCK_LOCKED_AFTER=0

LOG_LEVEL=info
HONGUO_CONFIG
  chmod 640 "$CONF_FILE"
  chown "root:$SVC_USER" "$CONF_FILE" 2>/dev/null || true
}

write_unit() {
  local systemd_ver hardening=""
  systemd_ver=$(systemctl --version 2>/dev/null | head -1 | awk '{print $2}')
  systemd_ver=${systemd_ver:-0}
  if [ "$systemd_ver" -ge 235 ]; then
    hardening=$(cat <<'HARD'
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
HARD
)
  fi
  cat > "$UNIT_FILE" <<HONGUO_UNIT
[Unit]
Description=Hongguo Drama Gateway
Documentation=file://${APP_DIR}/server.js
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SVC_USER}
Group=${SVC_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${CONF_FILE}
ExecStart=${REG_DIR}/node ${APP_DIR}/server.js
Restart=always
RestartSec=3
TimeoutStopSec=10
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
LimitNOFILE=65535
${hardening}
[Install]
WantedBy=multi-user.target
HONGUO_UNIT
  ok "systemd 单元已写入 $UNIT_FILE"
}

write_nginx() {
  cat > "$NGINX_CONF" <<'HONGUO_NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name __SERVER_NAME__;

    access_log /var/log/nginx/hongguo-gateway.access.log;
    client_max_body_size 1m;

    location / {
        proxy_pass http://127.0.0.1:__PORT__;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;

        add_header X-Content-Type-Options nosniff always;
    }
}
HONGUO_NGINX
  sed -i "s/__PORT__/${PORT}/g" "$NGINX_CONF"
  sed -i "s/__SERVER_NAME__/${DOMAIN:-_}/g" "$NGINX_CONF"
  ok "nginx 配置已写入 $NGINX_CONF"
}

setup_selinux() {
  command -v getenforce >/dev/null 2>&1 || return 0
  [ "$(getenforce)" = "Disabled" ] && return 0
  log "检测到 SELinux 开启，允许 nginx 反代本机端口"
  setsebool -P httpd_can_network_connect 1 2>/dev/null \
    || warn "setsebool 失败（可能未装 selinux-policy），若 502 请手动执行：setsebool -P httpd_can_network_connect 1"
  if command -v semanage >/dev/null 2>&1; then
    semanage port -a -t http_port_t -p tcp "$PORT" 2>/dev/null || true
  fi
}

setup_firewall() {
  [ "$USE_FIREWALL" -eq 1 ] || return 0
  command -v firewall-cmd >/dev/null 2>&1 || return 0
  firewall-cmd --state >/dev/null 2>&1 || return 0
  log "配置 firewalld"
  if [ "$USE_NGINX" -eq 1 ]; then
    firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
    if [ -n "$DOMAIN" ]; then
      firewall-cmd --permanent --add-service=https >/dev/null 2>&1 || true
    fi
  else
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
  fi
  firewall-cmd --reload >/dev/null 2>&1 || true
  ok "防火墙已放行"
}

install_nginx() {
  [ "$USE_NGINX" -eq 1 ] || return 0
  if ! command -v nginx >/dev/null 2>&1; then
    log "安装 nginx"
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y nginx >/dev/null 2>&1 || die "nginx 安装失败"
    else
      yum install -y nginx >/dev/null 2>&1 || die "nginx 安装失败"
    fi
  fi
  write_nginx
  nginx -t >/dev/null 2>&1 || die "nginx 配置校验失败，请检查 $NGINX_CONF"
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx
  setup_selinux
  ok "nginx 已生效"
}

issue_cert() {
  [ "$USE_NGINX" -eq 1 ] && [ -n "$DOMAIN" ] || return 0
  command -v certbot >/dev/null 2>&1 || {
    warn "未安装 certbot，跳过 HTTPS。需要时：dnf install -y certbot python3-certbot-nginx"
    return 0
  }
  log "申请 Let's Encrypt 证书（$DOMAIN）"
  if [ -n "$EMAIL" ]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1 \
      && ok "HTTPS 已启用" || warn "证书申请失败（域名是否已解析到本机？），继续用 HTTP"
  else
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect >/dev/null 2>&1 \
      && ok "HTTPS 已启用" || warn "证书申请失败（域名是否已解析到本机？），继续用 HTTP"
  fi
}

health_check() {
  local host="127.0.0.1" tries=20
  log "等待服务就绪"
  while [ "$tries" -gt 0 ]; do
    if curl -fsS --max-time 3 "http://$host:$PORT/healthz" >/dev/null 2>&1; then
      ok "服务已就绪"
      return 0
    fi
    tries=$((tries - 1))
    sleep 1
  done
  warn "健康检查未通过，查看日志：journalctl -u $APP_NAME -n 50 --no-pager"
  return 1
}

random_key() {
  head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32
}

# ---------------------------------------------------------------- 安装流程

do_install() {
  if [ -n "$PREFIX" ]; then
    DRY_RUN=1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -r /etc/os-release ]; then detect_os; else warn "无法识别系统（演练模式继续）"; fi
  else
    require_root
    detect_os
    need_cmd curl
    need_cmd tar
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    fix_eol_repos
    install_node
    if ! id -u "$SVC_USER" >/dev/null 2>&1; then
      useradd --system --home-dir "$APP_DIR" --shell /sbin/nologin "$SVC_USER"
      ok "已创建系统用户 $SVC_USER"
    fi
    install -d -m 755 "$APP_DIR" "$ETC_DIR"
  else
    APP_DIR="${PREFIX:-/tmp/hongguo-gateway-dryrun}"
    CONF_FILE="$APP_DIR/config.env"
    UNIT_FILE="$APP_DIR/${APP_NAME}.service"
    NGINX_CONF="$APP_DIR/${APP_NAME}.conf"
    install -d -m 755 "$APP_DIR"
    log "演练模式：仅生成文件到 $APP_DIR"
  fi

  materialize_app "$APP_DIR"
  chmod +x "$APP_DIR/server.js" 2>/dev/null || true
  ok "网关代码已生成（server.js + 2 个适配器，零依赖）"

  local key="" secret=""
  if [ "$DISABLE_AUTH" -eq 0 ]; then
    key=$(random_key)
  fi
  secret=$(random_key)

  if [ -f "$CONF_FILE" ] && [ "$FORCE_CONFIG" -eq 0 ]; then
    key=$(grep -E '^API_KEY=' "$CONF_FILE" | head -1 | cut -d= -f2- || true)
    secret=$(grep -E '^AUTH_SECRET=' "$CONF_FILE" | head -1 | cut -d= -f2- || true)
    if [ -z "$secret" ]; then
      secret=$(random_key)
      printf '\n# 登录凭证签名密钥（脚本补写）\nAUTH_SECRET=%s\n' "$secret" >> "$CONF_FILE"
      ok "已为旧配置补写 AUTH_SECRET"
    fi
    warn "配置已存在，保留原文件（改配置：$CONF_FILE；或加 --force-config 重建）"
  else
    write_config "$key" "$secret"
    ok "配置已写入 $CONF_FILE"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    write_nginx
    cat > "$UNIT_FILE" <<HONGUO_DRY_UNIT
[Unit]
Description=Hongguo Drama Gateway
After=network-online.target

[Service]
User=${SVC_USER}
EnvironmentFile=/etc/hongguo-gateway/config.env
ExecStart=/usr/local/bin/node ${APP_DIR}/server.js
Restart=always

[Install]
WantedBy=multi-user.target
HONGUO_DRY_UNIT
    printf '\n%s演练完成%s\n  代码：%s\n  配置：%s\n  启动：PORT=%s node %s/server.js\n\n' \
      "$C_OK" "$C_RESET" "$APP_DIR" "$CONF_FILE" "$PORT" "$APP_DIR"
    return 0
  fi

  write_unit
  chown -R "$SVC_USER:$SVC_USER" "$APP_DIR"

  systemctl daemon-reload
  systemctl enable "$APP_NAME" >/dev/null 2>&1 || true
  systemctl restart "$APP_NAME"
  ok "服务已启动：$APP_NAME"

  install_nginx
  setup_firewall
  issue_cert
  health_check || true

  print_summary "$key"
}

print_summary() {
  local key="$1"
  local url
  if [ "$USE_NGINX" -eq 1 ]; then
    url="http://${DOMAIN:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
    [ -n "$DOMAIN" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && url="https://$DOMAIN"
  else
    url="http://$(hostname -I 2>/dev/null | awk '{print $1}'):$PORT"
  fi

  printf '\n%s========================================%s\n' "$C_OK" "$C_RESET"
  printf ' 网关已部署\n'
  printf '%s========================================%s\n' "$C_OK" "$C_RESET"
  printf ' 地址      : %s\n' "$url"
  printf ' 健康检查  : %s/healthz\n' "$url"
  printf ' API Key   : %s\n' "${key:-（未启用）}"
  printf ' 服务名    : %s\n' "$APP_NAME"
  printf ' 配置      : %s\n' "$CONF_FILE"
  printf ' 日志      : journalctl -u %s -f\n' "$APP_NAME"
  printf '\n 客户端接入：\n'
  if [ -n "$key" ]; then
    printf '   flutter run --dart-define=HONGGUO_GATEWAY=%s \\\n' "$url"
    printf '               --dart-define=HONGGUO_TOKEN=%s\n\n' "$key"
  else
    printf '   flutter run --dart-define=HONGGUO_GATEWAY=%s\n\n' "$url"
  fi
  printf ' 登录验证码: 未配置（请接入真实短信服务）\n'
  printf ' 自测：curl -H "X-API-Key: %s" "%s/feed?page=1"\n' "${key:-}" "$url"
  printf ' 登录：curl -s -X POST -H "Content-Type: application/json" \\\n'
  printf '         请先接入真实短信验证码服务再启用登录。\\n'
  printf '         "%s/auth/login"\n\n' "$url"
  printf ' 说明：请配置 %s 中的 UPSTREAM_BASE 指向真实元数据 API。\n\n' "$CONF_FILE"
}

# ---------------------------------------------------------------- 卸载

do_uninstall() {
  require_root
  log "卸载 $APP_NAME"
  systemctl stop "$APP_NAME" >/dev/null 2>&1 || true
  systemctl disable "$APP_NAME" >/dev/null 2>&1 || true
  rm -f "$UNIT_FILE"
  systemctl daemon-reload || true
  rm -rf "$APP_DIR" "$ETC_DIR"
  if [ -f "$NGINX_CONF" ]; then
    rm -f "$NGINX_CONF"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
  if id -u "$SVC_USER" >/dev/null 2>&1; then
    userdel "$SVC_USER" >/dev/null 2>&1 || true
  fi
  ok "已卸载（Node 运行时与 nginx 保留，需要时手动移除）"
}

# ---------------------------------------------------------------- 入口

case "$ACTION" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  *)         die "未知动作：$ACTION" ;;
esac
