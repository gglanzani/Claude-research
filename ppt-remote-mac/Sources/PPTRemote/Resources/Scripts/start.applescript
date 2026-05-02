tell application "Microsoft PowerPoint"
	activate
	if (count of slide show windows) is 0 then
		run slide show slide show settings of active presentation
	end if
end tell
