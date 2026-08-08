@echo off
REM Включает VPN-туннель через AmneziaWG (обычный WireGuard блокируется провайдером).
REM Нужен установленный клиент AmneziaWG: https://github.com/amnezia-vpn/amneziawg-windows-client
REM Положи рядом файл pc.conf (скачанный с сервера) и запусти этот файл двойным
REM кликом (попросит права администратора).

set TUNNEL_NAME=pc
set CONF_PATH=%~dp0pc.conf

"C:\Program Files\AmneziaWG\amneziawg.exe" /installtunnelservice "%CONF_PATH%"

echo VPN "%TUNNEL_NAME%" включен.
pause
