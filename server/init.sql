-- 服务器端验证数据库初始化脚本
-- 初始化表结构 (直接从 schema.sql 迁移)

CREATE TABLE IF NOT EXISTS licenses (
    serial TEXT NOT NULL,
    app_id TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'lifetime',
    email TEXT,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    PRIMARY KEY(serial, app_id)
);
    email TEXT,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS activations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    serial TEXT NOT NULL,
    app_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE,
    activated_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    last_heartbeat_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

-- 单独按索引优化查询
CREATE INDEX IF NOT EXISTS idx_activations_serial ON activations(serial);
CREATE INDEX IF NOT EXISTS idx_activations_token_device ON activations(token, device_id);

CREATE TABLE IF NOT EXISTS device_changes (
    serial TEXT NOT NULL,
    app_id TEXT NOT NULL,
    year INTEGER NOT NULL,
    count INTEGER DEFAULT 0,
    PRIMARY KEY (serial, app_id, year)
);

-- 发送找回邮件记录表（用于限制频率）
CREATE TABLE IF NOT EXISTS recovery_logs (
    email TEXT NOT NULL,
    sent_at INTEGER NOT NULL
);

-- 默认测试数据 (方便立刻测试)
INSERT OR IGNORE INTO licenses (serial, app_id, type) VALUES ('TEST-SERIAL-12345', 'InputLock', 'lifetime');
