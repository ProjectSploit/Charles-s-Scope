--[[
    DevConsole — a self-contained script console for Roblox executors.
    - Multi-line Lua input
    - Captures print / warn / errors / returned values
    - Copy output to clipboard
    - Preset recon snippets (remote dumps, egg scans, anti-cheat sweeps)
    Paste into Delta (or any executor) and execute. No external dependencies.
]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")

local LP = Players.LocalPlayer

-- ============================================================
-- THEME
-- ============================================================
local C = {
    bg      = Color3.fromRGB(18, 18, 22),
    panel   = Color3.fromRGB(26, 26, 32),
    panel2  = Color3.fromRGB(36, 36, 44),
    panel3  = Color3.fromRGB(50, 50, 62),
    accent  = Color3.fromRGB(88, 132, 255),
    accent2 = Color3.fromRGB(130, 168, 255),
    text    = Color3.fromRGB(226, 226, 236),
    dim     = Color3.fromRGB(138, 138, 152),
    err     = Color3.fromRGB(255, 105, 105),
    warn    = Color3.fromRGB(255, 190, 95),
    ok      = Color3.fromRGB(120, 220, 145),
    border  = Color3.fromRGB(48, 48, 58),
}

local FONT      = Enum.Font.GothamMedium
local FONT_MONO = Enum.Font.Code

-- ============================================================
-- HELPERS
-- ============================================================
local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
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

local function padding(parent, t, r, b, l)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, t or 0)
    p.PaddingRight  = UDim.new(0, r or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.Parent = parent
    return p
end

local function copyToClipboard(text)
    return (pcall(function()
        if setclipboard then setclipboard(text) return end
        if toclipboard then toclipboard(text) return end
        if setrbxclipboard then setrbxclipboard(text) return end
        error("no clipboard function available")
    end))
end

local function resolveParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, cg = pcall(function() return CoreGui end)
    if ok and cg then return cg end
    return LP:WaitForChild("PlayerGui")
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ============================================================
-- BUILD GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DevConsole_" .. tostring(math.random(100000, 999999))
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 9999

do
    local p = resolveParent()
    local ok = pcall(function() ScreenGui.Parent = p end)
    if not ok or not ScreenGui.Parent then
        ScreenGui.Parent = LP:WaitForChild("PlayerGui")
    end
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 600, 0, 460)
Main.Position = UDim2.new(0.5, -300, 0.5, -230)
Main.BackgroundColor3 = C.bg
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui
corner(Main, 12)
stroke(Main, C.border, 1)

-- ---------- Title bar ----------
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3 = C.panel
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main

local AccentBar = Instance.new("Frame")
AccentBar.Size = UDim2.new(0, 3, 0, 16)
AccentBar.Position = UDim2.new(0, 12, 0.5, -8)
AccentBar.BackgroundColor3 = C.accent
AccentBar.BorderSizePixel = 0
AccentBar.Parent = TitleBar
corner(AccentBar, 2)

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 22, 0, 0)
Title.Size = UDim2.new(1, -110, 1, 0)
Title.Font = FONT
Title.TextSize = 14
Title.TextColor3 = C.text
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "DevConsole"
Title.Parent = TitleBar

local function titleButton(text, xOffset, hoverColor)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 30, 0, 30)
    b.Position = UDim2.new(1, xOffset, 0.5, -15)
    b.BackgroundColor3 = C.panel
    b.BorderSizePixel = 0
    b.Font = FONT
    b.TextSize = 15
    b.TextColor3 = C.dim
    b.Text = text
    b.AutoButtonColor = false
    b.Parent = TitleBar
    corner(b, 6)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12),
            {BackgroundColor3 = hoverColor or C.panel2, TextColor3 = C.text}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12),
            {BackgroundColor3 = C.panel, TextColor3 = C.dim}):Play()
    end)
    return b
end

local CloseBtn = titleButton("✕", -40, Color3.fromRGB(200, 60, 60))
local MinBtn   = titleButton("—", -74)

-- ---------- Content root ----------
local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Position = UDim2.new(0, 12, 0, 46)
Content.Size = UDim2.new(1, -24, 1, -58)
Content.BackgroundTransparency = 1
Content.Parent = Main

local function sectionLabel(text, y)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 2, 0, y)
    l.Size = UDim2.new(1, 0, 0, 16)
    l.Font = FONT
    l.TextSize = 12
    l.TextColor3 = C.dim
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = Content
    return l
