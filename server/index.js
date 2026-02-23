/**
 * 输入法锁定 - 独立授权 API (Node.js + SQLite 版本)
 * 接口：POST /activate | POST /verify | POST /recover
 */

require('dotenv').config();
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const cors = require('cors');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());
app.use(cors());

// Token 有效期：30 天（秒）
const TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

// 配置说明 (可以放在 .env 文件里)
const PORT = process.env.PORT || 3000;

// --- SMTP 邮件配置 ---
const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.resend.com',
    port: parseInt(process.env.SMTP_PORT || '465'),
    secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
    auth: {
        user: process.env.SMTP_USER || 'resend',
        pass: process.env.SMTP_PASS || '',
    },
});

const FROM_EMAIL = process.env.FROM_EMAIL || 'noreply@yourdomain.com';
const MAX_DEVICE_CHANGES_PER_YEAR = parseInt(process.env.MAX_DEVICE_CHANGES_PER_YEAR || '2');

// --- 数据库初始化 ---
const dbPath = path.join(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath);

// 初始化数据库表
const initSql = fs.readFileSync(path.join(__dirname, 'init.sql'), 'utf8');
db.exec(initSql, (err) => {
    if (err) {
        console.error("数据库初始化错误:", err);
    } else {
        console.log("sqlite数据库已准备就绪.");
    }
});

// Promise 封装 SQLite 方法
const dbGet = (sql, params = []) => new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
});
const dbRun = (sql, params = []) => new Promise((resolve, reject) => {
    db.run(sql, params, function (err) {
        err ? reject(err) : resolve(this);
    });
});

// ────────────────────────────────────────────────────────────
// POST /activate
// ────────────────────────────────────────────────────────────
app.post('/activate', async (req, res) => {
    try {
        const { email, serial, device_id } = req.body || {};
        if (!email || !serial || !device_id) {
            return res.status(400).json({ error: "缺少必要参数" });
        }

        const license = await dbGet("SELECT email FROM licenses WHERE serial = ?", [serial]);
        if (!license) {
            return res.status(404).json({ error: "序列号不存在" });
        }

        if (!license.email) {
            await dbRun("UPDATE licenses SET email = ? WHERE serial = ?", [email, serial]);
        } else if (license.email.toLowerCase() !== email.toLowerCase()) {
            return res.status(403).json({ error: "该序列号已绑定至其他邮箱" });
        }

        const now = Math.floor(Date.now() / 1000);
        const expiresAt = now + TOKEN_TTL_SECONDS;

        const existing = await dbGet(
            "SELECT token, expires_at FROM activations WHERE serial = ? AND device_id = ?",
            [serial, device_id]
        );

        if (existing) {
            const newToken = generateToken();
            await dbRun(
                "UPDATE activations SET token = ?, expires_at = ?, last_heartbeat_at = ? WHERE serial = ? AND device_id = ?",
                [newToken, expiresAt, now, serial, device_id]
            );
            return res.json({ token: newToken, expires_at: expiresAt });
        }

        const currentYear = new Date().getFullYear();
        const changeRow = await dbGet(
            "SELECT count FROM device_changes WHERE serial = ? AND year = ?",
            [serial, currentYear]
        );

        const changeCount = changeRow ? changeRow.count : 0;
        if (changeCount >= MAX_DEVICE_CHANGES_PER_YEAR) {
            return res.status(403).json({ error: `本年度换机次数已达上限（${MAX_DEVICE_CHANGES_PER_YEAR} 次），如需帮助请联系支持` });
        }

        const token = generateToken();
        await dbRun(
            "INSERT INTO activations (serial, device_id, token, activated_at, expires_at, last_heartbeat_at) VALUES (?, ?, ?, ?, ?, ?)",
            [serial, device_id, token, now, expiresAt, now]
        );

        // UPSERT for SQLite
        await dbRun(`
            INSERT INTO device_changes (serial, year, count) VALUES (?, ?, 1)
            ON CONFLICT(serial, year) DO UPDATE SET count = count + 1
        `, [serial, currentYear]);

        res.json({ token, expires_at: expiresAt });
    } catch (error) {
        console.error("Activate Error:", error);
        res.status(500).json({ error: "Internal Server Error" });
    }
});

// ────────────────────────────────────────────────────────────
// POST /verify
// ────────────────────────────────────────────────────────────
app.post('/verify', async (req, res) => {
    try {
        const { token, device_id } = req.body || {};
        if (!token || !device_id) {
            return res.json({ valid: false, error: "缺少必要参数" });
        }

        const row = await dbGet(
            "SELECT serial, expires_at FROM activations WHERE token = ? AND device_id = ?",
            [token, device_id]
        );

        if (!row) {
            return res.json({ valid: false });
        }

        const now = Math.floor(Date.now() / 1000);
        if (row.expires_at < now) {
            return res.json({ valid: false, reason: "token_expired" });
        }

        await dbRun(
            "UPDATE activations SET last_heartbeat_at = ? WHERE token = ? AND device_id = ?",
            [now, token, device_id]
        );

        const thirtyDaysAgo = now - 30 * 24 * 60 * 60;
        const activeResult = await dbGet(
            "SELECT COUNT(DISTINCT device_id) as active_count FROM activations WHERE serial = ? AND last_heartbeat_at >= ?",
            [row.serial, thirtyDaysAgo]
        );

        const activeCount = activeResult ? activeResult.active_count : 1;
        if (activeCount > 2) {
            return res.json({ valid: false, reason: "too_many_devices_active" });
        }

        res.json({ valid: true, expires_at: row.expires_at });
    } catch (error) {
        console.error("Verify Error:", error);
        res.status(500).json({ valid: false, error: "Internal Server Error" });
    }
});

// ────────────────────────────────────────────────────────────
// POST /recover
// ────────────────────────────────────────────────────────────
app.post('/recover', async (req, res) => {
    try {
        const { email } = req.body || {};
        if (!email) {
            return res.status(400).json({ error: "请提供邮箱" });
        }

        const row = await dbGet(
            "SELECT serial FROM licenses WHERE LOWER(email) = LOWER(?)",
            [email]
        );

        // 无论是否找到都提示已发送
        if (!row) {
            return res.json({ status: "sent" });
        }

        const mailOptions = {
            from: FROM_EMAIL,
            to: email,
            subject: "您的「输入法锁定」序列号",
            html: `
            <div style="font-family:system-ui,sans-serif;max-width:480px;margin:0 auto;padding:32px">
              <h2 style="color:#1d1d1f">🔑 您的序列号</h2>
              <p>您申请找回「输入法锁定」的序列号，以下是您的专属序列号：</p>
              <div style="background:#f5f5f7;border-radius:8px;padding:16px 24px;margin:16px 0">
                <code style="font-size:20px;letter-spacing:2px;color:#0066cc">${row.serial}</code>
              </div>
              <p style="color:#6e6e73;font-size:13px">请妥善保存此序列号。<br>若非本人操作，请忽略此邮件。</p>
            </div>`
        };

        await transporter.sendMail(mailOptions);
        res.json({ status: "sent" });
    } catch (error) {
        console.error("Recover Error:", error);
        res.status(500).json({ error: "Internal Server Error" });
    }
});

function generateToken() {
    return crypto.randomBytes(32).toString('hex');
}

// 启动服务
app.listen(PORT, () => {
    console.log(`✅ 授权服务器已成功启动，运行在 http://localhost:${PORT}`);
});
