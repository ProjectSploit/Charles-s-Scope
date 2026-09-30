--[[
    Charles's DevConsole
    A self-contained Roblox client-side Luau inspection/debug console.

    Highlights:
      - Multi-line Luau execution
      - Reliable print/warn capture with environment injection + fallback hook
      - Full error capture with tracebacks when available
      - Resizable + draggable UI (mouse/touch)
      - Command history
      - Copyable complete reports
      - Structured inspection/recon commands
      - Remote call observation (when the executor exposes metamethod hooks)
      - Executor capability detection
      - No external dependencies
]]

-- ============================================================
-- SERVICES / GLOBALS
-- ============================================================
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local CoreGui      = game:GetService("CoreGui")

local LP = Players.LocalPlayer

-- ============================================================
-- THEME
-- ============================================================
local C = {
    bg      = Color3.fromRGB(16, 16, 20),
    panel   = Color3.fromRGB(23, 23, 29),
    panel2  = Color3.fromRGB(32, 32, 40),
    panel3  = Color3.fromRGB(45, 45, 56),
    accent  = Color3.fromRGB(88, 132, 255),
    accent2 = Color3.fromRGB(137, 173, 255),
    text    = Color3.fromRGB(232, 232, 240),
    dim     = Color3.fromRGB(143, 143, 158),
    err     = Color3.fromRGB(255, 108, 108),
    warn    = Color3.fromRGB(255, 194, 100),
    ok      = Color3.fromRGB(120, 224, 150),
    border  = Color3.fromRGB(51, 51, 63),
}

local FONT      = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local FONT_MONO = Enum.Font.Code

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or C.border
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function padding(parent, top, right, bottom, left)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, top or 0)
    p.PaddingRight  = UDim.new(0, right or 0)
    p.PaddingBottom = UDim.new(0, bottom or 0)
    p.PaddingLeft   = UDim.new(0, left or 0)
    p.Parent = parent
    return p
end

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function safeToString(v)
    local ok, result = pcall(tostring, v)
    return ok and result or "<tostring error>"
end

local function joinArgs(...)
    local n = select("#", ...)
    local out = table.create and table.create(n) or {}
    for i = 1, n do
        out[i] = safeToString(select(i, ...))
    end
    return table.concat(out, " ")
end

local function copyToClipboard(text)
    return pcall(function()
        if setclipboard then
            setclipboard(text)
        elseif toclipboard then
            toclipboard(text)
        elseif setrbxclipboard then
            setrbxclipboard(text)
        else
            error("clipboard API unavailable")
        end
    end)
end

local function resolveParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then
            return h
        end
    end

    local ok, cg = pcall(function()
        return CoreGui
    end)
    if ok and cg then
        return cg
    end

    return LP:WaitForChild("PlayerGui")
end

-- ============================================================
-- ROOT GUI
-- ============================================================
local existing = nil
pcall(function()
    local parent = resolveParent()
    existing = parent:FindFirstChild("CharlesDevConsole")
end)
if existing then
    pcall(function() existing:Destroy() end)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CharlesDevConsole"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 9999

local guiParent = resolveParent()
local parentOK = pcall(function()
    ScreenGui.Parent = guiParent
end)
if not parentOK or not ScreenGui.Parent then
    ScreenGui.Parent = LP:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(620, 430)
Main.Position = UDim2.new(0.5, -310, 0.5, -215)
Main.BackgroundColor3 = C.bg
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui
corner(Main, 13)
stroke(Main, C.border, 1)

-- ============================================================
-- TITLE BAR
-- ============================================================
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = C.panel
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main

local AccentBar = Instance.new("Frame")
AccentBar.Size = UDim2.fromOffset(3, 18)
AccentBar.Position = UDim2.new(0, 13, 0.5, -9)
AccentBar.BackgroundColor3 = C.accent
AccentBar.BorderSizePixel = 0
AccentBar.Parent = TitleBar
corner(AccentBar, 2)

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 24, 0, 0)
Title.Size = UDim2.new(1, -125, 1, 0)
Title.Font = FONT_BOLD
Title.TextSize = 14
Title.TextColor3 = C.text
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "Charles's DevConsole"
Title.ZIndex = 10
Title.Parent = TitleBar

local Subtitle = Instance.new("TextLabel")
Subtitle.BackgroundTransparency = 1
Subtitle.Position = UDim2.new(0, 190, 0, 0)
Subtitle.Size = UDim2.new(1, -315, 1, 0)
Subtitle.Font = FONT
Subtitle.TextSize = 11
Subtitle.TextColor3 = C.dim
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Text = "client inspection / runtime console"
Subtitle.ZIndex = 10
Subtitle.Parent = TitleBar

local function titleButton(text, xOffset, hoverColor)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(31, 31)
    b.Position = UDim2.new(1, xOffset, 0.5, -15)
    b.BackgroundColor3 = C.panel
    b.BorderSizePixel = 0
    b.Font = FONT_BOLD
    b.TextSize = 15
    b.TextColor3 = C.dim
    b.Text = text
    b.AutoButtonColor = false
    b.ZIndex = 20
    b.Parent = TitleBar
    corner(b, 7)

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {
            BackgroundColor3 = hoverColor or C.panel2,
            TextColor3 = C.text,
        }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {
            BackgroundColor3 = C.panel,
            TextColor3 = C.dim,
        }):Play()
    end)

    return b
end

local CloseBtn = titleButton("✕", -40, Color3.fromRGB(198, 66, 66))
local MinBtn   = titleButton("—", -76)

-- ============================================================
-- CONTENT
-- ============================================================
local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Position = UDim2.fromOffset(12, 50)
Content.Size = UDim2.new(1, -24, 1, -62)
Content.BackgroundTransparency = 1
Content.Parent = Main

local InputLabel = Instance.new("TextLabel")
InputLabel.BackgroundTransparency = 1
InputLabel.Font = FONT_BOLD
InputLabel.TextSize = 11
InputLabel.TextColor3 = C.dim
InputLabel.TextXAlignment = Enum.TextXAlignment.Left
InputLabel.Text = "INPUT"
InputLabel.Parent = Content

