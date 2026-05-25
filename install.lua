-- Installer for Water Line Control from Kwazzi44/Waterline-
-- Run in OpenComputers: wget -f https://raw.githubusercontent.com/Kwazzi44/Waterline-/main/install.lua && install

local shell = require("shell")
local filesystem = require("filesystem")
local internet = require("internet")

local baseUrl = "https://raw.githubusercontent.com/Kwazzi44/Waterline-/main/"

local files = {
  "main.lua",
  "config.lua",
  "version.lua",
  "lib/component-discover-lib.lua",
  "lib/gt-sensor-parser.lua",
  "lib/gui-lib.lua",
  "lib/list-lib.lua",
  "lib/program-lib.lua",
  "lib/state-machine-lib.lua",
  "lib/gui-widgets/scroll-list.lua",
  "lib/logger-handler/discord-logger-handler-lib.lua",
  "lib/logger-handler/file-logger-handler-lib.lua",
  "lib/logger-handler/scroll-list-logger-handler-lib.lua",
  "src/line-controller.lua",
  "src/t3-controller.lua",
  "src/t4-controller.lua",
  "src/t5-controller.lua",
  "src/t6-controller.lua",
  "src/t7-controller.lua",
  "src/t8-controller.lua"
}

print("Starting installation of Water Line Control...")

-- Helper function to download a file
local function downloadFile(relativeUrl, localPath)
  local url = baseUrl .. relativeUrl
  print("Downloading: " .. relativeUrl)
  
  -- Create parent directory if it does not exist
  local directory = filesystem.path(localPath)
  if not filesystem.exists(directory) then
    filesystem.makeDirectory(directory)
  end
  
  local response, err = internet.request(url)
  if not response then
    print("Error connecting to: " .. url .. " -> " .. tostring(err))
    return false
  end
  
  local file, fileErr = io.open(localPath, "w")
  if not file then
    print("Error opening local file: " .. localPath .. " -> " .. tostring(fileErr))
    return false
  end
  
  for chunk in response do
    file:write(chunk)
  end
  
  file:close()
  return true
end

-- Create directories
filesystem.makeDirectory("/home/lib")
filesystem.makeDirectory("/home/lib/gui-widgets")
filesystem.makeDirectory("/home/lib/logger-handler")
filesystem.makeDirectory("/home/home") -- In case files need it, or we install to /home
filesystem.makeDirectory("/home/src")

-- Download each file
local success = true
for _, file in ipairs(files) do
  local localPath = "/home/" .. file
  if not downloadFile(file, localPath) then
    success = false
    print("Failed to download: " .. file)
    break
  end
end

if success then
  print("\nInstallation completed successfully!")
  print("You can now edit /home/config.lua and start the program using: main")
else
  print("\nInstallation failed during download. Please check internet connection.")
end
