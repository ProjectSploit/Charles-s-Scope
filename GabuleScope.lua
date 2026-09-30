--[[
    Gabule DevConsole
    =================

    A self-contained script console for Roblox executors.

    - Multi-line Lua input with synchronized syntax-highlight overlay
    - Captures print / warn / errors / returned values
    - Copy output to clipboard
    - Preset recon snippets (remote dumps, egg scans, anti-cheat sweeps)
    - Optional background image (see BACKGROUND_ASSET below)

    Built on the known-good cmd.lua baseline: same startup sequence,
    same parenting path (gethui -> CoreGui -> PlayerGui), same fixed
    600x460 default window, same execution and output pipeline.

    Editor architecture:
      InputFrame (chrome)
        EditorScroll (ScrollingFrame)
          HighlightOverlay (TextLabel, RichText)
          InputBox (TextBox, plain text, source of truth)

    Both editor layers share one ScrollingFrame and are given the same
    explicit height, so they never scroll apart. The overlay is a
    passive visual layer; InputBox.Text is never mutated with markup.
    The overlay is shown only while the editor is unfocused.
]]

-- ============================================================
-- BACKGROUND IMAGE CONFIG
-- ============================================================
-- Set this to your uploaded Roblox asset ID, e.g. "rbxassetid://1234567890".
-- Leave as "" to keep the plain dark background.
-- If your executor supports getcustomasset(), you can also do:
--   BACKGROUND_ASSET = getcustomasset("Screenshot_2026-09-30-23-28-10-673_com.miui.gallery-edit.jpg")
local BACKGROUND_ASSET = ""

-- ============================================================
-- RE-EXECUTION GUARD
-- ============================================================
local CLEANUP_KEY = "_GabuleDevConsole_Cleanup"
do
    local prevCleanup = _G[CLEANUP_KEY]
    _G[CLEANUP_KEY] = nil
    if type(prevCleanup) == "function" then
        pcall(prevCleanup)
    end
end

-- ============================================================
-- SERVICES
-- ============================================================
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService  = game:GetService("TextService")
local CoreGui      = game:GetService("CoreGui")

local LP = Players.LocalPlayer

-- ============================================================
-- CONSTANTS
-- ============================================================
local MIN_W = 380
local MIN_H = 320
local LINE_HEIGHT_PX = 16      -- approximate monospace line height at TextSize 13
local LARGE_TEXT_LIMIT = 30000 -- skip tokenization above this many chars

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

local trackedConnections = {}
local function trackConnection(conn)
    trackedConnections[#trackedConnections + 1] = conn
    return conn
end

-- Forward declaration: close button needs to call into cleanup, but
-- cleanup is defined at the very end of the file. Assign later.
local closeConsole = nil

-- ============================================================
-- BUILD GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GabuleDevConsole_" .. tostring(math.random(100000, 999999))
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

-- ---------- Background image (behind everything) ----------
do
    local hasBg = type(BACKGROUND_ASSET) == "string"
        and BACKGROUND_ASSET ~= ""
        and BACKGROUND_ASSET ~= "rbxassetid://0"
    if hasBg then
        local bg = Instance.new("ImageLabel")
        bg.Name = "BackgroundImage"
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.Position = UDim2.new(0, 0, 0, 0)
        bg.BackgroundTransparency = 1
        bg.Image = BACKGROUND_ASSET
        bg.ScaleType = Enum.ScaleType.Crop
        bg.ZIndex = 0
        bg.Parent = Main
        corner(bg, 12)

        -- Dim layer so title bar / editor / output stay readable
        local dim = Instance.new("Frame")
        dim.Name = "BackgroundDim"
        dim.Size = UDim2.new(1, 0, 1, 0)
        dim.Position = UDim2.new(0, 0, 0, 0)
        dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        dim.BackgroundTransparency = 0.45
        dim.BorderSizePixel = 0
        dim.ZIndex = 0
        dim.Parent = Main
        corner(dim, 12)
    end
end

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
Title.Text = "Gabule's DevConsole"
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

local MinBtn = titleButton("—", -74)

-- Close button: first click arms, second click within 3s closes.
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -15)
CloseBtn.BackgroundColor3 = C.panel
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = FONT
CloseBtn.TextSize = 15
CloseBtn.TextColor3 = C.dim
CloseBtn.Text = "✕"
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = TitleBar
corner(CloseBtn, 6)