local OutputLabel = Instance.new("TextLabel")
OutputLabel.BackgroundTransparency = 1
OutputLabel.Font = FONT_BOLD
OutputLabel.TextSize = 11
OutputLabel.TextColor3 = C.dim
OutputLabel.TextXAlignment = Enum.TextXAlignment.Left
OutputLabel.Text = "OUTPUT"
OutputLabel.Parent = Content

local InputBox = Instance.new("TextBox")
InputBox.Name = "Input"
InputBox.BackgroundColor3 = C.panel
InputBox.BorderSizePixel = 0
InputBox.Font = FONT_MONO
InputBox.TextSize = 13
InputBox.TextColor3 = C.text
InputBox.PlaceholderColor3 = C.dim
InputBox.PlaceholderText = "-- type Lua or :help for built-in commands"
InputBox.Text = ""
InputBox.MultiLine = true
InputBox.TextWrapped = false
InputBox.TextXAlignment = Enum.TextXAlignment.Left
InputBox.TextYAlignment = Enum.TextYAlignment.Top
InputBox.ClearTextOnFocus = false
InputBox.Parent = Content
corner(InputBox, 8)
stroke(InputBox, C.border, 1)
padding(InputBox, 8, 10, 8, 10)

local OutputScroll = Instance.new("ScrollingFrame")
OutputScroll.Name = "Output"
OutputScroll.BackgroundColor3 = C.panel
OutputScroll.BorderSizePixel = 0
OutputScroll.ScrollBarThickness = 5
OutputScroll.ScrollBarImageColor3 = C.panel3
OutputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
OutputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OutputScroll.ScrollingDirection = Enum.ScrollingDirection.Y
OutputScroll.Parent = Content
corner(OutputScroll, 8)
stroke(OutputScroll, C.border, 1)
padding(OutputScroll, 8, 10, 8, 10)

local OutputLayout = Instance.new("UIListLayout")
OutputLayout.Padding = UDim.new(0, 3)
OutputLayout.SortOrder = Enum.SortOrder.LayoutOrder
OutputLayout.Parent = OutputScroll

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Font = FONT
Status.TextSize = 11
Status.TextColor3 = C.dim
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "Ready"
Status.Parent = Content

local ButtonRow = Instance.new("Frame")
ButtonRow.BackgroundTransparency = 1
ButtonRow.Parent = Content

local BtnLayout = Instance.new("UIListLayout")
BtnLayout.FillDirection = Enum.FillDirection.Horizontal
BtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
BtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
BtnLayout.Padding = UDim.new(0, 6)
BtnLayout.SortOrder = Enum.SortOrder.LayoutOrder
BtnLayout.Parent = ButtonRow

local function makeButton(text, width, baseColor, textColor)
    local base = baseColor or C.panel2
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(width, 32)
    b.BackgroundColor3 = base
    b.BorderSizePixel = 0
    b.Font = FONT
    b.TextSize = 12
    b.TextColor3 = textColor or C.text
    b.Text = text
    b.AutoButtonColor = false
    b.Parent = ButtonRow
    corner(b, 7)

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {
            BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.11),
        }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {
            BackgroundColor3 = base,
        }):Play()
    end)

    return b
end

local RunBtn      = makeButton("Run",        64, C.accent, Color3.new(1, 1, 1))
local PresetBtn   = makeButton("Presets",    72)
local HistoryBtn  = makeButton("History",    76)
local CopyLogBtn  = makeButton("Copy Log",   82)
local CopyInBtn   = makeButton("Copy Input", 88)
local ClearBtn    = makeButton("Clear",      68)

-- ============================================================
-- RESIZE HANDLE
-- ============================================================
-- Dedicated title-bar drag surface. It sits behind the title text/buttons and avoids
-- relying on child TextLabels to propagate InputBegan events.
local DragArea = Instance.new("TextButton")
DragArea.Name = "DragArea"
DragArea.BackgroundTransparency = 1
DragArea.BorderSizePixel = 0
DragArea.Text = ""
DragArea.AutoButtonColor = false
DragArea.ZIndex = 5
DragArea.Parent = TitleBar

local ResizeHandle = Instance.new("TextButton")
ResizeHandle.Name = "ResizeHandle"
ResizeHandle.BackgroundColor3 = C.panel2
ResizeHandle.BackgroundTransparency = 0.15
ResizeHandle.BorderSizePixel = 0
ResizeHandle.Text = "◢"
ResizeHandle.Font = FONT_BOLD
ResizeHandle.TextSize = 13
ResizeHandle.TextColor3 = C.dim
ResizeHandle.AutoButtonColor = false
ResizeHandle.ZIndex = 100
ResizeHandle.Parent = Main
corner(ResizeHandle, 5)

ResizeHandle.MouseEnter:Connect(function()
    ResizeHandle.TextColor3 = C.accent2
end)
ResizeHandle.MouseLeave:Connect(function()
    ResizeHandle.TextColor3 = C.dim
end)

-- ============================================================
-- STATUS / LOGGING
-- ============================================================
local Buffer = {}
local LineLabels = {}
local CommandHistory = {}
local HistoryIndex = 0
local MAX_LINES = 2500

local function setStatus(text, color)
    Status.Text = tostring(text)
    Status.TextColor3 = color or C.dim
end

local function scrollToBottom()
    task.defer(function()
        pcall(function()
            local target = OutputScroll.AbsoluteCanvasSize.Y - OutputScroll.AbsoluteSize.Y
            if target > 0 then
                OutputScroll.CanvasPosition = Vector2.new(0, target)
            end
        end)
    end)
end

