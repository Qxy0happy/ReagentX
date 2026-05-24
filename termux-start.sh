#!/data/data/com.termux/files/usr/bin/bash
# Termux 一键启动脚本
# 用法：bash termux-start.sh

set -e

cd "$(dirname "$0")/backend"

# 1. 安装依赖（首次运行）
if ! command -v go &>/dev/null; then
    echo "[install] golang..."
    pkg install -y golang
fi

# 2. 编译/启动 Go 后端（HTTP :8081）
echo "[start] Go backend → :8081"
go run . &
GO_PID=$!

# 3. 安装/启动 Caddy（HTTPS :8080）
if ! command -v caddy &>/dev/null; then
    echo "[install] caddy..."
    go install github.com/caddyserver/caddy/v2/cmd/caddy@latest
fi

echo "[start] Caddy → https://localhost:8080"
~/go/bin/caddy reverse-proxy --from localhost:8080 --to localhost:8081 &
CADDY_PID=$!

echo ""
echo "================================="
echo "  Go  :8081 (PID $GO_PID)"
echo "  Caddy :8080 (PID $CADDY_PID)"
echo "================================="
echo "  本机 IP:"
ifconfig wlan0 2>/dev/null | awk '/inet /{print $2}' || echo "(未连接 WiFi)"
echo ""
echo "按 Ctrl+C 停止所有服务"

# 4. 捕获退出信号
trap "kill $GO_PID $CADDY_PID 2>/dev/null; exit" SIGINT SIGTERM
wait
