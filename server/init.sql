-- 服务器端验证数据库初始化脚本
-- 初始化表结构 (直接从 schema.sql 迁移)

CREATE TABLE IF NOT EXISTS licenses (
    serial TEXT PRIMARY KEY,
    type TEXT NOT NULL DEFAULT 'lifetime',
    email TEXT,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS activations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    serial TEXT NOT NULL,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE,
    activated_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    last_heartbeat_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY(serial) REFERENCES licenses(serial) ON DELETE CASCADE
);

-- 单独按索引优化查询
CREATE INDEX IF NOT EXISTS idx_activations_serial ON activations(serial);
CREATE INDEX IF NOT EXISTS idx_activations_token_device ON activations(token, device_id);

CREATE TABLE IF NOT EXISTS device_changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    serial TEXT NOT NULL,
    year INTEGER NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    UNIQUE(serial, year),
    FOREIGN KEY(serial) REFERENCES licenses(serial) ON DELETE CASCADE
);

-- 默认测试数据 (方便立刻测试)
INSERT OR IGNORE INTO licenses (serial, type) VALUES ('TEST-SERIAL-12345', 'lifetime');