end

sectionLabel("INPUT", 0)
sectionLabel("OUTPUT", 138)

-- ---------- Input box ----------
local InputBox = Instance.new("TextBox")
InputBox.Name = "Input"
InputBox.Position = UDim2.new(0, 0, 0, 20)
InputBox.Size = UDim2.new(1, 0, 0, 108)
InputBox.BackgroundColor3 = C.panel
InputBox.BorderSizePixel = 0
InputBox.Font = FONT_MONO
InputBox.TextSize = 13
InputBox.TextColor3 = C.text
InputBox.PlaceholderColor3 = C.dim
InputBox.PlaceholderText = "-- paste Lua here, then press Run (or load a preset)"
InputBox.Text = ""
InputBox.MultiLine = true
InputBox.TextWrapped = true
InputBox.TextXAlignment = Enum.TextXAlignment.Left
InputBox.TextYAlignment = Enum.TextYAlignment.Top
InputBox.ClearTextOnFocus = false
InputBox.Parent = Content
corner(InputBox, 8)
stroke(InputBox, C.border, 1)
padding(InputBox, 8, 10, 8, 10)

-- ---------- Output scroll ----------
local OutputScroll = Instance.new("ScrollingFrame")
OutputScroll.Name = "Output"
OutputScroll.Position = UDim2.new(0, 0, 0, 158)
OutputScroll.Size = UDim2.new(1, 0, 0, 176)
OutputScroll.BackgroundColor3 = C.panel
OutputScroll.BorderSizePixel = 0
OutputScroll.ScrollBarThickness = 4
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

-- ---------- Status line ----------
local Status = Instance.new("TextLabel")
Status.Name = "Status"
Status.BackgroundTransparency = 1
Status.Position = UDim2.new(0, 2, 0, 384)
Status.Size = UDim2.new(1, 0, 0, 18)
Status.Font = FONT
Status.TextSize = 12
Status.TextColor3 = C.dim
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "Ready"
Status.Parent = Content

local function setStatus(text, color)
    Status.Text = text
    Status.TextColor3 = color or C.dim
end

-- ---------- Button row ----------
local ButtonRow = Instance.new("Frame")
ButtonRow.Position = UDim2.new(0, 0, 0, 344)
ButtonRow.Size = UDim2.new(1, 0, 0, 34)
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
    b.Size = UDim2.new(0, width, 0, 32)
    b.BackgroundColor3 = base
    b.BorderSizePixel = 0
    b.Font = FONT
    b.TextSize = 13
    b.TextColor3 = textColor or C.text
    b.Text = text
    b.AutoButtonColor = false
    b.Parent = ButtonRow
    corner(b, 7)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12),
            {BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12)}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = base}):Play()
    end)
    return b
end

local RunBtn      = makeButton("Run",         70, C.accent, Color3.new(1, 1, 1))
local PresetBtn   = makeButton("Presets",     84)
local CopyLogBtn  = makeButton("Copy Log",    88)
local CopyInBtn   = makeButton("Copy Input",  92)
local ClearLogBtn = makeButton("Clear Log",   88)
local ClearInBtn  = makeButton("Clear Input", 92)

-- ============================================================
-- LOG BUFFER + RENDERING
-- ============================================================
local Buffer = {}
local LineLabels = {}
local MAX_LINES = 1500

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
    line.Text = text
    line.Parent = OutputScroll

    table.insert(LineLabels, line)

    while #Buffer > MAX_LINES do
        table.remove(Buffer, 1)
        local old = table.remove(LineLabels, 1)
        if old then old:Destroy() end
    end

    scrollToBottom()
end

local function record(text, kind)
    table.insert(Buffer, text)
    addLine(text, kind)
end

-- ============================================================
-- HOOK print / warn  →  route into console
-- ============================================================
local realPrint = print
local realWarn  = warn