local function addLine(text, kind)
    local color = C.text
    if kind == "in" then color = C.accent2
    elseif kind == "err" then color = C.err
    elseif kind == "warn" then color = C.warn
    elseif kind == "ok" then color = C.ok
    elseif kind == "dim" then color = C.dim
    end

    local line = Instance.new("TextLabel")
    line.BackgroundTransparency = 1
    line.Size = UDim2.new(1, 0, 0, 0)
    line.AutomaticSize = Enum.AutomaticSize.Y
    line.Font = FONT_MONO
    line.TextSize = 13
    line.TextColor3 = color
    line.TextXAlignment = Enum.TextXAlignment.Left
    line.TextYAlignment = Enum.TextYAlignment.Top
    line.TextWrapped = true
    line.Text = tostring(text)
    line.Parent = OutputScroll

    table.insert(LineLabels, line)

    while #Buffer > MAX_LINES do
        table.remove(Buffer, 1)
        local old = table.remove(LineLabels, 1)
        if old then
            old:Destroy()
        end
    end

    scrollToBottom()
end

local function record(text, kind)
    table.insert(Buffer, tostring(text))
    addLine(text, kind)
end

local function clearLog()
    table.clear(Buffer)
    for _, lbl in ipairs(LineLabels) do
        pcall(function() lbl:Destroy() end)
    end
    table.clear(LineLabels)
    setStatus("Log cleared", C.dim)
end

local function emitBlock(title, lines, kind)
    record("========== " .. tostring(title) .. " ==========" , "ok")
    for _, line in ipairs(lines or {}) do
        record(line, kind or "out")
    end
end

-- ============================================================
-- OUTPUT CAPTURE
-- ============================================================
local realPrint = print
local realWarn  = warn

local function capturePrint(...)
    local line = joinArgs(...)
    record(line, "out")
    pcall(realPrint, "[Charles's DevConsole] " .. line)
end

local function captureWarn(...)
    local line = joinArgs(...)
    record(line, "warn")
    pcall(realWarn, "[Charles's DevConsole] " .. line)
end

local function buildExecutionEnvironment()
    local base = nil

    pcall(function()
        if getgenv then
            base = getgenv()
        elseif getfenv then
            base = getfenv()
        else
            base = _G
        end
    end)

    base = base or _G

    local env = {
        print = capturePrint,
        warn = captureWarn,
    }

    return setmetatable(env, {
        __index = base,
        __newindex = base,
    })
end

