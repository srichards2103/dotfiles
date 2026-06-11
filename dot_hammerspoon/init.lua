-- Cmd+Ctrl+F → Ghostty
hs.hotkey.bind({ "cmd", "ctrl" }, "f", function()
	hs.application.launchOrFocus("Ghostty")
end)

-- Cmd+Ctrl+D → Chrome
hs.hotkey.bind({ "cmd", "ctrl" }, "d", function()
	hs.application.launchOrFocus("Google Chrome")
end)

-- Cmd+Ctrl+S → Spotify
hs.hotkey.bind({ "cmd", "ctrl" }, "s", function()
	hs.application.launchOrFocus("Spotify")
end)

-- Cmd+Ctrl+A → Docker
hs.hotkey.bind({ "cmd", "ctrl" }, "a", function()
	hs.application.launchOrFocus("Docker Desktop")
end)
