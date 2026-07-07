Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = scriptDir
shell.Run Chr(34) & scriptDir & "\start_kokoro_server.bat" & Chr(34), 0, False