local function executeCode(code)
    local loader = loadstring or load
    if type(loader) ~= "function" then
        record("[error] no loadstring/load available in this executor", "err")
        setStatus("No loader", C.err)
        return false
    end

    local t0 = os.clock()
    local env = buildExecutionEnvironment()
    local chunk, compileErr

    -- Prefer Lua's environment-aware `load` when an executor exposes it.
    -- Fall back to `loadstring`, then use setfenv when available.
    local loadedWithEnv = false
    if type(load) == "function" then
        local ok, a, b = pcall(load, code, "=CharlesDevConsole", "t", env)
        if ok and a then
            chunk = a
            loadedWithEnv = true
        elseif ok then
            compileErr = b
        else
            compileErr = a
        end
    end

    if not chunk then
        local ok, a, b = pcall(loader, code, "=CharlesDevConsole")
        if ok and a then
            chunk = a
        elseif ok then
            compileErr = b or a
        else
            compileErr = a
        end
    end

    if not chunk then
        record("[compile error] " .. safeToString(compileErr), "err")
        setStatus("Compile error", C.err)
        return false
    end

    local envApplied = loadedWithEnv

    if not envApplied and setfenv then
        local ok = pcall(function()
            setfenv(chunk, env)
        end)
        envApplied = ok
    end

    local oldGlobalPrint = print
    local oldGlobalWarn = warn
    local globalFallbackApplied = false

    if not envApplied then
        local ok = pcall(function()
            print = capturePrint
            warn = captureWarn
        end)
        globalFallbackApplied = ok
    end

    local results = {}
    local runOK, runErr

    local tracebackFn = function(err)
        local msg = safeToString(err)
        local dbg = debug
        if dbg and type(dbg.traceback) == "function" then
            local ok, trace = pcall(dbg.traceback, msg, 2)
            if ok and trace then
                return trace
            end
        end
        return msg
    end

    -- Keep every chunk return value. This is intentionally simple so it works
    -- across executors that expose slightly different Lua compatibility layers.
    local packed
    if type(xpcall) == "function" then
        local callOK, callResults = pcall(function()
            return {xpcall(chunk, tracebackFn)}
        end)
        if callOK and callResults then
            packed = callResults
        else
            packed = {false, callResults}
        end
    else
        local callOK, callResults = pcall(function()
            return {pcall(chunk)}
        end)
        if callOK and callResults then
            packed = callResults
        else
            packed = {false, callResults}
        end
    end

    if globalFallbackApplied then
        pcall(function()
            print = oldGlobalPrint
            warn = oldGlobalWarn
        end)
    end

    runOK = packed[1]
    if not runOK then
        runErr = packed[2]
    else
        for i = 2, #packed do
            results[#results + 1] = packed[i]
        end
    end

    local dt = (os.clock() - t0) * 1000

    if not runOK then
        record("[runtime error] " .. safeToString(runErr), "err")
        setStatus(string.format("Error (%.1f ms)", dt), C.err)
        return false
    end

    local returned = 0
    for i, value in ipairs(results or {}) do
        -- xpcall/pcall state values can get nested in edge cases. The first value
        -- from the chunk is still useful, and all values are shown in order.
        if value ~= nil then
            record(string.format("[returned #%d] %s", i, safeToString(value)), "ok")
            returned = returned + 1
        end
    end

    record(string.format("[done in %.1f ms%s]", dt, returned > 0 and string.format(", %d return value(s)", returned) or ""), "dim")
    setStatus(string.format("Done in %.1f ms", dt), C.ok)
    return true
end

-- ============================================================
-- PATH / INSPECTION HELPERS
-- ============================================================
local function resolvePath(path)
    path = trim(path)
    if path == "" or path == "game" then
        return game
    end

    if path:sub(1, 5) == "game." then
        path = path:sub(6)
    end

    local current = game
    for part in path:gmatch("[^%.]+") do
        local ok, child = pcall(function()
            return current:FindFirstChild(part)
        end)
        if not ok or not child then
            return nil
        end
        current = child
    end
    return current
end

local function dumpValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 4 then
        return "<max depth>"
    end

    local valueType = typeof(v)
    if valueType ~= "table" then
        return safeToString(v)
    end

    if seen[v] then
        return "<cycle>"
    end
    seen[v] = true

    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end

    table.sort(keys, function(a, b)
        return safeToString(a) < safeToString(b)
    end)

    local out = {"{"}
    for _, k in ipairs(keys) do
        local ok, value = pcall(function()
            return v[k]
        end)
        out[#out + 1] = string.rep("  ", depth + 1) .. "[" .. safeToString(k) .. "] = " .. (ok and dumpValue(value, depth + 1, seen) or "<error>")
    end
    out[#out + 1] = string.rep("  ", depth) .. "}"
    return table.concat(out, "\n")
end

local function commandHelp()
    emitBlock("COMMANDS", {
        ":help                             show this list",
        ":caps                             detect available runtime/executor APIs",
        ":env                              client/game environment information",
        ":players                          list current players",
        ":services                         list common Roblox services",
        ":remotes                          enumerate replicated RemoteEvents/Functions",
        ":find <text>                      search replicated instance names/paths",
        ":egg                              search replicated instances containing 'egg'",
        ":tree [path] [depth]              print a replicated hierarchy",
        ":inspect <path>                   inspect instance metadata/attributes",
        ":attrs <path>                     print attributes on an instance",
        ":children <path>                  list immediate children of an instance",
        ":scripts                          list replicated Script/LocalScript/ModuleScript objects",
        ":history                           show command history",
        ":clear                             clear output",
        ":copy                              copy complete output",
        ":spy                              toggle remote-call observation",
        ":spyoff                            disable remote-call observation",
        "Normal Luau input executes below the command layer.",
        "Hotkeys: F2 toggle | F4 run | Ctrl+Enter run",
    })
end

local function commandCaps()
    local names = {
        "loadstring", "load", "gethui", "setclipboard", "toclipboard", "setrbxclipboard",
        "getrawmetatable", "setreadonly", "newcclosure", "hookfunction", "hookmetamethod",
        "getnamecallmethod", "getgc", "getgenv", "getfenv", "setfenv", "identifyexecutor",
        "getexecutorname", "request", "http_request", "syn", "getconnections", "firesignal"
    }

    local lines = {}
    local execName = "unknown"

    pcall(function()
        if identifyexecutor then
            execName = safeToString(identifyexecutor())
        end
    end)
    if execName == "unknown" then
        pcall(function()
            if getexecutorname then
                execName = safeToString(getexecutorname())
            end
        end)
    end

    lines[#lines + 1] = "Executor: " .. execName
    for _, name in ipairs(names) do
        local exists = false
        pcall(function()
            exists = type(_G[name]) ~= "nil"
        end)
        if not exists then
            pcall(function()
                exists = type((getgenv and getgenv() or _G)[name]) ~= "nil"
            end)
        end
        lines[#lines + 1] = string.format("%-20s %s", name, exists and "YES" or "no")
    end

    emitBlock("CAPABILITIES", lines)
end

local function commandEnv()
    local lines = {
        "PlaceId:      " .. safeToString(game.PlaceId),
        "GameId:       " .. safeToString(game.GameId),
        "JobId:        " .. safeToString(game.JobId),
        "Loaded:       " .. safeToString(game:IsLoaded()),
        "LocalPlayer:  " .. safeToString(LP and LP.Name or "nil"),
        "UserId:       " .. safeToString(LP and LP.UserId or "nil"),
        "AccountAge:   " .. safeToString(LP and LP.AccountAge or "nil"),
        "Camera:       " .. safeToString(workspace.CurrentCamera),
        "Heartbeat:    " .. safeToString(RunService.Heartbeat),
    }
    emitBlock("ENVIRONMENT", lines)
end

local function commandPlayers()
    local lines = {}
    for _, player in ipairs(Players:GetPlayers()) do
        lines[#lines + 1] = string.format(
            "%s | %s | UserId=%s | AccountAge=%s",
            player.Name,
            player.DisplayName,
            player.UserId,
            player.AccountAge
        )
    end
    table.sort(lines)
    emitBlock("PLAYERS (" .. #lines .. ")", lines)
end

local function commandServices()
    local names = {
        "Players", "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui",
        "StarterPlayer", "Lighting", "SoundService", "TextChatService", "UserInputService",
        "HttpService", "RunService", "TweenService", "CoreGui"
    }

    local lines = {}
    for _, name in ipairs(names) do
        local ok, service = pcall(game.GetService, game, name)
        lines[#lines + 1] = string.format(
            "%-22s %s",
            name,
            ok and safeToString(service:GetFullName()) or "unavailable"
        )
    end
    emitBlock("SERVICES", lines)
end

local function commandRemotes()
    local lines = {}
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            lines[#lines + 1] = string.format("[%s] %s", obj.ClassName, obj:GetFullName())
        end
    end
    table.sort(lines)
    emitBlock("REMOTES (" .. #lines .. ")", lines)
end

local function commandFind(term)
    term = trim(term):lower()
    if term == "" then
        record("Usage: :find <text>", "warn")
        return
    end

    local lines = {}
    for _, obj in ipairs(game:GetDescendants()) do
        local name = obj.Name:lower()
        local path = obj:GetFullName():lower()
        if name:find(term, 1, true) or path:find(term, 1, true) then
            lines[#lines + 1] = string.format("[%s] %s", obj.ClassName, obj:GetFullName())
        end
    end

    table.sort(lines)
    emitBlock("FIND: " .. term .. " (" .. #lines .. ")", lines)
end

local function commandTree(path, depth)
    local root = resolvePath(path or "game")
    if not root then
        record("Path not found: " .. safeToString(path), "err")
        return
    end

    depth = math.clamp(tonumber(depth) or 2, 0, 6)

    local lines = {
        root:GetFullName() .. " [" .. root.ClassName .. "]"
    }

    local function walk(node, level)
        if level > depth then
            return
        end

        local children = node:GetChildren()
        table.sort(children, function(a, b)
            return a.Name:lower() < b.Name:lower()
        end)

        for _, child in ipairs(children) do
            lines[#lines + 1] = string.rep("  ", level) .. "- " .. child.Name .. " [" .. child.ClassName .. "]"
            walk(child, level + 1)
        end
    end

    walk(root, 1)
    emitBlock("TREE", lines)
end

local function commandInspect(path)
    local obj = resolvePath(path)
    if not obj then
        record("Path not found: " .. safeToString(path), "err")
        return
    end

    local lines = {
        "Name:       " .. safeToString(obj.Name),
        "ClassName:  " .. safeToString(obj.ClassName),
        "FullName:   " .. safeToString(obj:GetFullName()),
        "Parent:     " .. safeToString(obj.Parent and obj.Parent:GetFullName() or "nil"),
        "Children:   " .. safeToString(#obj:GetChildren()),
        "Archivable: " .. safeToString(obj.Archivable),
    }

    local attributes = obj:GetAttributes()
    local keys = {}
    for key in pairs(attributes) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    if #keys > 0 then
        lines[#lines + 1] = "Attributes:"
        for _, key in ipairs(keys) do
            lines[#lines + 1] = "  " .. safeToString(key) .. " = " .. dumpValue(attributes[key])
        end
    else
        lines[#lines + 1] = "Attributes: <none>"
    end

    emitBlock("INSPECT", lines)
end

local function commandAttributes(path)
    local obj = resolvePath(path)
    if not obj then
        record("Path not found: " .. safeToString(path), "err")
        return
    end

    local attributes = obj:GetAttributes()
    local keys = {}
    for key in pairs(attributes) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    local lines = {"Path: " .. obj:GetFullName()}
    if #keys == 0 then
        lines[#lines + 1] = "<no attributes>"
    else
        for _, key in ipairs(keys) do
            lines[#lines + 1] = safeToString(key) .. " = " .. dumpValue(attributes[key])
        end
    end
    emitBlock("ATTRIBUTES", lines)
end

local function commandChildren(path)
    local obj = resolvePath(path)
    if not obj then
        record("Path not found: " .. safeToString(path), "err")
        return
    end

    local lines = {}
    for _, child in ipairs(obj:GetChildren()) do
        lines[#lines + 1] = string.format("[%s] %s", child.ClassName, child.Name)
    end
    table.sort(lines)
    emitBlock("CHILDREN: " .. obj:GetFullName() .. " (" .. #lines .. ")", lines)
end

local function commandScripts()
    local lines = {}
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
            lines[#lines + 1] = string.format("[%s] %s", obj.ClassName, obj:GetFullName())
        end
    end
    table.sort(lines)
    emitBlock("SCRIPTS (" .. #lines .. ")", lines)
end

-- ============================================================
-- REMOTE OBSERVER
-- ============================================================
local RemoteSpyInstalled = false
local RemoteSpyRestore = nil

local function installRemoteSpy()
    if RemoteSpyInstalled then
        record("[spy] already installed", "warn")
        return
    end

    local ok, err = pcall(function()
        if hookmetamethod and newcclosure and getnamecallmethod then
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    record(string.format(
                        "[remote] %s %s args=%s",
                        method,
                        safeToString(self:GetFullName()),
                        joinArgs(...)
                    ), "warn")
                end
                return old(self, ...)
            end))

            RemoteSpyRestore = function()
                -- Executors differ here. Re-hooking the saved function is the
                -- most broadly compatible restoration method.
                pcall(function()
                    hookmetamethod(game, "__namecall", old)
                end)
                RemoteSpyRestore = nil
                RemoteSpyInstalled = false
            end
            RemoteSpyInstalled = true
            return
        end

        if getrawmetatable and setreadonly and newcclosure and getnamecallmethod then
            local mt = getrawmetatable(game)
            local oldNamecall = mt.__namecall
            setreadonly(mt, false)
            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    record(string.format(
                        "[remote] %s %s args=%s",
                        method,
                        safeToString(self:GetFullName()),
                        joinArgs(...)
                    ), "warn")
                end
                return oldNamecall(self, ...)
            end)
            setreadonly(mt, true)

            RemoteSpyRestore = function()
                pcall(function()
                    setreadonly(mt, false)
                    mt.__namecall = oldNamecall
                    setreadonly(mt, true)
                end)
                RemoteSpyRestore = nil
                RemoteSpyInstalled = false
            end
            RemoteSpyInstalled = true
            return
        end

        error("no supported metamethod hook API")
    end)

    if ok then
        record("[spy] remote call observer installed", "ok")
    else
        record("[spy] failed: " .. safeToString(err), "err")
    end
end

local function uninstallRemoteSpy()
    if not RemoteSpyInstalled then
        return
    end

    if RemoteSpyRestore then
        pcall(RemoteSpyRestore)
    end
    RemoteSpyRestore = nil
    RemoteSpyInstalled = false
    record("[spy] remote call observer disabled", "ok")
end

-- ============================================================
-- BUILT-IN COMMAND DISPATCH
-- ============================================================
local function runBuiltinCommand(line)
    local body = trim(line:sub(2))
    local cmd, rest = body:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    local a, b = rest:match("^(%S+)%s*(.*)$")

    if cmd == "help" or cmd == "?" then
        commandHelp()
    elseif cmd == "caps" then
        commandCaps()
    elseif cmd == "env" then
        commandEnv()
    elseif cmd == "players" then
        commandPlayers()
    elseif cmd == "services" then
        commandServices()
    elseif cmd == "remotes" then
        commandRemotes()
    elseif cmd == "find" then
        commandFind(rest)
    elseif cmd == "egg" then
        commandFind("egg")
    elseif cmd == "tree" then
        commandTree(a or "game", b ~= "" and b or "2")
    elseif cmd == "inspect" then
        commandInspect(rest)
    elseif cmd == "attrs" then
        commandAttributes(rest)
    elseif cmd == "children" then
        commandChildren(rest)
    elseif cmd == "scripts" then
        commandScripts()
    elseif cmd == "history" then
        local lines = {}
        for i, value in ipairs(CommandHistory) do
            lines[#lines + 1] = string.format("%03d  %s", i, value:gsub("\n", "\\n"))
        end
        emitBlock("HISTORY (" .. #lines .. ")", lines)
    elseif cmd == "clear" then
        clearLog()
    elseif cmd == "copy" then
        local report = table.concat(Buffer, "\n")
        if copyToClipboard(report) then
            setStatus("Copied " .. #Buffer .. " lines", C.ok)
        else
            setStatus("Clipboard unavailable", C.err)
        end
    elseif cmd == "spy" then
        installRemoteSpy()
    elseif cmd == "spyoff" then
        uninstallRemoteSpy()
    else
        record("Unknown command: " .. cmd .. " | use :help", "warn")
    end
end

-- ============================================================
-- EXECUTION / HISTORY
-- ============================================================
local function pushHistory(code)
    if trim(code) == "" then
        return
    end
    if CommandHistory[#CommandHistory] == code then
        HistoryIndex = #CommandHistory + 1
        return
    end

    CommandHistory[#CommandHistory + 1] = code
    if #CommandHistory > 100 then
        table.remove(CommandHistory, 1)
    end
    HistoryIndex = #CommandHistory + 1
end

local function runCode()
    local code = InputBox.Text
    if trim(code) == "" then
        setStatus("Nothing to run", C.warn)
        return
    end

    pushHistory(code)
    record("", "dim")
    record("> " .. code:gsub("\n", "\n> "), "in")

    if code:sub(1, 1) == ":" and not code:find("\n", 1, true) then
        setStatus("Running command...", C.accent2)
        local ok = pcall(runBuiltinCommand, code)
        if not ok then
            record("[command error] command failed unexpectedly", "err")
            setStatus("Command error", C.err)
        elseif Status.Text == "Running command..." then
            setStatus("Command complete", C.ok)
        end
        return
    end

    setStatus("Running...", C.accent2)
    executeCode(code)
end

-- ============================================================
-- PRESETS
-- ============================================================
local PRESETS = {
    {
        name = "Remote Inventory",
        code = [[for _, v in ipairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
        print(v:GetFullName(), "[" .. v.ClassName .. "]")
    end
end]],
    },
    {
        name = "Egg Scan",
        code = [[for _, v in ipairs(game:GetDescendants()) do
    if v.Name:lower():find("egg", 1, true) then
        print(v:GetFullName(), "[" .. v.ClassName .. "]")
    end
end]],
    },
    {
        name = "ReplicatedStorage",
        code = [[for _, v in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
    print(v.Name, "[" .. v.ClassName .. "]")
end]],
    },
    {
        name = "Environment",
        code = [[print("PlaceId:", game.PlaceId)
print("GameId:", game.GameId)
print("JobId:", game.JobId)
print("LocalPlayer:", game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer.Name)]],
    },
    {
        name = "Print Test",
        code = [[print("hello from Charles's DevConsole")
warn("warn capture test")
return "return capture test"]],
    },
    {
        name = "Remote Observer",
        code = [[:spy]],
    },
}

-- ============================================================
-- PRESET / HISTORY MENUS
-- ============================================================
local PresetMenu = Instance.new("Frame")
PresetMenu.Name = "PresetMenu"
PresetMenu.Visible = false
PresetMenu.BackgroundColor3 = C.panel2
PresetMenu.BorderSizePixel = 0
PresetMenu.Size = UDim2.fromOffset(305, 245)
PresetMenu.ZIndex = 200
PresetMenu.Parent = Content
corner(PresetMenu, 8)
stroke(PresetMenu, C.border, 1)

local PresetScroll = Instance.new("ScrollingFrame")
PresetScroll.Size = UDim2.new(1, 0, 1, 0)
PresetScroll.BackgroundTransparency = 1
PresetScroll.BorderSizePixel = 0
PresetScroll.ScrollBarThickness = 3
PresetScroll.ScrollBarImageColor3 = C.panel3
PresetScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
PresetScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
PresetScroll.ScrollingDirection = Enum.ScrollingDirection.Y
PresetScroll.ZIndex = 201
PresetScroll.Parent = PresetMenu
padding(PresetScroll, 6, 6, 6, 6)

local PLayout = Instance.new("UIListLayout")
PLayout.Padding = UDim.new(0, 2)
PLayout.SortOrder = Enum.SortOrder.LayoutOrder
PLayout.Parent = PresetScroll

for i, preset in ipairs(PRESETS) do
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 31)
    item.BackgroundColor3 = C.panel3
    item.BackgroundTransparency = 1
    item.BorderSizePixel = 0
    item.Font = FONT
    item.TextSize = 12
    item.TextColor3 = C.text
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Text = "   " .. preset.name
    item.AutoButtonColor = false
    item.LayoutOrder = i
    item.ZIndex = 202
    item.Parent = PresetScroll
    corner(item, 6)

    item.MouseEnter:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), {
            BackgroundTransparency = 0,
        }):Play()
    end)
    item.MouseLeave:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), {
            BackgroundTransparency = 1,
        }):Play()
    end)
    item.MouseButton1Click:Connect(function()
        InputBox.Text = preset.code
        PresetMenu.Visible = false
        setStatus("Loaded preset: " .. preset.name, C.ok)
    end)
end

local HistoryMenu = Instance.new("Frame")
HistoryMenu.Name = "HistoryMenu"
HistoryMenu.Visible = false
HistoryMenu.BackgroundColor3 = C.panel2
HistoryMenu.BorderSizePixel = 0
HistoryMenu.Size = UDim2.fromOffset(430, 250)
HistoryMenu.ZIndex = 210
HistoryMenu.Parent = Content
corner(HistoryMenu, 8)
stroke(HistoryMenu, C.border, 1)

local HistoryScroll = Instance.new("ScrollingFrame")
HistoryScroll.Size = UDim2.new(1, 0, 1, 0)
HistoryScroll.BackgroundTransparency = 1
HistoryScroll.BorderSizePixel = 0
HistoryScroll.ScrollBarThickness = 3
HistoryScroll.ScrollBarImageColor3 = C.panel3
HistoryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
HistoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
HistoryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
HistoryScroll.ZIndex = 211
HistoryScroll.Parent = HistoryMenu
padding(HistoryScroll, 6, 6, 6, 6)

local HLayout = Instance.new("UIListLayout")
HLayout.Padding = UDim.new(0, 2)
HLayout.SortOrder = Enum.SortOrder.LayoutOrder
HLayout.Parent = HistoryScroll

local function refreshHistoryMenu()
    for _, child in ipairs(HistoryScroll:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    if #CommandHistory == 0 then
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 0, 34)
        label.Font = FONT_MONO
        label.TextSize = 12
        label.TextColor3 = C.dim
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = "   <history empty>"
        label.ZIndex = 212
        label.Parent = HistoryScroll
        return
    end

    for i = #CommandHistory, 1, -1 do
        local index = i
        local text = CommandHistory[i]
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, 34)
        item.BackgroundColor3 = C.panel3
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Font = FONT_MONO
        item.TextSize = 11
        item.TextColor3 = C.text
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.TextWrapped = true
        item.Text = string.format("   %03d  %s", index, text:gsub("\n", "\\n"))
        item.AutoButtonColor = false
        item.LayoutOrder = #CommandHistory - i + 1
        item.ZIndex = 212
        item.Parent = HistoryScroll
        corner(item, 6)

        item.MouseEnter:Connect(function()
            item.BackgroundTransparency = 0
        end)
        item.MouseLeave:Connect(function()
            item.BackgroundTransparency = 1
        end)
        item.MouseButton1Click:Connect(function()
            InputBox.Text = text
            HistoryMenu.Visible = false
            setStatus("Loaded history #" .. index, C.ok)
        end)
    end
end

PresetBtn.MouseButton1Click:Connect(function()
    HistoryMenu.Visible = false
    PresetMenu.Visible = not PresetMenu.Visible
end)

HistoryBtn.MouseButton1Click:Connect(function()
    PresetMenu.Visible = false
    refreshHistoryMenu()
    HistoryMenu.Visible = not HistoryMenu.Visible
end)

-- ============================================================
-- BUTTONS
-- ============================================================
RunBtn.MouseButton1Click:Connect(runCode)
CopyLogBtn.MouseButton1Click:Connect(function()
    if #Buffer == 0 then
        setStatus("Log is empty", C.warn)
        return
    end
    if copyToClipboard(table.concat(Buffer, "\n")) then
        setStatus("Copied " .. #Buffer .. " lines", C.ok)
    else
        setStatus("Clipboard unavailable", C.err)
    end
end)

CopyInBtn.MouseButton1Click:Connect(function()
    if trim(InputBox.Text) == "" then
        setStatus("Input is empty", C.warn)
        return
    end
    if copyToClipboard(InputBox.Text) then
        setStatus("Input copied", C.ok)
    else
        setStatus("Clipboard unavailable", C.err)
    end
end)

ClearBtn.MouseButton1Click:Connect(function()
    clearLog()
end)

-- ============================================================
-- OUTSIDE MENU CLICK
-- ============================================================
UIS.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
       and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local pos = input.Position

    local function inside(gui)
        local a = gui.AbsolutePosition
        local s = gui.AbsoluteSize
        return pos.X >= a.X and pos.X <= a.X + s.X
            and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
    end

    if PresetMenu.Visible and not inside(PresetMenu) and not inside(PresetBtn) then
        PresetMenu.Visible = false
    end
    if HistoryMenu.Visible and not inside(HistoryMenu) and not inside(HistoryBtn) then
        HistoryMenu.Visible = false
    end
end)

-- ============================================================
-- DRAG + RESIZE
-- ============================================================
local dragging = false
local dragStart = nil
local startPos = nil
local resizing = false
local resizeStart = nil
local resizeStartSize = nil

local function beginDrag(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end

local function beginResize(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        resizing = true
        resizeStart = input.Position
        resizeStartSize = Main.AbsoluteSize
    end
end

DragArea.InputBegan:Connect(beginDrag)
TitleBar.InputBegan:Connect(beginDrag)
Title.InputBegan:Connect(beginDrag)
Subtitle.InputBegan:Connect(beginDrag)
ResizeHandle.InputBegan:Connect(beginResize)

local function isPointerMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

UIS.InputChanged:Connect(function(input)
    if not isPointerMove(input) then return end

    if dragging and dragStart and startPos then
        local delta = input.Position - dragStart
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local size = Main.AbsoluteSize
        local x = math.clamp(startPos.X.Offset + delta.X, 8, viewport.X - size.X - 8)
        local y = math.clamp(startPos.Y.Offset + delta.Y, 8, viewport.Y - size.Y - 8)
        Main.Position = UDim2.fromOffset(x, y)
    elseif resizing and resizeStart and resizeStartSize then
        local delta = input.Position - resizeStart
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local minW, minH = 480, 320
        local maxW = math.max(minW, viewport.X - 16)
        local maxH = math.max(minH, viewport.Y - 16)
        local newW = math.clamp(resizeStartSize.X + delta.X, minW, maxW)
        local newH = math.clamp(resizeStartSize.Y + delta.Y, minH, maxH)
        Main.Size = UDim2.fromOffset(newW, newH)

        -- Keep the window onscreen after a resize.
        local pos = Main.AbsolutePosition
        local x = math.clamp(pos.X, 8, viewport.X - newW - 8)
        local y = math.clamp(pos.Y, 8, viewport.Y - newH - 8)
        Main.Position = UDim2.fromOffset(x, y)
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        resizing = false
        dragStart = nil
        startPos = nil
        resizeStart = nil
        resizeStartSize = nil
    end
end)

-- ============================================================
-- DYNAMIC LAYOUT
-- ============================================================
local function applyLayout()
    local w = Main.AbsoluteSize.X
    local h = Main.AbsoluteSize.Y
    local contentW = math.max(100, w - 24)
    local contentH = math.max(100, h - 62)

    Content.Size = UDim2.new(1, -24, 1, -62)

    local inputH = math.clamp(math.floor(contentH * 0.25), 100, 170)
    local labelH = 16
    local gap = 8

    InputLabel.Position = UDim2.fromOffset(2, 0)
    InputLabel.Size = UDim2.fromOffset(math.max(50, contentW - 4), labelH)

    InputBox.Position = UDim2.fromOffset(0, 19)
    InputBox.Size = UDim2.new(1, 0, 0, inputH)

    local outputLabelY = 19 + inputH + gap
    OutputLabel.Position = UDim2.fromOffset(2, outputLabelY)
    OutputLabel.Size = UDim2.fromOffset(math.max(50, contentW - 4), labelH)

    local bottomArea = 56
    local outputY = outputLabelY + 18
    local outputH = math.max(100, contentH - outputY - bottomArea)

    OutputScroll.Position = UDim2.fromOffset(0, outputY)
    OutputScroll.Size = UDim2.new(1, 0, 0, outputH)

    ButtonRow.Position = UDim2.new(0, 0, 1, -34)
    ButtonRow.Size = UDim2.new(1, 0, 0, 34)

    Status.Position = UDim2.new(0, 2, 1, -56)
    Status.Size = UDim2.new(1, -4, 0, 18)

    DragArea.Position = UDim2.fromOffset(0, 0)
    DragArea.Size = UDim2.new(1, -88, 1, 0)
    ResizeHandle.Position = UDim2.new(1, -34, 1, -34)
    ResizeHandle.Size = UDim2.fromOffset(34, 34)

    -- Keep popup menus above the lower controls and inside the window.
    local menuY = math.max(40, contentH - 250 - 44)
    PresetMenu.Position = UDim2.fromOffset(78, menuY)
    HistoryMenu.Position = UDim2.fromOffset(158, menuY)
end

Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

-- Start at a compact, viewport-aware size rather than assuming a desktop display.
do task.defer(function()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local w = math.min(620, math.max(480, viewport.X - 24))
    local h = math.min(430, math.max(320, viewport.Y - 24))
    Main.Size = UDim2.fromOffset(w, h)
    Main.Position = UDim2.fromOffset(
        math.max(8, (viewport.X - w) / 2),
        math.max(8, (viewport.Y - h) / 2)
    )
    applyLayout()
end)
applyLayout()

-- ============================================================
-- INPUT / HOTKEYS
-- ============================================================
InputBox.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Return and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
        runCode()
    elseif input.KeyCode == Enum.KeyCode.Up and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
        if #CommandHistory > 0 then
            HistoryIndex = math.clamp(HistoryIndex - 1, 1, #CommandHistory)
            InputBox.Text = CommandHistory[HistoryIndex]
            task.defer(function()
                pcall(function() InputBox.CursorPosition = #InputBox.Text + 1 end)
            end)
        end
    elseif input.KeyCode == Enum.KeyCode.Down and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
        if #CommandHistory > 0 then
            HistoryIndex = math.clamp(HistoryIndex + 1, 1, #CommandHistory + 1)
            if HistoryIndex <= #CommandHistory then
                InputBox.Text = CommandHistory[HistoryIndex]
            else
                InputBox.Text = ""
            end
        end
    end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then
        return
    end

    if input.KeyCode == Enum.KeyCode.F2 then
        Main.Visible = not Main.Visible
    elseif input.KeyCode == Enum.KeyCode.F4 then
        runCode()
    end
end)

-- ============================================================
-- MINIMIZE / RESTORE / CLOSE
-- ============================================================
local RestoreBtn = Instance.new("TextButton")
RestoreBtn.Name = "RestoreBtn"
RestoreBtn.Size = UDim2.fromOffset(58, 58)
RestoreBtn.Position = UDim2.new(0, 18, 0.5, -29)
RestoreBtn.BackgroundColor3 = C.accent
RestoreBtn.BorderSizePixel = 0
RestoreBtn.Font = FONT_BOLD
RestoreBtn.TextSize = 13
RestoreBtn.TextColor3 = Color3.new(1, 1, 1)
RestoreBtn.Text = "CD"
RestoreBtn.Visible = false
RestoreBtn.AutoButtonColor = false
RestoreBtn.Parent = ScreenGui
corner(RestoreBtn, 29)
stroke(RestoreBtn, C.border, 1)

RestoreBtn.MouseEnter:Connect(function()
    TweenService:Create(RestoreBtn, TweenInfo.new(0.12), {
        BackgroundColor3 = C.accent2,
    }):Play()
end)
RestoreBtn.MouseLeave:Connect(function()
    TweenService:Create(RestoreBtn, TweenInfo.new(0.12), {
        BackgroundColor3 = C.accent,
    }):Play()
end)

MinBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    RestoreBtn.Visible = true
end)

RestoreBtn.MouseButton1Click:Connect(function()
    Main.Visible = true
    RestoreBtn.Visible = false
end)

CloseBtn.MouseButton1Click:Connect(function()
    pcall(uninstallRemoteSpy)
    ScreenGui:Destroy()
end)

-- ============================================================
-- INIT
-- ============================================================
record("Charles's DevConsole ready.", "ok")
record("Use :help to see commands.", "dim")
record("Print capture test: press Run with :help or use the Print Test preset.", "dim")
setStatus("Ready", C.dim)