local closeConfirming = false
local closeToken = 0

local function closeHover(on)
    if closeConfirming then return end
    TweenService:Create(CloseBtn, TweenInfo.new(0.12), {
        BackgroundColor3 = on and Color3.fromRGB(200, 60, 60) or C.panel,
        TextColor3 = on and C.text or C.dim,
    }):Play()
end

CloseBtn.MouseEnter:Connect(function() closeHover(true) end)
CloseBtn.MouseLeave:Connect(function() closeHover(false) end)

CloseBtn.MouseButton1Click:Connect(function()
    if closeConfirming then
        if closeConsole then closeConsole() else ScreenGui:Destroy() end
        return
    end
    closeConfirming = true
    closeToken = closeToken + 1
    local my = closeToken
    CloseBtn.Text = "?"
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        TextColor3 = Color3.new(1, 1, 1),
    }):Play()
    task.delay(3, function()
        if closeToken ~= my then return end
        closeConfirming = false
        pcall(function()
            CloseBtn.Text = "✕"
            TweenService:Create(CloseBtn, TweenInfo.new(0.2), {
                BackgroundColor3 = C.panel,
                TextColor3 = C.dim,
            }):Play()
        end)
    end)
end)

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

local InputLabel  = sectionLabel("INPUT", 0)
local OutputLabel = sectionLabel("OUTPUT", 138)

-- ---------- Editor ----------
local InputFrame = Instance.new("Frame")
InputFrame.Name = "InputFrame"
InputFrame.Position = UDim2.new(0, 0, 0, 20)
InputFrame.Size = UDim2.new(1, 0, 0, 108)
InputFrame.BackgroundColor3 = C.panel
InputFrame.BorderSizePixel = 0
InputFrame.ClipsDescendants = true
InputFrame.Parent = Content
corner(InputFrame, 8)
stroke(InputFrame, C.border, 1)
padding(InputFrame, 8, 10, 8, 10)

local EditorScroll = Instance.new("ScrollingFrame")
EditorScroll.Name = "EditorScroll"
EditorScroll.BackgroundTransparency = 1
EditorScroll.BorderSizePixel = 0
EditorScroll.Position = UDim2.new(0, 0, 0, 0)
EditorScroll.Size = UDim2.new(1, 0, 1, 0)
EditorScroll.CanvasSize = UDim2.new(1, 0, 0, 0)
EditorScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
EditorScroll.ScrollingDirection = Enum.ScrollingDirection.Y
EditorScroll.ScrollBarThickness = 4
EditorScroll.ScrollBarImageColor3 = C.panel3
EditorScroll.Active = true
EditorScroll.ClipsDescendants = true
EditorScroll.Parent = InputFrame

local HighlightOverlay = Instance.new("TextLabel")
HighlightOverlay.Name = "HighlightOverlay"
HighlightOverlay.BackgroundTransparency = 1
HighlightOverlay.RichText = true
HighlightOverlay.Font = FONT_MONO
HighlightOverlay.TextSize = 13
HighlightOverlay.TextColor3 = C.text
HighlightOverlay.TextXAlignment = Enum.TextXAlignment.Left
HighlightOverlay.TextYAlignment = Enum.TextYAlignment.Top
HighlightOverlay.TextWrapped = true
HighlightOverlay.Position = UDim2.new(0, 0, 0, 0)
HighlightOverlay.Size = UDim2.new(1, 0, 0, 100)
HighlightOverlay.Text = ""
HighlightOverlay.Visible = false
HighlightOverlay.ZIndex = 1
HighlightOverlay.Parent = EditorScroll

local InputBox = Instance.new("TextBox")
InputBox.Name = "Input"
InputBox.BackgroundTransparency = 1
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
InputBox.Position = UDim2.new(0, 0, 0, 0)
InputBox.Size = UDim2.new(1, 0, 0, 100)
InputBox.ZIndex = 2
InputBox.Parent = EditorScroll

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
Status.Size = UDim2.new(1, -34, 0, 18)
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

