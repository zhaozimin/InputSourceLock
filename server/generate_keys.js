const sqlite3 = require('sqlite3').verbose();
const fs = require('fs');
const path = require('path');

const dbPath = path.join(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath);
const count = 10000;
const outputFile = path.join(__dirname, 'licenses_10000.txt');

function generateRandomKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let key = '';
    for (let i = 0; i < 20; i++) {
        if (i > 0 && i % 4 === 0) key += '-';
        key += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return key;
}

const keys = new Set();
while (keys.size < count) {
    keys.add(generateRandomKey());
}
const keyArray = Array.from(keys);

console.log(`正在写入 ${count} 个序列号到数据库 ${dbPath} ...`);

db.serialize(() => {
    db.run("BEGIN TRANSACTION");
    const stmt = db.prepare("INSERT OR IGNORE INTO licenses (serial, type) VALUES (?, 'lifetime')");

    for (const key of keyArray) {
        stmt.run(key);
    }

    stmt.finalize();
    db.run("COMMIT", (err) => {
        if (err) console.error("✅ 批量插入失败:", err);
        else {
            fs.writeFileSync(outputFile, keyArray.join('\n'));
            console.log(`✅ 成功将 ${count} 个不重复的序列号注入到了数据库！`);
            console.log(`✅ 所有这些可用的序列号同时也已被导出至：${outputFile}`);
        }
        db.close();
    });
});
