/**
 * 输入法锁定 - 授权 API
 * 接口：POST /activate | POST /verify | POST /recover
 */

export interface Env {
    DB: D1Database;
    RESEND_API_KEY: string;
    FROM_EMAIL: string;
    MAX_DEVICE_CHANGES_PER_YEAR: string;
}

// Token 有效期：30 天（秒）
const TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        if (request.method !== "POST") {
            return jsonResponse({ error: "Method Not Allowed" }, 405);
        }

        const url = new URL(request.url);
        switch (url.pathname) {
            case "/activate": return handleActivate(request, env);
            case "/verify": return handleVerify(request, env);
            case "/recover": return handleRecover(request, env);
            default: return jsonResponse({ error: "Not Found" }, 404);
        }
    },
};

// ────────────────────────────────────────────────────────────
// POST /activate
// Body: { email, serial, device_id }
// 成功返回: { token, expires_at }
// ────────────────────────────────────────────────────────────
async function handleActivate(request: Request, env: Env): Promise<Response> {
    const body = await parseBody(request);
    const { email, serial, device_id } = body ?? {};

    if (!email || !serial || !device_id) {
        return jsonResponse({ error: "缺少必要参数" }, 400);
    }

    // 1. 查询序列号是否存在
    const license = await env.DB.prepare(
        "SELECT email FROM licenses WHERE serial = ?"
    ).bind(serial).first<{ email: string | null }>();

    if (!license) {
        return jsonResponse({ error: "序列号不存在" }, 404);
    }

    // 检查邮箱绑定状态
    if (!license.email) {
        // 首次激活：绑定邮箱到此序列号
        await env.DB.prepare(
            "UPDATE licenses SET email = ? WHERE serial = ?"
        ).bind(email, serial).run();
    } else if (license.email.toLowerCase() !== email.toLowerCase()) {
        // 已被绑定且邮箱不匹配
        return jsonResponse({ error: "该序列号已绑定至其他邮箱" }, 403);
    }

    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + TOKEN_TTL_SECONDS;

    // 2. 检查此设备是否已激活（重装后同设备重新激活不算换机）
    const existing = await env.DB.prepare(
        "SELECT token, expires_at FROM activations WHERE serial = ? AND device_id = ?"
    ).bind(serial, device_id).first<{ token: string; expires_at: number }>();

    if (existing) {
        // 设备已激活，续签 token
        const newToken = generateToken();
        await env.DB.prepare(
            "UPDATE activations SET token = ?, expires_at = ? WHERE serial = ? AND device_id = ?"
        ).bind(newToken, expiresAt, serial, device_id).run();
        return jsonResponse({ token: newToken, expires_at: expiresAt });
    }

    // 3. 新设备：检查本年换机次数
    const currentYear = new Date().getFullYear();
    const maxChanges = parseInt(env.MAX_DEVICE_CHANGES_PER_YEAR ?? "2");

    const changeRow = await env.DB.prepare(
        "SELECT count FROM device_changes WHERE serial = ? AND year = ?"
    ).bind(serial, currentYear).first<{ count: number }>();

    const changeCount = changeRow?.count ?? 0;
    if (changeCount >= maxChanges) {
        return jsonResponse(
            { error: `本年度换机次数已达上限（${maxChanges} 次），如需帮助请联系支持` },
            403
        );
    }

    // 4. 写入新激活记录
    const token = generateToken();
    await env.DB.prepare(
        "INSERT INTO activations (serial, device_id, token, activated_at, expires_at) VALUES (?, ?, ?, ?, ?)"
    ).bind(serial, device_id, token, now, expiresAt).run();

    // 5. 换机计数 +1（upsert）
    await env.DB.prepare(`
    INSERT INTO device_changes (serial, year, count) VALUES (?, ?, 1)
    ON CONFLICT(serial, year) DO UPDATE SET count = count + 1
  `).bind(serial, currentYear).run();

    return jsonResponse({ token, expires_at: expiresAt });
}

// ────────────────────────────────────────────────────────────
// POST /verify
// Body: { token, device_id }
// 成功返回: { valid: true, expires_at }
// ────────────────────────────────────────────────────────────
async function handleVerify(request: Request, env: Env): Promise<Response> {
    const body = await parseBody(request);
    const { token, device_id } = body ?? {};

    if (!token || !device_id) {
        return jsonResponse({ valid: false, error: "缺少必要参数" }, 400);
    }

    const row = await env.DB.prepare(
        "SELECT expires_at FROM activations WHERE token = ? AND device_id = ?"
    ).bind(token, device_id).first<{ expires_at: number }>();

    if (!row) {
        return jsonResponse({ valid: false }, 200);
    }

    const now = Math.floor(Date.now() / 1000);
    if (row.expires_at < now) {
        return jsonResponse({ valid: false, reason: "token_expired" }, 200);
    }

    return jsonResponse({ valid: true, expires_at: row.expires_at });
}

// ────────────────────────────────────────────────────────────
// POST /recover
// Body: { email }
// 若邮箱存在，将序列号发送至该邮箱
// ────────────────────────────────────────────────────────────
async function handleRecover(request: Request, env: Env): Promise<Response> {
    const body = await parseBody(request);
    const { email } = body ?? {};

    if (!email) {
        return jsonResponse({ error: "请提供邮箱" }, 400);
    }

    // 查询邮箱对应的序列号
    const row = await env.DB.prepare(
        "SELECT serial FROM licenses WHERE LOWER(email) = LOWER(?)"
    ).bind(email).first<{ serial: string }>();

    // 无论是否找到，都返回相同提示（防止邮箱探查攻击）
    if (!row) {
        return jsonResponse({ status: "sent" });
    }

    // 发送找回邮件
    await sendRecoveryEmail(env, email, row.serial);
    return jsonResponse({ status: "sent" });
}

// ────────────────────────────────────────────────────────────
// 工具函数
// ────────────────────────────────────────────────────────────

/** 生成 32 字节随机 token（64 位十六进制） */
function generateToken(): string {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    return Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join("");
}

/** 发送找回序列号邮件 */
async function sendRecoveryEmail(env: Env, to: string, serial: string): Promise<void> {
    const html = `
    <div style="font-family:system-ui,sans-serif;max-width:480px;margin:0 auto;padding:32px">
      <h2 style="color:#1d1d1f">🔑 您的序列号</h2>
      <p>您申请找回「输入法锁定」的序列号，以下是您的专属序列号：</p>
      <div style="background:#f5f5f7;border-radius:8px;padding:16px 24px;margin:16px 0">
        <code style="font-size:20px;letter-spacing:2px;color:#0066cc">${serial}</code>
      </div>
      <p style="color:#6e6e73;font-size:13px">
        请妥善保存此序列号。激活时需同时输入您的注册邮箱和序列号。<br>
        若非本人操作，请忽略此邮件。
      </p>
    </div>
  `;

    await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${env.RESEND_API_KEY}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            from: env.FROM_EMAIL,
            to,
            subject: "您的「输入法锁定」序列号",
            html,
        }),
    });
}

/** 解析请求 JSON body */
async function parseBody(request: Request): Promise<Record<string, string> | null> {
    try {
        return await request.json() as Record<string, string>;
    } catch {
        return null;
    }
}

/** 构造 JSON 响应 */
function jsonResponse(data: object, status = 200): Response {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
    });
}
