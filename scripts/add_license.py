#!/usr/bin/env python3
"""
输入法锁定 - 录入序列号工具
每卖出一份，运行此脚本将生成的序列号写入 Cloudflare D1 数据库。
用户首次在 App 内激活时，服务器会将其输入的邮箱与此序列号永久绑定。

用法:
    python3 add_license.py <序列号>

示例:
    python3 add_license.py ABCD-1234-EF56-7890

依赖:
    - wrangler CLI（npm install -g wrangler）
    - 已登录 Cloudflare 账号（wrangler login）
"""

import sys
import subprocess
import re

# ── 配置 ────────────────────────────────────────────────────
DATABASE_NAME = "inputlock-db"       # 与 wrangler.toml 中 database_name 一致
REMOTE_FLAG   = "--remote"           # 操作线上数据库；本地测试改为 "--local"
# ─────────────────────────────────────────────────────────────

SERIAL_PATTERN  = re.compile(r'^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$')


def run_d1_command(sql: str) -> str:
    result = subprocess.run(
        ["wrangler", "d1", "execute", DATABASE_NAME, REMOTE_FLAG, "--command", sql],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def add_license(serial: str) -> None:
    serial = serial.strip().upper()

    if not SERIAL_PATTERN.match(serial):
        print(f"❌ 序列号格式不正确（应为 XXXX-XXXX-XXXX-XXXX）: {serial}")
        sys.exit(1)

    sql = (
        f"INSERT INTO licenses (serial, created_at) "
        f"VALUES ('{serial}', unixepoch()) "
        f"ON CONFLICT(serial) DO NOTHING;"
    )

    print(f"📝 写入数据库(空邮箱，待首次激活绑定)...")
    print(f"   序列号: {serial}")

    run_d1_command(sql)
    print(f"✅ 录入成功！")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)

    add_license(sys.argv[1])
