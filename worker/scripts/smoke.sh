#!/usr/bin/env bash
# ============================================================================
# FindMa · M1 端到端联调脚本（对应 DESIGN 12 章 M1 验收标准）
#   用法：先跑 `npm run dev`，另开终端执行 `bash scripts/smoke.sh`
#   可覆盖：BASE=http://127.0.0.1:8791/api/v1 bash scripts/smoke.sh
# ============================================================================
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8791/api/v1}"
NODE_BIN="${NODE_BIN:-node}"
USER_NAME="guardian_$RANDOM"

# 从 stdin 的 JSON 里取字段：json <a.b.c>
json() {
  "${NODE_BIN}" -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const o = JSON.parse(s);
      let v = o;
      for (const k of process.argv[1].split(".")) v = v[k];
      console.log(v);
    });
  ' "$1"
}

hr() { printf '\n\033[1;36m── %s ──────────────────────────────\033[0m\n' "$1"; }

hr "0. 健康检查"
curl -sS "${BASE%/api/v1}/health"; echo

hr "1. 老人端注册（POST /device/register）"
DEV_JSON=$(curl -sS -X POST "${BASE}/device/register" \
  -H 'Content-Type: application/json' \
  -d '{"name":"测试老人机"}')
echo "${DEV_JSON}"

TOKEN=$(printf '%s' "${DEV_JSON}" | json token)
BIND_CODE=$(printf '%s' "${DEV_JSON}" | json bindCode)
DEVICE_ID=$(printf '%s' "${DEV_JSON}" | json deviceId)
echo "deviceId=${DEVICE_ID}  bindCode=${BIND_CODE}"

hr "2. 子女端注册（POST /auth/register）"
AUTH_JSON=$(curl -sS -X POST "${BASE}/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${USER_NAME}\",\"password\":\"secret123\"}")
JWT=$(printf '%s' "${AUTH_JSON}" | json token)
echo "username=${USER_NAME}  jwt=${JWT:0:24}..."

hr "3. 扫码绑定（POST /devices/bind，带称呼）"
curl -sS -X POST "${BASE}/devices/bind" \
  -H "Authorization: Bearer ${JWT}" \
  -H 'Content-Type: application/json' \
  -d "{\"bindCode\":\"${BIND_CODE}\",\"nickname\":\"爷爷\"}"; echo

hr "4. 第一次上报（POST /report，蜂窝 + VPN 未生效 → 应生成 GUARD_OFF）"
curl -sS -X POST "${BASE}/report" \
  -H "X-Device-Token: ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"settingsVer":1,"netType":"cellular","vpnActive":false,"appVer":"1.0.0",
       "points":[{"lat":31.2304,"lng":121.4737,"acc":12.5,"speed":1.2,"bearing":90,
                  "batt":66,"charging":false,"provider":"gps","devTs":1757460000000}]}'; echo

hr "5. 设置关注模式（PUT /devices/:id/settings）"
curl -sS -X PUT "${BASE}/devices/${DEVICE_ID}/settings" \
  -H "Authorization: Bearer ${JWT}" \
  -H 'Content-Type: application/json' \
  -d '{"mode":"WATCH","normalIntervalSec":600,"lostIntervalSec":60}'; echo

hr "6. 设置圆形围栏（PUT /devices/:id/geofence，圆心=上报点，半径 200m）"
curl -sS -X PUT "${BASE}/devices/${DEVICE_ID}/geofence" \
  -H "Authorization: Bearer ${JWT}" \
  -H 'Content-Type: application/json' \
  -d '{"type":"circle","name":"家","centerLat":31.2304,"centerLng":121.4737,"radiusM":200,"enabled":true}'; echo

hr "7. 上报一个远点（约 1.5km 外 → 应生成 OUT_OF_FENCE）"
curl -sS -X POST "${BASE}/report" \
  -H "X-Device-Token: ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"settingsVer":2,"netType":"wifi","vpnActive":true,"appVer":"1.0.0",
       "points":[{"lat":31.2405,"lng":121.4900,"acc":15,"batt":19,"charging":false,
                  "provider":"gps","devTs":1757460060000}]}'; echo

hr "8. 低精度点（acc=300m → 应被精度门槛拦掉，inFence 保持）"
curl -sS -X POST "${BASE}/report" \
  -H "X-Device-Token: ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"settingsVer":2,"netType":"wifi","vpnActive":true,"appVer":"1.0.0",
       "points":[{"lat":31.2000,"lng":121.4000,"acc":300,"batt":18,"charging":false,
                  "provider":"network","devTs":1757460120000}]}'; echo

hr "9. 告警列表（GET /alerts）"
curl -sS "${BASE}/alerts" -H "Authorization: Bearer ${JWT}"; echo

hr "10. 设备列表（GET /devices，含最新位置/配置状态/未读数）"
curl -sS "${BASE}/devices" -H "Authorization: Bearer ${JWT}"; echo

hr "11. 设备摘要（GET /devices/:id/summary）"
curl -sS "${BASE}/devices/${DEVICE_ID}/summary" -H "Authorization: Bearer ${JWT}"; echo

hr "12. 历史轨迹（GET /devices/:id/locations）"
curl -sS "${BASE}/devices/${DEVICE_ID}/locations?from=0&limit=50" \
  -H "Authorization: Bearer ${JWT}"; echo

hr "13. 标记全部告警已读（PUT /alerts/read）"
curl -sS -X PUT "${BASE}/alerts/read" \
  -H "Authorization: Bearer ${JWT}" \
  -H 'Content-Type: application/json' \
  -d '{"all":true}'; echo

hr "14. 重置绑定码（POST /device/rebind-code，旧码作废）"
curl -sS -X POST "${BASE}/device/rebind-code" -H "X-Device-Token: ${TOKEN}"; echo

hr "15. 用旧绑定码绑定 → 应失败"
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' -X POST "${BASE}/devices/bind" \
  -H "Authorization: Bearer ${JWT}" \
  -H 'Content-Type: application/json' \
  -d "{\"bindCode\":\"${BIND_CODE}\",\"nickname\":\"爷爷\"}"

printf '\n\033[1;32m全部用例执行完毕。\033[0m\n'