local function joinArgs(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end

local function installOutputHooks()
    local okPrint = pcall(function()
        print = function(...)
            local line = joinArgs(...)
            record(line, "out")
            realPrint("[DC] " .. line)
        end
    end)
    local okWarn = pcall(function()
        warn = function(...)
            local line = joinArgs(...)
            record(line, "warn")
            realWarn("[DC] " .. line)
        end
    end)
    return okPrint, okWarn
end

-- ============================================================
-- EXECUTION
-- ============================================================
local function runCode()
    local code = InputBox.Text
    if trim(code) == "" then
        setStatus("Nothing to run", C.warn)
        return
    end

    setStatus("Running...", C.accent2)
    record("", "dim")

    for line in (code .. "\n"):gmatch("([^\n]*)\n") do
        record("> " .. line, "in")
    end

    local loader = loadstring or load
    if not loader then
        record("[error] no loadstring/load available in this executor", "err")
        setStatus("No loader", C.err)
        return
    end

    local t0 = os.clock()
    local chunk, compileErr = loader(code, "=DevConsole")
    if not chunk then
        record("[compile error] " .. tostring(compileErr), "err")
        setStatus("Compile error", C.err)
        return
    end

    local ok, result = pcall(chunk)
    local dt = (os.clock() - t0) * 1000

    if not ok then
        record("[runtime error] " .. tostring(result), "err")
        setStatus(string.format("Error (%.1f ms)", dt), C.err)
    else
        if result ~= nil then
            record("[returned] " .. tostring(result), "ok")
        end
        record(string.format("[done in %.1f ms]", dt), "dim")
        setStatus(string.format("Done in %.1f ms", dt), C.ok)
    end
end

-- ============================================================
-- BUTTON WIRING
-- ============================================================
RunBtn.MouseButton1Click:Connect(runCode)

CopyLogBtn.MouseButton1Click:Connect(function()
    if #Buffer == 0 then
        setStatus("Log is empty", C.warn)
        return
    end
    local text = table.concat(Buffer, "\n")
    if copyToClipboard(text) then
        setStatus(string.format("Copied %d lines to clipboard", #Buffer), C.ok)
    else
        setStatus("Clipboard unavailable", C.err)
    end
end)

CopyInBtn.MouseButton1Click:Connect(function()
    if InputBox.Text == "" then
        setStatus("Input is empty", C.warn)
        return
    end
    if copyToClipboard(InputBox.Text) then
        setStatus("Input copied to clipboard", C.ok)
    else
        setStatus("Clipboard unavailable", C.err)
    end
end)

ClearLogBtn.MouseButton1Click:Connect(function()
    Buffer = {}
    for _, lbl in ipairs(LineLabels) do
        lbl:Destroy()
    end
    LineLabels = {}
    setStatus("Log cleared", C.dim)
end)

ClearInBtn.MouseButton1Click:Connect(function()
    InputBox.Text = ""
    setStatus("Input cleared", C.dim)
end)

-- ============================================================
-- PRESETS
-- ============================================================
local PRESETS = {
    {
        name = "Dump Remotes",
        code = [[-- Dump all RemoteEvents and RemoteFunctions
for _, v in ipairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
        print(v:GetFullName(), "[" .. v.ClassName .. "]")
    end
end]],
    },
    {
        name = "Dump Egg Instances",
        code = [[-- Dump anything with 'egg' in the name
for _, v in ipairs(game:GetDescendants()) do
    if v.Name:lower():find("egg") then
        print(v:GetFullName(), "[" .. v.ClassName .. "]")
    end
end]],
    },
    {
        name = "PlaceId + Anti-Cheat Sweep",
        code = [[print("PlaceId:", game.PlaceId)
print("JobId:", game.JobId)
print("--- suspicious scripts ---")
for _, v in ipairs(game:GetDescendants()) do
    if v:IsA("Script") or v:IsA("LocalScript") then
        local n = v.Name:lower()
        if n:find("anti") or n:find("check") or n:find("guard") or n:find("detect") then
            print(v:GetFullName(), "[" .. v.ClassName .. "]")
        end
    end
end]],
    },
    {
        name = "List Players",
        code = [[for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    print(p.Name, "|", p.DisplayName, "| UserId=" .. p.UserId)
end]],
    },
    {
        name = "List Workspace Children",
        code = [[for _, v in ipairs(workspace:GetChildren()) do
    print(v.Name, "[" .. v.ClassName .. "]")
end]],
    },
    {
        name = "List ReplicatedStorage",
        code = [[for _, v in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
    print(v.Name, "[" .. v.ClassName .. "]")
end]],
    },
    {
        name = "Spy: Log Remote Fires",
        code = [[-- Requires hookfunction + getrawmetatable (most executors have them)
local ok, err = pcall(function()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            print("[remote]", method, self:GetFullName(), ...)
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end)
if ok then print("Remote spy installed") else print("Remote spy failed:", err) end]],
    },
}

local PresetMenu = Instance.new("Frame")
PresetMenu.Name = "PresetMenu"
PresetMenu.Visible = false
PresetMenu.BackgroundColor3 = C.panel2
PresetMenu.BorderSizePixel = 0
PresetMenu.Size = UDim2.new(0, 280, 0, 220)
PresetMenu.Position = UDim2.new(0, 76, 0, 118)
PresetMenu.ZIndex = 50
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
PresetScroll.ZIndex = 51
PresetScroll.Parent = PresetMenu
padding(PresetScroll, 6, 6, 6, 6)

local PLayout = Instance.new("UIListLayout")
PLayout.Padding = UDim.new(0, 2)
PLayout.SortOrder = Enum.SortOrder.LayoutOrder
PLayout.Parent = PresetScroll

for i, preset in ipairs(PRESETS) do
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 30)
    item.BackgroundColor3 = C.panel3
    item.BackgroundTransparency = 1
    item.BorderSizePixel = 0
    item.Font = FONT
    item.TextSize = 13
    item.TextColor3 = C.text
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Text = "   " .. preset.name
    item.AutoButtonColor = false
    item.LayoutOrder = i
    item.ZIndex = 52
    item.Parent = PresetScroll
    corner(item, 6)

    item.MouseEnter:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1),
            {BackgroundTransparency = 0}):Play()
    end)
    item.MouseLeave:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1),
            {BackgroundTransparency = 1}):Play()
    end)
    item.MouseButton1Click:Connect(function()
        InputBox.Text = preset.code
        PresetMenu.Visible = false
        setStatus("Loaded preset: " .. preset.name, C.ok)
    end)
