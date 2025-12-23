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
echo [1/3] 下载中...

powershell -Command "$ProgressPreference='SilentlyContinue'; (New-Object System.Net.WebClient).DownloadFile('%ZIP_URL%', '%ZIP_FILE%')" >nul 2>&1

if not exist "%ZIP_FILE%" (
    echo [失败] 下载失败
    exit /b 1
)

echo [成功] 下载完成
echo.

:: 解压
echo [2/3] 解压中...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%TARGET_DIR%' -Force" >nul 2>&1

if not exist "%TARGET_DIR%\NetWatch" (
    echo [失败] 解压失败
    del "%ZIP_FILE%" >nul 2>&1
    exit /b 1
)

echo [成功] 解压完成
del "%ZIP_FILE%" >nul 2>&1
echo.

:: 运行所有run.bat
echo [3/3] 启动监控...

set "RUN_COUNT=0"
for /r "%TARGET_DIR%" %%F in (run.bat) do (
    if exist "%%F" (
        echo 启动: %%F
        pushd "%%~dpF"
        start "" "run.bat"
        popd
        set /a "RUN_COUNT+=1"
    )
)

if %RUN_COUNT% gtr 0 (
    echo [成功] 已启动 %RUN_COUNT% 个监控程序
) else (
    echo [警告] 未找到 run.bat 文件
)

echo.
echo ========================================
echo 完成！
echo ========================================
echo.

exit /b 0

