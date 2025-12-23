@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ========================================
:: Heartbeat 更新执行脚本
:: 此文件应上传到Git仓库
:: ========================================

set "ZIP_URL=https://github.com/yao0525888/heartbeat/releases/download/heartbeat/NetWatch.zip"
set "TARGET_DIR=C:\NetWatch"

echo ========================================
echo   Heartbeat 自动更新
echo ========================================
echo.
echo 时间: %date% %time%
echo 目标: %TARGET_DIR%
echo.

:: 创建目录
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%" >nul 2>&1

:: 下载ZIP
set "ZIP_FILE=%TEMP%\NetWatch_%RANDOM%.zip"
echo [1/4] 下载中...

powershell -Command "$ProgressPreference='SilentlyContinue'; (New-Object System.Net.WebClient).DownloadFile('%ZIP_URL%', '%ZIP_FILE%')" >nul 2>&1

if not exist "%ZIP_FILE%" (
    echo [失败] 下载失败
    exit /b 1
)

echo [成功] 下载完成
echo.

:: 备份
if exist "%TARGET_DIR%\NetWatch" (
    echo [2/4] 备份旧版本...
    set "BK_TIME=%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
    set "BK_TIME=!BK_TIME: =0!"
    if not exist "%TARGET_DIR%\backup" mkdir "%TARGET_DIR%\backup" >nul 2>&1
    xcopy "%TARGET_DIR%\NetWatch" "%TARGET_DIR%\backup\!BK_TIME!\" /E /I /Y >nul 2>&1
    echo [成功] 备份完成
    echo.
) else (
    echo [2/4] 首次安装，跳过备份
    echo.
)

:: 解压
echo [3/4] 解压中...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%TARGET_DIR%' -Force" >nul 2>&1

if not exist "%TARGET_DIR%\NetWatch" (
    echo [失败] 解压失败
    del "%ZIP_FILE%" >nul 2>&1
    exit /b 1
)

echo [成功] 解压完成
del "%ZIP_FILE%" >nul 2>&1
echo.

:: 运行
echo [4/4] 启动监控...
set "RUN_BAT=%TARGET_DIR%\NetWatch\heartbeat\run.bat"

if exist "%RUN_BAT%" (
    pushd "%TARGET_DIR%\NetWatch\heartbeat"
    start "" "run.bat"
    popd
    echo [成功] 监控程序已启动
) else (
    echo [警告] 未找到 run.bat
)

echo.
echo ========================================
echo 完成！
echo ========================================
echo.

:: 清理7天前的备份
if exist "%TARGET_DIR%\backup" (
    powershell -Command "Get-ChildItem '%TARGET_DIR%\backup' -Directory | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Recurse -Force" >nul 2>&1
)

exit /b 0