end

PresetBtn.MouseButton1Click:Connect(function()
    PresetMenu.Visible = not PresetMenu.Visible
    if PresetMenu.Visible then PresetMenu.ZIndex = 50 end
end)

-- close preset menu on outside click
UIS.InputBegan:Connect(function(input)
    if not PresetMenu.Visible then return end
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
    if not inside(PresetMenu) and not inside(PresetBtn) then
        PresetMenu.Visible = false
    end
end)

-- ============================================================
-- DRAG
-- ============================================================
local dragging, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
       and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPos.X.Scale, startPos.X.Offset + delta.X,
        startPos.Y.Scale, startPos.Y.Offset + delta.Y
    )
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ============================================================
-- MINIMIZE / CLOSE
-- ============================================================
local RestoreBtn = Instance.new("TextButton")
RestoreBtn.Name = "RestoreBtn"
RestoreBtn.Size = UDim2.new(0, 52, 0, 52)
RestoreBtn.Position = UDim2.new(0, 24, 0.5, -26)
RestoreBtn.BackgroundColor3 = C.accent
RestoreBtn.BorderSizePixel = 0
RestoreBtn.Font = FONT
RestoreBtn.TextSize = 14
RestoreBtn.TextColor3 = Color3.new(1, 1, 1)
RestoreBtn.Text = "DC"
RestoreBtn.Visible = false
RestoreBtn.AutoButtonColor = false
RestoreBtn.Parent = ScreenGui
corner(RestoreBtn, 26)
stroke(RestoreBtn, C.border, 1)

RestoreBtn.MouseEnter:Connect(function()
    TweenService:Create(RestoreBtn, TweenInfo.new(0.12),
        {BackgroundColor3 = C.accent2}):Play()
end)
RestoreBtn.MouseLeave:Connect(function()
    TweenService:Create(RestoreBtn, TweenInfo.new(0.12),
        {BackgroundColor3 = C.accent}):Play()
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
    ScreenGui:Destroy()
end)

-- ============================================================
-- KEYBIND: F2 toggles visibility
-- ============================================================
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F2 then
        if Main.Visible then
            Main.Visible = false
            RestoreBtn.Visible = true
        else
            Main.Visible = true
            RestoreBtn.Visible = false
        end
    end
end)

-- ============================================================
-- INIT
-- ============================================================
local okPrint, okWarn = installOutputHooks()

record("DevConsole ready.", "ok")
if not okPrint then
    record("[warn] global print could not be hooked — user output may not appear here", "warn")
end
if not okWarn then
    record("[warn] global warn could not be hooked", "warn")
end
record("Paste Lua above and press Run.  Presets has ready-made recon snippets.", "dim")
record("F2 toggles the window.  Copy Log grabs everything for pasting back here.", "dim")
setStatus("Ready", C.dim)