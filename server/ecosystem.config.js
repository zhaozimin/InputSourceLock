module.exports = {
    apps: [
        {
            name: 'inputlock-server',
            script: './index.js',
            env: {
                NODE_ENV: 'production',
                PORT: 3000,
            },
        },
    ],
};
