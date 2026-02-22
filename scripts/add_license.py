#!/usr/bin/env python3
"""
输入法锁定 - 录入序列号工具
每卖出一份，运行此脚本将「邮箱 + 序列号」写入 Cloudflare D1 数据库。

用法:
    python3 add_license.py <邮箱> <序列号>

示例:
    python3 add_license.py user@example.com ABCD-1234-EF56-7890

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

EMAIL_PATTERN   = re.compile(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')
SERIAL_PATTERN  = re.compile(r'^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$')


def run_d1_command(sql: str) -> str:
    result = subprocess.run(
        ["wrangler", "d1", "execute", DATABASE_NAME, REMOTE_FLAG, "--command", sql],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def add_license(email: str, serial: str) -> None:
    email  = email.strip().lower()
    serial = serial.strip().upper()

    if not EMAIL_PATTERN.match(email):
        print(f"❌ 邮箱格式不正确: {email}")
        sys.exit(1)

    if not SERIAL_PATTERN.match(serial):
        print(f"❌ 序列号格式不正确（应为 XXXX-XXXX-XXXX-XXXX）: {serial}")
        sys.exit(1)

    sql = (
        f"INSERT INTO licenses (serial, email, created_at) "
        f"VALUES ('{serial}', '{email}', unixepoch()) "
        f"ON CONFLICT(serial) DO UPDATE SET email = excluded.email;"
    )

    print(f"📝 写入数据库...")
    print(f"   邮箱  : {email}")
    print(f"   序列号: {serial}")

    run_d1_command(sql)
    print(f"✅ 录入成功！")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    add_license(sys.argv[1], sys.argv[2])
