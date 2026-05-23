@REM 注册课题组 + 发布测试数据
@echo off
set URL=http://localhost:8080/api/v1
echo ===== 1. 注册课题组 =====

echo --- 张伟老师课题组（3人）---
curl -s -X POST %URL%/register -H "Content-Type: application/json" -d "{\"teacher_name\":\"张伟\",\"members\":[\"李华\",\"王芳\"]}"
echo.

echo --- 王强老师课题组（2人）---
curl -s -X POST %URL%/register -H "Content-Type: application/json" -d "{\"teacher_name\":\"王强\",\"members\":[\"赵明\"]}"
echo.

echo --- 陈敏老师课题组（1人）---
curl -s -X POST %URL%/register -H "Content-Type: application/json" -d "{\"teacher_name\":\"陈敏\"}"
echo.
