tell application "Microsoft PowerPoint"
	activate
	try
		exit slide show slide show window 1
	on error
		try
			tell application "System Events"
				tell process "Microsoft PowerPoint"
					key code 53
				end tell
			end tell
		end try
	end try
end tell
