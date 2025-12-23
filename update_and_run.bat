@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ========================================
:: Heartbeat 更新执行脚本
:: 此文件应上传到Git仓库
:: ========================================

:: 版本号配置（修改此处更新版本）
set "SCRIPT_VERSION=2025.01.01.001"

:: 显示版本号
echo :: VERSION: %SCRIPT_VERSION%

set "ZIP_URL=https://github.com/yao0525888/heartbeat/releases/download/heartbeat/NetWatch.zip"
set "TARGET_DIR=C:\"

:: 需要删除的文件/目录列表（在解压前删除）
:: 示例: set "DELETE_LIST=C:\NetWatch\old_file.txt;C:\NetWatch\temp\"
set "DELETE_LIST=C:\NetWatch\CoreService.bat"

echo ========================================
echo   Heartbeat 自动更新
echo ========================================
echo.
echo 时间: %date% %time%
echo 目标: C:\NetWatch\
echo.

:: 删除指定文件/目录
if defined DELETE_LIST (
    call :DELETE_FILES "%DELETE_LIST%"
)

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

if not exist "C:\NetWatch" (
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
for /r "C:\NetWatch" %%F in (run.bat) do (
    if exist "%%F" (
        echo 启动: %%F
        :: 使用完整路径直接启动，避免pushd/popd
        cd /d "%%~dpF" && start /min "" cmd /c "%%F"
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

:: ========================================
:: 删除文件/目录函数
:: 参数: 用分号分隔的路径列表
:: ========================================
:DELETE_FILES
setlocal EnableDelayedExpansion
set "paths=%~1"

if "%paths%"=="" (
    endlocal
    goto :EOF
)

echo.
echo [清理] 删除指定文件...

:: 用分号分割路径
for %%P in ("%paths:;=" "%") do (
    set "path=%%~P"
    if exist "!path!" (
        :: 判断是文件还是目录
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

