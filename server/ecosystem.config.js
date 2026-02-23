module.exports = {
    apps: [
        {
            name: 'inputlock-server',
            script: './index.js',
            env: {
                NODE_ENV: 'production',
                PORT: 3000,
                SMTP_HOST: 'smtpdm.aliyun.com',
                SMTP_PORT: '465',
                SMTP_SECURE: 'true',
                SMTP_USER: 'laozhao@mail.cklaozhao.me',
                SMTP_PASS: '请替换为你的真实密码',
                FROM_EMAIL: '输入法锁定 <laozhao@mail.cklaozhao.me>',
                MAX_DEVICE_CHANGES_PER_YEAR: '2',
            },
        },
    ],
};
