const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('database.sqlite');
db.run("INSERT OR IGNORE INTO licenses (serial, type) VALUES ('TEST-SERIAL-12345', 'lifetime');", (err) => {
    if (err) console.error(err);
    else console.log('✅ 测试序列号 TEST-SERIAL-12345 已经成功加入数据库！');
});
