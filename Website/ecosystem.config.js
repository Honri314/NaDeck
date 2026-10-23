// pm2 설정: NaDeck(TrueNAS 관리 프로그램) 다운로드 서버
// 사용:
//   pm2 start Website/ecosystem.config.js
//   pm2 save
// 상태 확인: pm2 status, 로그: pm2 logs truenas-downloads
module.exports = {
  apps: [
    {
      name: "truenas-downloads",
      script: "server.py",
      cwd: __dirname,
      // TrueNAS SCALE에는 python3가 기본 포함되어 있습니다.
      // 경로가 다르면 실제 경로로 조정하세요. (예: /usr/bin/python3)
      interpreter: "python3",
      args: "8181",
      env: { PYTHONDONTWRITEBYTECODE: "1" },
      autorestart: true,
      max_restarts: 10,
    },
  ],
};