-- ---------- Resize handle ----------
local ResizeHandle = Instance.new("TextButton")
ResizeHandle.Name = "ResizeHandle"
ResizeHandle.Size = UDim2.new(0, 32, 0, 32)
ResizeHandle.Position = UDim2.new(1, -36, 1, -36)
ResizeHandle.BackgroundTransparency = 1
ResizeHandle.BorderSizePixel = 0
ResizeHandle.Font = FONT_MONO
ResizeHandle.TextSize = 18
ResizeHandle.TextColor3 = C.dim
ResizeHandle.Text = "◢"
ResizeHandle.AutoButtonColor = false
ResizeHandle.Parent = Main

ResizeHandle.MouseEnter:Connect(function()
    TweenService:Create(ResizeHandle, TweenInfo.new(0.1), {TextColor3 = C.accent2}):Play()
end)
ResizeHandle.MouseLeave:Connect(function()
    TweenService:Create(ResizeHandle, TweenInfo.new(0.1), {TextColor3 = C.dim}):Play()
end)

-- ============================================================
-- VIEWPORT HELPER
-- ============================================================
local function getViewportSize()
    local ok, sz = pcall(function() return ScreenGui.AbsoluteSize end)
    if ok and sz and sz.X >= 40 and sz.Y >= 40 then
        return sz
    end
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X >= 40 then
        return cam.ViewportSize
    end
    return Vector2.new(1280, 720)
end

-- ============================================================
-- SYNTAX HIGHLIGHTER
-- ============================================================
local HL = {
    comment  = "6A9955",
    string   = "CE9178",
    number   = "B5CEA8",
    keyword  = "C586C0",
    literal  = "569CD6",
    builtin  = "4FC1FF",
    roblox   = "4EC9B0",
    call     = "DCDCAA",
    default  = "D4D4D4",
}

