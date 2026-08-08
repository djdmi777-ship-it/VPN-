@echo off
REM Выключает VPN-туннель (AmneziaWG).

set TUNNEL_NAME=pc

"C:\Program Files\AmneziaWG\amneziawg.exe" /uninstalltunnelservice %TUNNEL_NAME%

echo VPN "%TUNNEL_NAME%" выключен.
pause
