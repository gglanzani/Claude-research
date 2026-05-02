tell application "Microsoft PowerPoint" to activate
try
	tell application "Microsoft PowerPoint"
		tell slide show view of slide show window 1 to go to previous slide
	end tell
on error
	tell application "System Events"
		tell process "Microsoft PowerPoint"
			key code 123
		end tell
	end tell
end try