local KEYWORDS = {
    ["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,
    ["end"]=true,["for"]=true,["function"]=true,["if"]=true,["in"]=true,
    ["local"]=true,["not"]=true,["or"]=true,["repeat"]=true,["return"]=true,
    ["then"]=true,["until"]=true,["while"]=true,
}
local LITERALS = { ["true"]=true, ["false"]=true, ["nil"]=true }
local BUILTINS = {
    ["print"]=true,["warn"]=true,["error"]=true,["assert"]=true,["pcall"]=true,
    ["xpcall"]=true,["type"]=true,["typeof"]=true,["tostring"]=true,["tonumber"]=true,
    ["pairs"]=true,["ipairs"]=true,["next"]=true,["select"]=true,["rawget"]=true,
    ["rawset"]=true,["rawequal"]=true,["rawlen"]=true,["setmetatable"]=true,
    ["getmetatable"]=true,["unpack"]=true,["require"]=true,
    ["table"]=true,["string"]=true,["math"]=true,["os"]=true,
    ["coroutine"]=true,["task"]=true,["bit32"]=true,["utf8"]=true,["debug"]=true,
}
local ROBLOX = {
    ["game"]=true,["workspace"]=true,["script"]=true,["Instance"]=true,
    ["Vector3"]=true,["Vector2"]=true,["CFrame"]=true,["Color3"]=true,
    ["BrickColor"]=true,["UDim"]=true,["UDim2"]=true,["Enum"]=true,
    ["wait"]=true,["spawn"]=true,["delay"]=true,["tick"]=true,["time"]=true,
    ["shared"]=true,["_G"]=true,["_ENV"]=true,
}

local function escapeXML(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

local function tryLongBracket(code, pos)
    if code:sub(pos, pos) ~= "[" then return nil end
    local j = pos + 1
    local eqs = ""
    while code:sub(j, j) == "=" do
        eqs = eqs .. "="
        j = j + 1
    end
    if code:sub(j, j) ~= "[" then return nil end
    return eqs, j + 1
end

local function tokenize(code)
    local tokens = {}
    local i, n = 1, #code
    while i <= n do
        local c  = code:sub(i, i)
        local c2 = code:sub(i, i + 1)

        if c2 == "--" then
            local eqs, afterOpen = tryLongBracket(code, i + 2)
            if eqs then
                local close = "]" .. eqs .. "]"
                local k = code:find(close, afterOpen, true)
                local endPos = k and (k + #close - 1) or n
                tokens[#tokens + 1] = { t = "comment", v = code:sub(i, endPos) }
                i = endPos + 1
            else
                local k = code:find("\n", i, true)
                local endPos = k and (k - 1) or n
                tokens[#tokens + 1] = { t = "comment", v = code:sub(i, endPos) }
                i = endPos + 1
            end

        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local ch = code:sub(j, j)
                if ch == "\\" then
                    j = j + 2
                elseif ch == c then
                    j = j + 1
                    break
                else
                    j = j + 1
                end
            end
            if j > n then j = n + 1 end
            tokens[#tokens + 1] = { t = "string", v = code:sub(i, j - 1) }
            i = j

        elseif c == "[" then
            local eqs, afterOpen = tryLongBracket(code, i)
            if eqs then
                local close = "]" .. eqs .. "]"
                local k = code:find(close, afterOpen, true)
                local endPos = k and (k + #close - 1) or n
                tokens[#tokens + 1] = { t = "string", v = code:sub(i, endPos) }
                i = endPos + 1
            else
                tokens[#tokens + 1] = { t = "default", v = c }
                i = i + 1
            end

        elseif c:match("[%a_]") then
            local j = i
            while j <= n and code:sub(j, j):match("[%w_]") do j = j + 1 end
            local word = code:sub(i, j - 1)
            local kind
            if LITERALS[word] then
                kind = "literal"
            elseif KEYWORDS[word] then
                kind = "keyword"
            elseif BUILTINS[word] then
                kind = "builtin"
            elseif ROBLOX[word] then
                kind = "roblox"
            else
                local k = j
                while k <= n and code:sub(k, k):match("%s") do k = k + 1 end
                if code:sub(k, k) == "(" then kind = "call" else kind = "default" end
            end
            tokens[#tokens + 1] = { t = kind, v = word }
            i = j

        elseif c:match("%d") or (c == "." and code:sub(i + 1, i + 1):match("%d")) then
            local j = i
            if c == "0" and code:sub(i + 1, i + 1):match("[xXbB]") then
                j = i + 2
                while j <= n and code:sub(j, j):match("[%w_%.]") do j = j + 1 end
            else
                while j <= n and code:sub(j, j):match("[%d_%.]") do j = j + 1 end
                if code:sub(j, j):match("[eE]") then
                    j = j + 1
                    if code:sub(j, j):match("[+%-]") then j = j + 1 end
                    while j <= n and code:sub(j, j):match("%d") do j = j + 1 end
                end
            end
            tokens[#tokens + 1] = { t = "number", v = code:sub(i, j - 1) }
            i = j

        else
            tokens[#tokens + 1] = { t = "default", v = c }
            i = i + 1
        end
    end
    return tokens
end

-- Coalesce adjacent same-type tokens to reduce <font> tag count.
local function mergeTokens(tokens)
    local merged = {}
    for _, tok in ipairs(tokens) do
        local last = merged[#merged]
        if last and last.t == tok.t then
            last.v = last.v .. tok.v
        else
            merged[#merged + 1] = { t = tok.t, v = tok.v }
        end
    end
    return merged
end

local function highlight(code)
    local tokens = mergeTokens(tokenize(code))
    local out = {}
    for _, tok in ipairs(tokens) do
        local color = HL[tok.t] or HL.default
        out[#out + 1] = '<font color="#' .. color .. '">' .. escapeXML(tok.v) .. '</font>'
    end
    return table.concat(out)
end

-- ============================================================
-- EDITOR SIZING
-- ============================================================
local cachedW, cachedText, cachedViewH = -1, nil, -1

local function measureTextHeight(text, width)
    if width <= 0 then return 30 end
    local probe = text
    if probe == "" then probe = " " end
    if probe:sub(-1) == "\n" then probe = probe .. " " end
    local ok, sz = pcall(function()
        return TextService:GetTextSize(
            probe, 13, FONT_MONO, Vector2.new(width, 1e6))
    end)
    if ok and sz and sz.Y then
        -- Add two full lines of safety margin so the TextBox never
        -- internally scrolls (which would desync from the overlay).
        return math.max(30, math.ceil(sz.Y) + LINE_HEIGHT_PX * 2)
    end
    return 30
end

local function refreshEditorSize()
    local w, viewH = 0, 0
    do
        local ok, sz = pcall(function() return EditorScroll.AbsoluteSize end)
        if ok and sz then
            w = sz.X
            viewH = sz.Y
        end
    end
    if w <= 0 then return end

    local text = InputBox.Text
    if w == cachedW and text == cachedText and viewH == cachedViewH then
        return
    end
    cachedW, cachedText, cachedViewH = w, text, viewH

    local contentH = measureTextHeight(text, w)
    local totalH   = math.max(contentH, viewH)

    InputBox.Size           = UDim2.new(1, 0, 0, totalH)
    HighlightOverlay.Size   = UDim2.new(1, 0, 0, totalH)
    EditorScroll.CanvasSize = UDim2.new(1, 0, 0, totalH)
end

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
    local prevPrint = print
    local prevWarn  = warn

    local okPrint = pcall(function()
        print = function(...)
            local line
            local okArgs, result = pcall(joinArgs, ...)
            if okArgs then line = result else line = "<print arg error>" end
            pcall(record, line, "out")
            pcall(prevPrint, "[JD] " .. line)
        end
    end)
    local okWarn = pcall(function()
        warn = function(...)
            local line
            local okArgs, result = pcall(joinArgs, ...)
            if okArgs then line = result else line = "<warn arg error>" end
            pcall(record, line, "warn")
            pcall(prevWarn, "[JD] " .. line)
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
    local chunk, compileErr = loader(code, "=GabuleDevConsole")
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

trackConnection(UIS.InputBegan:Connect(function(input)
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
end))

-- ============================================================
-- HIGHLIGHT OVERLAY STATE
-- ============================================================
local highlightEnabled = true
local inputFocused     = false
local highlightPending = false

local function refreshHighlight()
    if not highlightEnabled then return end
    local text = InputBox.Text

    if text == "" then
        HighlightOverlay.Text = ""
        return
    end

    local ok, markup
    if #text > LARGE_TEXT_LIMIT then
        ok, markup = pcall(escapeXML, text)
    else
        ok, markup = pcall(highlight, text)
    end

    if not ok then
        highlightEnabled = false
        HighlightOverlay.Text = ""
        HighlightOverlay.Visible = false
        InputBox.TextTransparency = 0
        return
    end

    HighlightOverlay.Text = markup
end

local function scheduleHighlight()
    if highlightPending then return end
    highlightPending = true
    task.defer(function()
        highlightPending = false
        refreshHighlight()
    end)
end

-- Single source of truth for editor visibility. Everything that
-- can change focus, text, or highlighter state funnels through here.
local function applyEditorVisuals()
    if InputBox.Text == "" then
        InputBox.TextTransparency = 0
        HighlightOverlay.Visible = false
        return
    end
    if inputFocused or not highlightEnabled then
        InputBox.TextTransparency = 0
        HighlightOverlay.Visible = false
    else
        InputBox.TextTransparency = 1
        HighlightOverlay.Visible = true
    end
end

InputBox.Focused:Connect(function()
    inputFocused = true
    applyEditorVisuals()
end)

InputBox.FocusLost:Connect(function()
    inputFocused = false
    if InputBox.Text ~= "" and highlightEnabled then
        refreshHighlight()
    end
    applyEditorVisuals()
end)

InputBox:GetPropertyChangedSignal("Text"):Connect(function()
    refreshEditorSize()
    if not inputFocused and InputBox.Text ~= "" and highlightEnabled then
        scheduleHighlight()
    end
    applyEditorVisuals()
end)

-- Cursor follow: keep the caret inside the visible band while typing.
local cursorPending = false
InputBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
    if not inputFocused then return end
    if cursorPending then return end
    cursorPending = true
    task.defer(function()
        cursorPending = false
        if not inputFocused then return end
        local w = 0
        do
            local ok, sz = pcall(function() return EditorScroll.AbsoluteSize end)
            if ok and sz then w = sz.X end
        end
        if w <= 0 then return end

        local text = InputBox.Text
        local pos  = math.max(1, InputBox.CursorPosition)
        local before = text:sub(1, pos - 1)

        local ok, sz = pcall(function()
            return TextService:GetTextSize(
                before == "" and " " or before,
                13, FONT_MONO, Vector2.new(w, 1e6))
        end)
        if not ok or not sz then return end

        local cursorY = sz.Y
        local cp = EditorScroll.CanvasPosition.Y
        local vh = EditorScroll.AbsoluteSize.Y
        if vh <= 0 then return end

        if cursorY - LINE_HEIGHT_PX < cp then
            EditorScroll.CanvasPosition = Vector2.new(0, math.max(0, cursorY - LINE_HEIGHT_PX * 2))
        elseif cursorY + LINE_HEIGHT_PX > cp + vh then
            EditorScroll.CanvasPosition = Vector2.new(0, cursorY + LINE_HEIGHT_PX * 2 - vh)
        end
    end)
end)

EditorScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    refreshEditorSize()
end)

-- ============================================================
-- LAYOUT
-- ============================================================
local function relayout()
    local w = Main.Size.X.Offset
    local h = Main.Size.Y.Offset
    local Ch = math.max(100, h - 58)
    local Cw = math.max(100, w - 24)

    local statusH = 18
    local statusY = Ch - statusH
    Status.Position = UDim2.new(0, 2, 0, statusY)
    Status.Size     = UDim2.new(1, -34, 0, statusH)

    local btnH   = 34
    local btnGap = 6
    local btnY   = statusY - btnGap - btnH
    ButtonRow.Position = UDim2.new(0, 0, 0, btnY)
    ButtonRow.Size     = UDim2.new(1, 0, 0, btnH)

    local btns  = { RunBtn, PresetBtn, CopyLogBtn, CopyInBtn, ClearLogBtn, ClearInBtn }
    local count = #btns
    local gap   = 6
    local avail = Cw - (count - 1) * gap
    local bw    = math.max(40, math.floor(avail / count))
    for _, b in ipairs(btns) do
        b.Size = UDim2.new(0, bw, 0, 32)
    end

    local inputTop = 20
    local inputH   = math.clamp(math.floor(Ch * 0.28), 80, 140)
    InputFrame.Position = UDim2.new(0, 0, 0, inputTop)
    InputFrame.Size     = UDim2.new(1, 0, 0, inputH)

    local outputLabelY = inputTop + inputH + 10
    OutputLabel.Position = UDim2.new(0, 2, 0, outputLabelY)
    OutputLabel.Size     = UDim2.new(1, 0, 0, 16)

    local outputTop    = outputLabelY + 20
    local outputBottom = btnY - 8
    local outputH      = math.max(60, outputBottom - outputTop)
    OutputScroll.Position = UDim2.new(0, 0, 0, outputTop)
    OutputScroll.Size     = UDim2.new(1, 0, 0, outputH)

    local pmW = math.min(280, math.max(160, Cw - 16))
    local pmH = math.min(220, math.max(120, Ch - 40))
    local pmX = math.min(76,  math.max(8, Cw - pmW - 8))
    local pmY = math.min(118, math.max(8, Ch - pmH - 8))
    PresetMenu.Position = UDim2.new(0, pmX, 0, pmY)
    PresetMenu.Size     = UDim2.new(0, pmW, 0, pmH)

    refreshEditorSize()
end

relayout()

-- ============================================================
-- DRAG + RESIZE
-- ============================================================
local activeOp    = nil
local opStart     = nil
local opStartX, opStartY    = 0, 0
local opStartW, opStartH    = 0, 0

TitleBar.InputBegan:Connect(function(input)
    if activeOp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        local mp = Main.AbsolutePosition
        activeOp = "drag"
        opStart  = input.Position
        opStartX, opStartY = mp.X, mp.Y
    end
end)

ResizeHandle.InputBegan:Connect(function(input)
    if activeOp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        local ms = Main.AbsoluteSize
        activeOp = "resize"
        opStart  = input.Position
        opStartW, opStartH = ms.X, ms.Y
    end
end)

trackConnection(UIS.InputChanged:Connect(function(input)
    if not activeOp then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
       and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - opStart
    local vp    = getViewportSize()

    if activeOp == "drag" then
        local ms = Main.AbsoluteSize
        local nx = math.clamp(opStartX + delta.X, 0, math.max(0, vp.X - ms.X))
        local ny = math.clamp(opStartY + delta.Y, 0, math.max(0, vp.Y - ms.Y))
        Main.Position = UDim2.new(0, nx, 0, ny)

    elseif activeOp == "resize" then
        local mp   = Main.AbsolutePosition
        local maxW = math.max(MIN_W, vp.X - mp.X)
        local maxH = math.max(MIN_H, vp.Y - mp.Y)
        local nw   = math.clamp(opStartW + delta.X, MIN_W, maxW)
        local nh   = math.clamp(opStartH + delta.Y, MIN_H, maxH)
        Main.Size = UDim2.new(0, nw, 0, nh)
        relayout()
    end
end))

trackConnection(UIS.InputEnded:Connect(function(input)
    local isPrimary = input.UserInputType == Enum.UserInputType.MouseButton1
                   or input.UserInputType == Enum.UserInputType.Touch
    if isPrimary and activeOp then
        activeOp = nil
    end
end))

-- ============================================================
-- VIEWPORT CHANGE HANDLER
-- ============================================================
do
    local cam = workspace.CurrentCamera
    if cam then
        trackConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local vp = getViewportSize()
            local mp = Main.AbsolutePosition
            local ms = Main.AbsoluteSize

            local maxW = math.max(MIN_W, vp.X)
            local maxH = math.max(MIN_H, vp.Y)
            local nw   = math.min(ms.X, maxW)
            local nh   = math.min(ms.Y, maxH)
            if nw ~= ms.X or nh ~= ms.Y then
                Main.Size = UDim2.new(0, nw, 0, nh)
                relayout()
            end

            local nx = math.clamp(mp.X, 0, math.max(0, vp.X - nw))
            local ny = math.clamp(mp.Y, 0, math.max(0, vp.Y - nh))
            if nx ~= mp.X or ny ~= mp.Y then
                Main.Position = UDim2.new(0, nx, 0, ny)
            end
        end))
    end
end

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

-- Draggable minimized icon. If the user actually dragged it, the
-- click is suppressed so a drag doesn't also restore the window.
do
    local dragging = false
    local moved    = false
    local dragStart, startPos = nil, nil

    RestoreBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            moved     = false
            dragStart = input.Position
            startPos  = RestoreBtn.AbsolutePosition
        end
    end)

    trackConnection(UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
           and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then moved = true end
        local vp = getViewportSize()
        local ms = RestoreBtn.AbsoluteSize
        local nx = math.clamp(startPos.X + delta.X, 0, math.max(0, vp.X - ms.X))
        local ny = math.clamp(startPos.Y + delta.Y, 0, math.max(0, vp.Y - ms.Y))
        RestoreBtn.Position = UDim2.new(0, nx, 0, ny)
    end))

    trackConnection(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    RestoreBtn.MouseButton1Click:Connect(function()
        if moved then return end
        Main.Visible = true
        RestoreBtn.Visible = false
    end)
end

-- ============================================================
-- KEYBIND: F2 toggles visibility
-- ============================================================
trackConnection(UIS.InputBegan:Connect(function(input, gpe)
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
end))

-- ============================================================
-- INIT
-- ============================================================
local okPrint, okWarn = installOutputHooks()

record("Gabule DevConsole ready.", "ok")
if not okPrint then
    record("[warn] global print could not be hooked — user output may not appear here", "warn")
end
if not okWarn then
    record("[warn] global warn could not be hooked", "warn")
end
record("Paste Lua above and press Run.  Presets has ready-made recon snippets.", "dim")
record("F2 toggles the window.  Copy Log grabs everything for pasting back here.", "dim")
setStatus("Ready", C.dim)

-- ============================================================
-- CLEANUP REGISTRATION
-- ============================================================
local function runCleanup()
    if _G[CLEANUP_KEY] == runCleanup then
        _G[CLEANUP_KEY] = nil
    end

    -- Disconnect service-owned connections. GUI-owned connections
    -- disappear with the ScreenGui below, so they aren't tracked.
    for _, conn in ipairs(trackedConnections) do
        pcall(function() conn:Disconnect() end)
    end
    trackedConnections = {}

    -- Restore print/warn to whatever they were before this session.
    pcall(function() print = realPrint end)
    pcall(function() warn  = realWarn  end)

    pcall(function() ScreenGui:Destroy() end)
end

closeConsole = runCleanup
_G[CLEANUP_KEY] = runCleanup