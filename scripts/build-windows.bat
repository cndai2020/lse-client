@echo off
rem LSE Build Script - Windows
rem 本地构建 Windows EXE

cd /d "%~dp0"

echo === LSE Windows 构建脚本 ===
echo.

rem 1. 检查 Flutter
where flutter >nul 2>&1
if errorlevel 1 (
    echo Flutter 未安装
    exit /b 1
)

rem 2. 拉取依赖
echo 拉取 Flutter 依赖...
call flutter pub get

rem 3. 构建
echo 构建 Windows Release...
call flutter build windows --release

rem 4. 打包
echo 打包 EXE...
powershell -Command "Compress-Archive -Path 'build\windows\runner\Release\*' -DestinationPath 'build\windows\runner\Release\lse-windows.zip' -Force"

echo.
echo 构建完成！
echo 产物: build\windows\runner\Release\lse-windows.zip
