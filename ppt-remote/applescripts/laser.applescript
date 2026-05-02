tell application "Microsoft PowerPoint" to activate
delay 0.05
tell application "System Events"
	tell process "Microsoft PowerPoint"
		keystroke "l"
	end tell
end tell
