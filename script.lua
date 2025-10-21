local VERSION = "v1.0.0"

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Catppuccin Mocha Colors
local MOCHA = {
    mauve = Color3.fromRGB(203, 166, 247),
    base = Color3.fromRGB(30, 30, 46),
    text = Color3.fromRGB(205, 214, 244),
    green = Color3.fromRGB(166, 227, 161),
    red = Color3.fromRGB(243, 139, 168),
}

-- Config
local CONFIG = {
    barrelName = "PickUpBarrel",
    soundId = "rbxassetid://9068077052",
    authUrl = "https://pastebin.com/raw/S3XNdeyX",
    authInterval = 5,
    notifDuration = 3,
    maxNotifs = 5,
    rainbowSpeed = 1,
    debugMode = true,
}

-- State
local barrels = {}
local boxes = {}
local notifs = {}
local connections = {}
local hue = 0
local isAuthenticated = false
local killLoopActive = false

-- Helpers
local function log(text)
    print(text)
end

local function debug(text)
    if CONFIG.debugMode then
        print(text)
    end
end

local function getPart(barrel)
    if barrel:IsA("BasePart") then return barrel end
    if barrel:IsA("Model") then return barrel.PrimaryPart or barrel:FindFirstChildWhichIsA("BasePart") end
end

local function getSize(barrel)
    if barrel:IsA("BasePart") then return barrel.Size end
    if barrel:IsA("Model") then return barrel:GetExtentsSize() end
    return Vector3.new(4, 4, 4)
end

-- Sound
local function playSound()
    local sound = Instance.new("Sound")
    sound.SoundId = CONFIG.soundId
    sound.Volume = 0.5
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Once(function() sound:Destroy() end)
end

-- Notifications
local function createNotif(msg, color)
    local gui = Instance.new("ScreenGui")
    gui.Name = "OilBarrelNotif"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999999
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 280, 0, 70)
    frame.Position = UDim2.new(1, 0, 1, -120)
    frame.BackgroundColor3 = MOCHA.base
    frame.BorderSizePixel = 0
    frame.Parent = gui

    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = color
    stroke.Thickness = 2

    local msgLbl = Instance.new("TextLabel")
    msgLbl.Text = msg
    msgLbl.Font = Enum.Font.GothamBold
    msgLbl.TextSize = 18
    msgLbl.TextColor3 = MOCHA.text
    msgLbl.BackgroundTransparency = 1
    msgLbl.Size = UDim2.new(1, -16, 1, 0)
    msgLbl.Position = UDim2.new(0, 8, 0, 0)
    msgLbl.TextXAlignment = Enum.TextXAlignment.Center
    msgLbl.TextYAlignment = Enum.TextYAlignment.Center
    msgLbl.TextWrapped = true
    msgLbl.Parent = frame

    return gui, frame
end

