@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: VERSION: 2025.01.01.001

set "ZIP_URL=https://github.com/yao0525888/heartbeat/releases/download/heartbeat/NetWatch.zip"
set "TARGET_DIR=C:\"
set "DELETE_LIST=C:\NetWatch\CoreService.bat"
for /f "tokens=2 delims=: " %%V in ('findstr /C:":: VERSION:" "%~f0"') do set "CURRENT_VERSION=%%V"

echo ========================================
echo   Heartbeat 自动更新
echo   版本: %CURRENT_VERSION%
echo ========================================
echo.
echo 时间: %date% %time%
echo 目标: C:\NetWatch\
echo.
if defined DELETE_LIST call :DELETE_FILES "%DELETE_LIST%"

echo [1/3] 下载中...
set "ZIP_FILE=%TEMP%\NetWatch_%RANDOM%.zip"

powershell -Command "$ProgressPreference='SilentlyContinue'; (New-Object System.Net.WebClient).DownloadFile('%ZIP_URL%', '%ZIP_FILE%')" >nul 2>&1

if not exist "%ZIP_FILE%" (
    echo [失败] 下载失败
    exit /b 1
)

echo [成功] 下载完成
echo.
echo [2/3] 解压中...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%TARGET_DIR%' -Force" >nul 2>&1

if not exist "C:\NetWatch" (
    echo [失败] 解压失败
    del "%ZIP_FILE%" >nul 2>&1
    exit /b 1
)

echo [成功] 解压完成
del "%ZIP_FILE%" >nul 2>&1
echo.
echo [3/3] 启动监控...

set "RUN_COUNT=0"
for /r "C:\NetWatch" %%F in (run.bat) do if exist "%%F" (
    echo 启动: %%F
    cd /d "%%~dpF" && start /min "" cmd /c "%%F"
    set /a "RUN_COUNT+=1"
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

:DELETE_FILES
setlocal EnableDelayedExpansion
set "paths=%~1"

if "%paths%"=="" (
    endlocal
    goto :EOF
)

echo.
echo [清理] 删除指定文件...
for %%P in ("%paths:;=" "%") do (
    set "path=%%~P"
    if exist "!path!" (
        if exist "!path!\*" (
            echo   删除目录: !path!
            rd /s /q "!path!" 2>nul
            if !errorLevel! equ 0 (
                echo   [成功] 目录已删除
            ) else (
                echo   [警告] 目录删除失败
            )
        ) else (
            echo   删除文件: !path!
            del /f /q "!path!" 2>nul
            if !errorLevel! equ 0 (
                echo   [成功] 文件已删除
            ) else (
                echo   [警告] 文件删除失败
            )
        )
    ) else (
        echo   [跳过] 不存在: !path!
    )
)

echo [完成] 清理结束
echo.

endlocal
goto :EOF

