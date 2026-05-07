@echo off
title Chella Collectibles - Remove Sold Card
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Sold-Card.ps1"
pause