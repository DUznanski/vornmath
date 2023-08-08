@echo off
:start
echo 5.1
lua5.1 test\test.lua
echo =========================
echo jit
luajit test\test.lua
echo =========================
echo 5.2
lua52 test\test.lua
echo =========================
echo 5.3
lua53 test\test.lua
echo =========================
echo 5.4
lua54 test\test.lua
pause
cls
goto start