-- Cmd+Ctrl+T → iTerm
hs.hotkey.bind({"cmd", "ctrl"}, "t", function()
  hs.application.launchOrFocus("iTerm")
end)

-- Cmd+Ctrl+B → Chrome
hs.hotkey.bind({"cmd", "ctrl"}, "b", function()
  hs.application.launchOrFocus("Google Chrome")
end)
