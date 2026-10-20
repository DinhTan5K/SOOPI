@echo off
chcp 65001 >nul
echo =======================================================
echo          SOOPI FOOD - START DEV ENVIRONMENT
echo =======================================================

:: 1. Tìm IP Wi-Fi của máy tính
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4 Address" /c:"IPv4" ^| findstr /v "169.254"') do (
    set LOCAL_IP=%%a
    goto :found_ip
)
:found_ip
set LOCAL_IP=%LOCAL_IP: =%
echo [1] IP may tinh hien tai (Wi-Fi): %LOCAL_IP%
echo     - URL USB cắm cáp: http://127.0.0.1:5000/api
echo     - URL Wi-Fi nội bộ: http://%LOCAL_IP%:5000/api
echo     - URL Cloud Tunnel: https://soopifood-dev.loca.lt/api

:: 2. Khởi chạy ADB Reverse Watcher chạy ngầm liên tục giữ kết nối USB
start /b powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch_adb.ps1" >nul 2>nul
echo [2] Da bat ADB Reverse Watcher tu dong giu ket noi USB!

:: 3. Khởi chạy Cloud Tunnel ngầm (hoạt động trên 4G va moi Wi-Fi)
where npx >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    start /b "" npx localtunnel --port 5000 --subdomain soopifood-dev >nul 2>nul
    echo [3] Da bat Cloud Tunnel: https://soopifood-dev.loca.lt
)

echo =======================================================
echo Dang khoi dong Backend .NET...
cd /d "%~dp0backend"
dotnet run
pause