local function reposition()
    for i, n in ipairs(notifs) do
        local f = n:FindFirstChildOfClass("Frame")
        if f then
            local y = -120 - ((#notifs - i) * 75)
            f:TweenPosition(UDim2.new(1, -300, 1, y), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        end
    end
end

local function notify(msg, type)
    local color = type == "error" and MOCHA.red or type == "success" and MOCHA.green or MOCHA.mauve
    local gui, frame = createNotif(msg, color)
    
    while #notifs >= CONFIG.maxNotifs do
        local old = table.remove(notifs, 1)
        old:Destroy()
    end
    
    table.insert(notifs, gui)
    reposition()
    
    return gui
end

local function removeNotif(gui)
    if not gui or not gui.Parent then return end
    
    local frame = gui:FindFirstChildOfClass("Frame")
    if frame then
        frame:TweenPosition(UDim2.new(1, 300, 1, frame.Position.Y.Offset), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.3, true)
        task.wait(0.3)
    end
    
    for i, n in ipairs(notifs) do
        if n == gui then
            table.remove(notifs, i)
            break
        end
    end
    gui:Destroy()
    reposition()
end

local function updateNotif(gui, msg, color)
    if not gui or not gui.Parent then return end
    
    local frame = gui:FindFirstChildOfClass("Frame")
    if frame then
        local msgLbl = frame:FindFirstChildOfClass("TextLabel")
        if msgLbl then
            msgLbl.TextTransparency = 1
            msgLbl.Text = msg
            game:GetService("TweenService"):Create(msgLbl, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
        end
        local stroke = frame:FindFirstChildOfClass("UIStroke")
        if stroke and color then
            game:GetService("TweenService"):Create(stroke, TweenInfo.new(0.3), {Color = color}):Play()
        end
    end
end

-- Authentication
local function checkAuth()
    local ok, data = pcall(function()
        return game:HttpGet(CONFIG.authUrl .. "?t=" .. tick(), true)
    end)
    
    if not ok then 
        debug("Auth request failed")
        return false 
    end
    
    local auth = HttpService:JSONDecode(data)
    local name = player.Name:lower()
    
    for _, user in ipairs(auth.users or {}) do
        if name == user:lower() then 
            return true 
        end
    end
    
    return false
end

local function killPlayer()
    if player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then 
            hum.Health = 0 
        end
    end
end

local function startKillLoop()
    if killLoopActive then return end
    
    killLoopActive = true
    killPlayer()
    
    local respawnConn = player.CharacterAdded:Connect(function()
        task.wait(0.1)
        killPlayer()
    end)
    
    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                killPlayer()
            end
        end
    end)
    
    getgenv().OilBarrelESP = {
        killLoop = respawnConn,
        heartbeatKill = heartbeatConn,
        isKillLoopActive = true
    }
end

-- ESP
local function removeESP(barrel)
    local data = barrels[barrel]
    if not data then return end
    
    if data.highlight then data.highlight:Destroy() end
    if data.box then
        data.box:Destroy()
        for i, b in ipairs(boxes) do
            if b == data.box then
                table.remove(boxes, i)
                break
            end
        end
    end
    if data.conn then data.conn:Disconnect() end
    
    barrels[barrel] = nil
end

local function addESP(barrel)
    if barrels[barrel] then return end
    
    local part = getPart(barrel)
    if not part then return end
    
    local highlight = Instance.new("Highlight")
    highlight.FillColor = MOCHA.mauve
    highlight.OutlineColor = MOCHA.mauve
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = barrel
    
    local box = Instance.new("BoxHandleAdornment")
    box.Size = getSize(barrel) * 20
    box.Color3 = MOCHA.mauve
    box.Transparency = 0.7
    box.AlwaysOnTop = true
    box.ZIndex = 1
    box.Adornee = part
    box.Parent = barrel
    
    local detectedNotif = notify("Oil barrel detected", "success")
    task.delay(CONFIG.notifDuration, function()
        removeNotif(detectedNotif)
    end)
    
    barrels[barrel] = {highlight = highlight, box = box, notif = detectedNotif}
    table.insert(boxes, box)
    
    playSound()
    
    local conn = barrel.AncestryChanged:Connect(function()
        if not barrel:IsDescendantOf(workspace) then
            removeESP(barrel)
        end
    end)
    
    table.insert(connections, conn)
    barrels[barrel].conn = conn
end

local function updateRainbow()
    hue = (hue + CONFIG.rainbowSpeed) % 360
    local color = Color3.fromHSV(hue / 360, 1, 1)
    
    for i = #boxes, 1, -1 do
        local box = boxes[i]
        if box and box.Parent then
            box.Color3 = color
        else
            table.remove(boxes, i)
        end
    end
end

-- Cleanup
local function cleanup()
    log("Cleaning up")
    
    for _, c in pairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    
    for b in pairs(barrels) do
        removeESP(b)
    end
    
    for _, g in pairs(playerGui:GetChildren()) do
        if g.Name == "OilBarrelNotif" then g:Destroy() end
    end
    
    barrels = {}
    boxes = {}
    notifs = {}
    connections = {}
end

-- Initialize
if getgenv().OilBarrelESP then
    log("Cleaning old instance")
    
    if getgenv().OilBarrelESP.cleanup then 
        getgenv().OilBarrelESP.cleanup() 
    end
    
    if getgenv().OilBarrelESP.killLoop then 
        getgenv().OilBarrelESP.killLoop:Disconnect() 
    end
    
    if getgenv().OilBarrelESP.heartbeatKill then
        getgenv().OilBarrelESP.heartbeatKill:Disconnect()
    end
    
    killLoopActive = false
    task.wait(0.2)
end

-- Show version notification (now always runs)
local versionNotif = notify(VERSION .. " loading", "success")
task.delay(CONFIG.notifDuration, function()
    removeNotif(versionNotif)
end)
task.wait(0.5)

-- Authentication flow
log("Checking authentication")
local authNotif = notify("Checking authentication", "info")
task.wait(0.25)

if not checkAuth() then
    log("Failed to authenticate")
    updateNotif(authNotif, "Failed to authenticate", MOCHA.red)
    task.wait(3)
    removeNotif(authNotif)
    
    startKillLoop()
    
    return
end

log("Successfully authenticated")
updateNotif(authNotif, "Successfully authenticated", MOCHA.green)

task.delay(CONFIG.notifDuration, function()
    removeNotif(authNotif)
end)

task.wait(0.25)

-- Starting script
log("Starting script")
local scriptNotif = notify("Starting script", "info")
task.wait(0.3)

isAuthenticated = true

-- Auth recheck loop (console only)
local lastCheck = tick()

table.insert(connections, RunService.Heartbeat:Connect(function()
    if tick() - lastCheck < CONFIG.authInterval then return end
    lastCheck = tick()
    
    debug("Rechecking authentication")
    if not checkAuth() then
        log("Auth revoked")
        notify("Access revoked", "error")
        cleanup()
        isAuthenticated = false
        startKillLoop()
    end
end))

-- Rainbow loop
table.insert(connections, RunService.RenderStepped:Connect(updateRainbow))

-- Scan existing barrels
for _, obj in pairs(workspace:GetDescendants()) do
    if obj.Name == CONFIG.barrelName then 
        addESP(obj)
    end
end

-- Watch for new barrels
table.insert(connections, workspace.DescendantAdded:Connect(function(obj)
    if obj.Name == CONFIG.barrelName then 
        addESP(obj) 
    end
end))

-- Script started successfully
log("Script started successfully")
updateNotif(scriptNotif, "Script started successfully", MOCHA.green)

task.delay(CONFIG.notifDuration, function()
    removeNotif(scriptNotif)
end)

getgenv().OilBarrelESP = {
    version = VERSION, 
    cleanup = cleanup,
    isAuthenticated = isAuthenticated,
    isKillLoopActive = killLoopActive
}
