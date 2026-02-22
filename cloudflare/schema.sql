-- 序列号主表：记录每个序列号绑定的邮箱
CREATE TABLE IF NOT EXISTS licenses (
    serial      TEXT PRIMARY KEY,
    email       TEXT UNIQUE,
    created_at  INTEGER NOT NULL DEFAULT (unixepoch())
);

-- 设备激活记录表：记录每个序列号在哪些设备上激活
CREATE TABLE IF NOT EXISTS activations (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    serial       TEXT NOT NULL,
    device_id    TEXT NOT NULL,
    token        TEXT NOT NULL UNIQUE,
    activated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    expires_at   INTEGER NOT NULL,
    UNIQUE(serial, device_id)
);

-- 换机次数统计：每年每个序列号最多换 2 次
CREATE TABLE IF NOT EXISTS device_changes (
    serial  TEXT NOT NULL,
    year    INTEGER NOT NULL,
    count   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (serial, year)
);

-- 索引：按设备ID快速查询
CREATE INDEX IF NOT EXISTS idx_activations_device ON activations(device_id);
CREATE INDEX IF NOT EXISTS idx_activations_token ON activations(token);
