tell application "Microsoft PowerPoint" to activate
delay 0.05
tell application "System Events"
	tell process "Microsoft PowerPoint"
		keystroke "l" using command down
	end tell
end tell
