@echo off
rem SOUND DEMO (branch sound-demo): spectate an AI match and compare the sound sets. Keys: README-DEMO.md
set "GODOT=H:\My Drive\PROJECTS\Ooze Syndicate\Tools\Godot\Godot_v4.6.1-stable_win64.exe"
set "PROJ=C:\Users\itisf\AppData\Local\Temp\claude\H--My-Drive-PROJECTS-Ooze-Syndicate\df687da1-90a4-45c7-8c37-69d34e37f256\scratchpad\sound-demo"
rem (a copy of this folder elsewhere runs from where the .bat sits)
if not exist "%PROJ%\project.godot" set "PROJ=%~dp0."
start "" "%GODOT%" --path "%PROJ%" --resolution 1600x900 res://demo/sound_demo.tscn
