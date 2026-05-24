# ReagentX 本地启动脚本
# 用法：.\start-backend.ps1

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot

# 1. 启动 Go 后端（HTTP :8081）
Write-Host "[start] Go backend → :8081" -ForegroundColor Cyan
$goJob = Start-Process -NoNewWindow -PassThru -FilePath "go" -ArgumentList "run ."

# 2. 启动 Caddy 反向代理（HTTPS :8080）
Write-Host "[start] Caddy → https://localhost:8080" -ForegroundColor Cyan
$caddyJob = Start-Process -NoNewWindow -PassThru -FilePath "caddy" -ArgumentList "reverse-proxy --from localhost:8080 --to localhost:8081"

Pop-Location

Write-Host ""
Write-Host "=================================" -ForegroundColor Green
Write-Host "  Go    :8081 (PID $($goJob.Id))" -ForegroundColor Green
Write-Host "  Caddy :8080 (PID $($caddyJob.Id))" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green
Write-Host "按 Ctrl+C 停止所有服务" -ForegroundColor Yellow
Write-Host ""

# 3. 等待任意一个退出
try {
    while (-not ($goJob.HasExited -and $caddyJob.HasExited)) {
        Start-Sleep -Seconds 1
        if ($goJob.HasExited) {
            Write-Host "[stop] Go 后端已退出" -ForegroundColor Red
            $caddyJob.Kill()
            break
        }
        if ($caddyJob.HasExited) {
            Write-Host "[stop] Caddy 已退出" -ForegroundColor Red
            $goJob.Kill()
            break
        }
    }
}
finally {
    if (-not $goJob.HasExited) { $goJob.Kill() }
    if (-not $caddyJob.HasExited) { $caddyJob.Kill() }
    Write-Host "[done] 所有服务已停止" -ForegroundColor Cyan
}
