--[[
    Charles's DevConsole  v2.0.2
    Startup/lifecycle audit release. Fixes only — no new features.

    Fixes vs 2.0.1:
      - ScreenGui is parented to PlayerGui first. gethui()/CoreGui are only
        used if PlayerGui is genuinely unavailable. Previously a ScreenGui
        parented to a non-rendering gethui() container would exist but never
        display, producing "executes but nothing appears".
      - ScreenGui.Enabled and Main.Visible are set explicitly.
      - computeDefaultSize can no longer return a negative size on very
        small safe areas.
      - Startup diagnostic: emits SCRIPT_STARTED, SERVICES_READY,
        SCREEN_GUI_CREATED, SCREEN_GUI_PARENTED, SCREEN_GUI_HAS_VALID_SIZE,
        MAIN_CREATED, LAYOUT_COMPLETE, MAIN_VISIBLE, INITIALIZATION_COMPLETE
        to the executor console via raw print/warn. Failures emit FAIL lines
        instead of being swallowed by pcall.
      - Previous-cleanup errors are surfaced.
]]

local CONSOLE_VERSION = "2.0.2"
local CLEANUP_KEY = "_CharlesDevConsole_Cleanup_v2"

-- ============================================================
-- BOOT DIAGNOSTIC
-- ============================================================
-- Emits to the executor console using the raw print/warn globals so the
-- diagnostic survives even if the console never renders. Every stage is
-- named exactly as in the audit request.

local Boot = { stages = {}, failedStage = nil, startedAt = os.clock() }
local RAW_PRINT = print
local RAW_WARN  = warn

local function bootEmit(line)
    pcall(function() RAW_WARN(line) end)
    pcall(function() RAW_PRINT(line) end)
end
local function bootLog(stage, detail)
    local t = os.clock() - Boot.startedAt
    Boot.stages[#Boot.stages + 1] = { stage = stage, detail = detail, t = t }
    bootEmit(string.format("[DC-BOOT %.3f] %s%s",
        t, stage, detail and (" — " .. tostring(detail)) or ""))
end
local function bootFail(stage, err)
    Boot.failedStage = stage
    bootEmit("[DC-BOOT] FAIL " .. stage .. " — " .. tostring(err))
end

bootLog("SCRIPT_STARTED", "v" .. CONSOLE_VERSION)

-- Run the previous cleanup (if any) and surface errors instead of hiding them.
if type(_G[CLEANUP_KEY]) == "function" then
    local ok, err = pcall(_G[CLEANUP_KEY])
    if not ok then bootLog("PREVIOUS_CLEANUP", "errored: " .. tostring(err)) end
end

local _cleanup = {}
local function onCleanup(fn) _cleanup[#_cleanup + 1] = fn end
local function runCleanup()
    for i = #_cleanup, 1, -1 do pcall(_cleanup[i]) end
    _cleanup = {}
    if _G[CLEANUP_KEY] == runCleanup then _G[CLEANUP_KEY] = nil end
end
_G[CLEANUP_KEY] = runCleanup

-- ============================================================
-- SERVICES
-- ============================================================
local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local LP = Players.LocalPlayer

if not LP then
    bootFail("SERVICES_READY", "LocalPlayer is nil — cannot continue")
    error("Charles's DevConsole: LocalPlayer unavailable")
end
bootLog("SERVICES_READY", "LocalPlayer=" .. tostring(LP.Name))

-- ============================================================
-- THEME
-- ============================================================
local T = {
    bg          = Color3.fromRGB(24, 24, 28),
    panel       = Color3.fromRGB(32, 32, 38),
    panel2      = Color3.fromRGB(42, 42, 50),
    panel3      = Color3.fromRGB(58, 58, 68),
    editorBg    = Color3.fromRGB(30, 30, 32),
    outputBg    = Color3.fromRGB(22, 22, 26),
    accent      = Color3.fromRGB(86, 156, 214),
    accentHover = Color3.fromRGB(110, 175, 230),
    text        = Color3.fromRGB(220, 220, 224),
    dim         = Color3.fromRGB(140, 140, 150),
    faint       = Color3.fromRGB(90, 90, 100),
    err         = Color3.fromRGB(244, 135, 113),
    warn        = Color3.fromRGB(220, 220, 170),
    ok          = Color3.fromRGB(120, 200, 130),
    info        = Color3.fromRGB(120, 200, 230),
    border      = Color3.fromRGB(60, 60, 70),
    borderSoft  = Color3.fromRGB(46, 46, 54),
    close       = Color3.fromRGB(200, 70, 70),
}
local HL = {
    comment="6A9955", string="CE9178", number="B5CEA8", keyword="C586C0",
    literal="569CD6", builtin="4FC1FF", roblox="4EC9B0", call="DCDCAA", default="D4D4D4",
}
local FONT      = Enum.Font.GothamMedium
local FONT_MONO = Enum.Font.Code

-- ============================================================
-- HELPERS
-- ============================================================
local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p; return c
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke"); s.Color = col or T.border; s.Thickness = th or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s
end
local function padding(p, t, r, b, l)
    local pd = Instance.new("UIPadding")
    pd.PaddingTop=UDim.new(0,t or 0); pd.PaddingRight=UDim.new(0,r or 0)
    pd.PaddingBottom=UDim.new(0,b or 0); pd.PaddingLeft=UDim.new(0,l or 0)
    pd.Parent=p; return pd
end
local function safeToString(v) local ok,s = pcall(tostring, v); return ok and s or "<tostring error>" end
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function copyToClipboard(text)
    return (pcall(function()
        if setclipboard    then setclipboard(text)    return end
        if toclipboard     then toclipboard(text)     return end
        if setrbxclipboard then setrbxclipboard(text) return end
        if writeclipboard  then writeclipboard(text)  return end
        error("no clipboard function available")
    end))
end
local function escapeXML(s)
    s = s:gsub("&","&amp;"); s = s:gsub("<","&lt;"); s = s:gsub(">","&gt;"); s = s:gsub('"',"&quot;")
    return s
end
local function stripMarkup(s)
    s = s:gsub("<font[^>]*>",""); s = s:gsub("</font>","")
    s = s:gsub("&lt;","<"); s = s:gsub("&gt;",">"); s = s:gsub("&quot;",'"')
    s = s:gsub("&apos;","'"); s = s:gsub("&amp;","&")
    return s
end

-- ============================================================
-- VALUE SERIALIZER
-- ============================================================
local function formatValueBrief(v)
    local tv = type(v)
    if tv == "string" then
        if #v > 80 then return string.format("%q...(+%d)", v:sub(1,77), #v-77) end
        return string.format("%q", v)
    elseif tv == "number" or tv == "boolean" then return tostring(v)
    elseif tv == "nil" then return "nil"
    elseif tv == "function" then return "<function>"
    elseif tv == "thread" then return "<thread>"
    elseif tv == "table" then return "<table#" .. safeToString(#v) .. ">"
    elseif tv == "userdata" then
        local ok,isInst = pcall(function() return typeof(v) == "Instance" end)
        if ok and isInst then
            local ok2,name = pcall(function() return v:GetFullName() end)
            return "<Instance " .. (ok2 and name or "?") .. ">"
        end
        return "<userdata>"
    end
    return "<" .. tv .. ">"
end

local function serializeValue(v, opts)
    opts = opts or {}
    local maxDepth = opts.maxDepth or 4
    local maxItems = opts.maxItems or 50
    local seen = {}
    local function walk(value, depth)
        local tv = type(value)
        if tv == "nil" then return "nil"
        elseif tv == "boolean" then return tostring(value)
        elseif tv == "number" then
            if value ~= value then return "nan" end
            if value == math.huge then return "math.huge" end
            if value == -math.huge then return "-math.huge" end
            return tostring(value)
        elseif tv == "string" then
            if #value > 400 then
                return string.format("%q .. \"<truncated %d chars>\"", value:sub(1,400), #value-400)
            end
            return string.format("%q", value)
        elseif tv == "function" then
            local info
            if debug and debug.getinfo then
                local ok,i = pcall(debug.getinfo, value, "S")
                if ok then info = i end
            end
            if info then return string.format("<function %s:%s>", info.short_src or "?", info.linedefined or "?") end
            return "<function>"
        elseif tv == "thread" then return "<thread " .. tostring(value):gsub("^thread: ","") .. ">"
        elseif tv == "userdata" then
            local ok,isInst = pcall(function() return typeof(value) == "Instance" end)
            if ok and isInst then
                local ok2,full = pcall(function() return value:GetFullName() end)
                local ok3,cls  = pcall(function() return value.ClassName end)
                return string.format("<Instance %s [%s]>", ok2 and full or "?", ok3 and cls or "?")
            end
            return "<userdata>"
        elseif tv == "table" then
            if seen[value] then return "<cycle>" end
            if depth >= maxDepth then return "{...}" end
            seen[value] = true
            local isArray, n = true, 0
            for k in pairs(value) do
                if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then isArray = false; break end
                if k > n then n = k end
            end
            if isArray and n > 0 then
                for i = 1, n do if value[i] == nil then isArray = false; break end end
            end
            if isArray and n == 0 then isArray = false end
            local parts, count = {}, 0
            if isArray then
                for i = 1, n do
                    count = count + 1
                    if count > maxItems then parts[#parts+1] = "... (+" .. (n - maxItems) .. " more)"; break end
                    parts[#parts+1] = walk(value[i], depth+1)
                end
                seen[value] = nil
                return "{" .. table.concat(parts, ", ") .. "}"
            end
            for k, vv in pairs(value) do
                count = count + 1
                if count > maxItems then parts[#parts+1] = "... (+more)"; break end
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then keyStr = k
                elseif type(k) == "string" then keyStr = string.format("[%q]", k)
                else keyStr = "[" .. walk(k, depth+1) .. "]" end
                parts[#parts+1] = keyStr .. " = " .. walk(vv, depth+1)
            end
            seen[value] = nil
            if #parts == 0 then return "{}" end
            if depth == 0 then return "{\n  " .. table.concat(parts, ",\n  ") .. "\n}" end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
        return safeToString(value)
    end
    return walk(v, 0)
end

-- ============================================================
-- SYNTAX HIGHLIGHTER
-- ============================================================
local KEYWORDS = {
    ["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,
    ["end"]=true,["for"]=true,["function"]=true,["if"]=true,["in"]=true,
    ["local"]=true,["not"]=true,["or"]=true,["repeat"]=true,["return"]=true,
    ["then"]=true,["until"]=true,["while"]=true,["continue"]=true,
    ["export"]=true,["type"]=true,
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
    ["Random"]=true,["Rect"]=true,["Region3"]=true,["Ray"]=true,
    ["TweenInfo"]=true,["NumberRange"]=true,["NumberSequence"]=true,
    ["ColorSequence"]=true,["ColorSequenceKeypoint"]=true,["NumberSequenceKeypoint"]=true,
    ["Font"]=true,["PhysicalProperties"]=true,["Axes"]=true,["Faces"]=true,
    ["DateTime"]=true,["OverlapParams"]=true,["RaycastParams"]=true,
    ["shared"]=true,["_G"]=true,["_ENV"]=true,
}

local function matchLongBracket(code, i)
    local j = i
    if code:sub(j,j) ~= "[" then return nil end
    j = j + 1
    local eqs = ""
    while j <= #code and code:sub(j,j) == "=" do eqs = eqs .. "="; j = j + 1 end
    if code:sub(j,j) ~= "[" then return nil end
    return eqs, j + 1
end

local function tokenize(code)
    local tokens = {}
    local i, n = 1, #code
    while i <= n do
        local c  = code:sub(i,i)
        local c2 = code:sub(i,i+1)
        if c2 == "--" then
            local eqs, afterOpen = matchLongBracket(code, i + 2)
            if eqs then
                local close = "]" .. eqs .. "]"
                local k = code:find(close, afterOpen, true)
                local endPos = k and (k + #close - 1) or n
                tokens[#tokens+1] = { t="comment", v=code:sub(i, endPos) }
                i = endPos + 1
            else
                local k = code:find("\n", i, true)
                local endPos = k and (k - 1) or n
                tokens[#tokens+1] = { t="comment", v=code:sub(i, endPos) }
                i = endPos + 1
            end
        elseif c == '"' or c == "'" then
            local q = c; local j = i + 1
            while j <= n do
                local ch = code:sub(j,j)
                if ch == "\\" then j = j + 2
                elseif ch == q then j = j + 1; break
                else j = j + 1 end
            end
            if j > n then j = n + 1 end
            tokens[#tokens+1] = { t="string", v=code:sub(i, j-1) }; i = j
        elseif c == "`" then
            local j = i + 1
            while j <= n do
                local ch = code:sub(j,j)
                if ch == "\\" then j = j + 2
                elseif ch == "`" then j = j + 1; break
                else j = j + 1 end
            end
            if j > n then j = n + 1 end
            tokens[#tokens+1] = { t="string", v=code:sub(i, j-1) }; i = j
        elseif c == "[" then
            local eqs, afterOpen = matchLongBracket(code, i)
            if eqs then
                local close = "]" .. eqs .. "]"
                local k = code:find(close, afterOpen, true)
                local endPos = k and (k + #close - 1) or n
                tokens[#tokens+1] = { t="string", v=code:sub(i, endPos) }; i = endPos + 1
            else
                tokens[#tokens+1] = { t="default", v=c }; i = i + 1
            end
        elseif c:match("[%a_]") then
            local j = i
            while j <= n and code:sub(j,j):match("[%w_]") do j = j + 1 end
            local word = code:sub(i, j-1)
            local kind
            if LITERALS[word] then kind = "literal"
            elseif KEYWORDS[word] then kind = "keyword"
            elseif BUILTINS[word] then kind = "builtin"
            elseif ROBLOX[word] then kind = "roblox"
            else
                local k = j
                while k <= n and code:sub(k,k):match("%s") do k = k + 1 end
                local nxt = code:sub(k,k)
                if nxt == "(" or nxt == "{" or nxt == '"' or nxt == "'" then kind = "call"
                else kind = "default" end
            end
            tokens[#tokens+1] = { t=kind, v=word }; i = j
        elseif c:match("%d") or (c == "." and code:sub(i+1,i+1):match("%d")) then
            local j = i
            if code:sub(j,j) == "0" and code:sub(j+1,j+1):match("[xXbB]") then
                j = j + 2
                while j <= n and code:sub(j,j):match("[%w_%.]") do j = j + 1 end
            else
                while j <= n and code:sub(j,j):match("[%d_%.]") do j = j + 1 end
                if code:sub(j,j):match("[eE]") then
                    j = j + 1
                    if code:sub(j,j):match("[+%-]") then j = j + 1 end
                    while j <= n and code:sub(j,j):match("%d") do j = j + 1 end
                end
            end
            tokens[#tokens+1] = { t="number", v=code:sub(i, j-1) }; i = j
        else
            tokens[#tokens+1] = { t="default", v=c }; i = i + 1
        end
    end
    return tokens
end

local function highlight(code)
    local tokens = tokenize(code)
    local out = {}
    for _, tok in ipairs(tokens) do
        local color = HL[tok.t] or HL.default
        out[#out+1] = '<font color="#' .. color .. '">' .. escapeXML(tok.v) .. '</font>'
    end
    return table.concat(out)
end

local function plainToMarkupPos(plainText, markupText, plainPos)
    local target = math.max(0, plainPos - 1)
    local count = 0
    local i, n = 1, #markupText
    while count < target and i <= n do
        local ch = markupText:sub(i,i)
        if ch == "<" then
            local close = markupText:find(">", i, true)
            if close then i = close + 1 else break end
        elseif ch == "&" then
            local semi = markupText:find(";", i, true)
            if semi and (semi - i) < 8 then i = semi + 1; count = count + 1
            else i = i + 1; count = count + 1 end
        else i = i + 1; count = count + 1 end
    end
    return math.clamp(i, 1, n + 1)
end

local function markupToPlainPos(markupText, pos)
    local count = 0
    local i = 1
    while i < pos do
        local ch = markupText:sub(i,i)
        if ch == "<" then
            local close = markupText:find(">", i, true)
            if close then i = close + 1 else i = i + 1 end
        elseif ch == "&" then
            local semi = markupText:find(";", i, true)
            if semi and (semi - i) < 8 then i = semi + 1; count = count + 1
            else i = i + 1; count = count + 1 end
        else i = i + 1; count = count + 1 end
    end
    return count + 1
end

-- ============================================================
-- STATE
-- ============================================================
local State = {
    history = {}, historyIndex = 0,
    buffer = {}, lineLabels = {}, maxLines = 600,
    recentErrors = {}, recentWarnings = {},
    execCount = 0,
    highlightEnabled = true,
    spy = { active = false, unmount = nil },
}

-- ============================================================
-- BUILD GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CharlesDevConsole_" .. tostring(math.random(100000, 999999))
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 100000
ScreenGui.Enabled = true          -- FIX: explicit
bootLog("SCREEN_GUI_CREATED", ScreenGui.Name)

-- ------------------------------------------------------------------
-- Parent selection.
-- PlayerGui is tried first. gethui()/CoreGui are only used if PlayerGui
-- is genuinely unavailable. Parent selection is verified by comparing
-- ScreenGui.Parent to the intended container; a silent no-op fails over.
-- ------------------------------------------------------------------
do
    local parentUsed = nil

    -- 1. PlayerGui (preferred)
    local pgOk, pg = pcall(function() return LP:WaitForChild("PlayerGui", 5) end)
    if pgOk and pg then
        local ok = pcall(function() ScreenGui.Parent = pg end)
        if ok and ScreenGui.Parent == pg then
            parentUsed = "PlayerGui"
        end
    end

    -- 2. gethui / CoreGui fallback
    if not parentUsed then
        local container, label
        if gethui then
            local ok, h = pcall(gethui)
            if ok and h then container = h; label = "gethui" end
        end
        if not container then
            local ok, cg = pcall(function() return game:GetService("CoreGui") end)
            if ok and cg then container = cg; label = "CoreGui" end
        end
        if container then
            local ok = pcall(function() ScreenGui.Parent = container end)
            if ok and ScreenGui.Parent == container then
                parentUsed = label
            end
        end
    end

    if parentUsed then
        bootLog("SCREEN_GUI_PARENTED", parentUsed)
    else
        bootFail("SCREEN_GUI_PARENTED", "no valid parent could be assigned")
    end
end
onCleanup(function() ScreenGui:Destroy() end)

-- safeRect uses ScreenGui.AbsolutePosition / AbsoluteSize when available,
-- and falls back to the camera viewport before layout has been computed.
local function safeRect()
    local pos  = ScreenGui.AbsolutePosition
    local size = ScreenGui.AbsoluteSize
    if size.X < 40 or size.Y < 40 then
        local cam = workspace.CurrentCamera
        local vp  = cam and cam.ViewportSize or Vector2.new(1280, 720)
        return Vector2.new(0, 0), vp
    end
    return pos, size
end

-- Short bounded wait for layout. If the ScreenGui is not laid out in 0.5s,
-- safeRect() will fall back to the viewport size and we proceed.
do
    local waited = 0
    while waited < 0.5 do
        local s = ScreenGui.AbsoluteSize
        if s.X >= 40 and s.Y >= 40 then break end
        task.wait(0.05)
        waited = waited + 0.05
    end
    local s = ScreenGui.AbsoluteSize
    if s.X >= 40 and s.Y >= 40 then
        bootLog("SCREEN_GUI_HAS_VALID_SIZE", tostring(s))
    else
        bootLog("SCREEN_GUI_HAS_VALID_SIZE", "TIMEOUT at " .. tostring(s) .. " — using safeRect fallback")
    end
end

-- ------------------------------------------------------------------
-- Default size. Never returns a value that could produce a negative or
-- degenerate Main.Size, even if the safe area is extremely small.
-- ------------------------------------------------------------------
local function computeDefaultSize(sw, sh)
    if sw < 40 or sh < 40 then
        local cam = workspace.CurrentCamera
        local vp  = cam and cam.ViewportSize or Vector2.new(1280, 720)
        sw, sh = vp.X, vp.Y
    end
    local w, h
    if sh > sw then
        w = math.min(sw * 0.96, 620); h = math.min(sh * 0.76, 760)
    else
        w = math.min(sw * 0.72, 900); h = math.min(sh * 0.86, 660)
    end
    w = math.max(w, 300); h = math.max(h, 340)
    w = math.min(w, math.max(300, sw - 12))
    h = math.min(h, math.max(340, sh - 12))
    return w, h
end

local sgPos, sgSize = safeRect()
local initW, initH = computeDefaultSize(sgSize.X, sgSize.Y)
local initX = math.max(4, math.floor((sgSize.X - initW) / 2))
local initY = math.max(4, math.floor((sgSize.Y - initH) / 2))

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size     = UDim2.new(0, initW, 0, initH)
Main.Position = UDim2.new(0, initX, 0, initY)
Main.BackgroundColor3 = T.bg
Main.BorderSizePixel  = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Visible = true               -- FIX: explicit
Main.Parent = ScreenGui
corner(Main, 10); stroke(Main, T.border, 1)
bootLog("MAIN_CREATED", string.format("%dx%d @ (%d,%d)", initW, initH, initX, initY))

-- ---------- Title bar ----------
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3 = T.panel
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = Main
corner(TitleBar, 10)

local TitleMask = Instance.new("Frame")
TitleMask.Size = UDim2.new(1, 0, 0, 10)
TitleMask.Position = UDim2.new(0, 0, 1, -10)
TitleMask.BackgroundColor3 = T.panel
TitleMask.BorderSizePixel = 0
TitleMask.Parent = TitleBar

local AccentBar = Instance.new("Frame")
AccentBar.Size = UDim2.new(0, 3, 0, 18)
AccentBar.Position = UDim2.new(0, 10, 0.5, -9)
AccentBar.BackgroundColor3 = T.accent
AccentBar.BorderSizePixel = 0
AccentBar.Parent = TitleBar
corner(AccentBar, 2)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.BackgroundTransparency = 1
TitleLabel.Position = UDim2.new(0, 20, 0, 0)
TitleLabel.Size = UDim2.new(1, -110, 1, 0)
TitleLabel.Font = FONT
TitleLabel.TextSize = 14
TitleLabel.TextColor3 = T.text
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Text = "Charles's DevConsole"
TitleLabel.Active = false
TitleLabel.Parent = TitleBar

local function titleButton(glyph, xOffset, hoverBg, hoverText)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 30, 0, 26)
    b.Position = UDim2.new(1, xOffset, 0.5, -13)
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Font = FONT
    b.TextSize = 15
    b.TextColor3 = T.dim
    b.Text = glyph
    b.AutoButtonColor = false
    b.Parent = TitleBar
    corner(b, 6)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1),
            { BackgroundColor3 = hoverBg or T.panel2, TextColor3 = hoverText or T.text,
              BackgroundTransparency = 0 }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
    end)
    return b
end
local CloseBtn = titleButton("✕", -38, T.close, Color3.new(1, 1, 1))
local MinBtn   = titleButton("—", -70, T.panel2, T.text)

-- ---------- Sections ----------
local EditorLabel = Instance.new("TextLabel")
EditorLabel.BackgroundTransparency = 1
EditorLabel.Font = FONT; EditorLabel.TextSize = 11
EditorLabel.TextColor3 = T.dim; EditorLabel.TextXAlignment = Enum.TextXAlignment.Left
EditorLabel.Text = "CODE EDITOR"; EditorLabel.Parent = Main

local EditorFrame = Instance.new("Frame")
EditorFrame.BackgroundColor3 = T.editorBg
EditorFrame.BorderSizePixel  = 0
EditorFrame.Parent = Main
corner(EditorFrame, 8); stroke(EditorFrame, T.borderSoft, 1)

local EditorBox = Instance.new("TextBox")
EditorBox.Name = "Editor"
EditorBox.BackgroundTransparency = 1
EditorBox.Size = UDim2.new(1, -16, 1, -16)
EditorBox.Position = UDim2.new(0, 8, 0, 8)
EditorBox.Font = FONT_MONO; EditorBox.TextSize = 13
EditorBox.TextColor3 = T.text; EditorBox.PlaceholderColor3 = T.faint
EditorBox.PlaceholderText = "-- Paste Luau here, then press Run.   :help for commands."
EditorBox.Text = ""
EditorBox.MultiLine = true; EditorBox.TextWrapped = true
EditorBox.TextXAlignment = Enum.TextXAlignment.Left
EditorBox.TextYAlignment = Enum.TextYAlignment.Top
EditorBox.ClearTextOnFocus = false
EditorBox.RichText = true
EditorBox.Parent = EditorFrame

local EditorBtnRow = Instance.new("Frame")
EditorBtnRow.BackgroundTransparency = 1; EditorBtnRow.Parent = Main

local OutputLabel = Instance.new("TextLabel")
OutputLabel.BackgroundTransparency = 1
OutputLabel.Font = FONT; OutputLabel.TextSize = 11
OutputLabel.TextColor3 = T.dim; OutputLabel.TextXAlignment = Enum.TextXAlignment.Left
OutputLabel.Text = "OUTPUT"; OutputLabel.Parent = Main

local OutputFrame = Instance.new("Frame")
OutputFrame.BackgroundColor3 = T.outputBg
OutputFrame.BorderSizePixel  = 0
OutputFrame.Parent = Main
corner(OutputFrame, 8); stroke(OutputFrame, T.borderSoft, 1)

local OutputScroll = Instance.new("ScrollingFrame")
OutputScroll.BackgroundTransparency = 1
OutputScroll.Size = UDim2.new(1, -12, 1, -12)
OutputScroll.Position = UDim2.new(0, 6, 0, 6)
OutputScroll.BorderSizePixel = 0
OutputScroll.ScrollBarThickness = 4
OutputScroll.ScrollBarImageColor3 = T.panel3
OutputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
OutputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OutputScroll.ScrollingDirection = Enum.ScrollingDirection.Y
OutputScroll.Parent = OutputFrame
local OutputLayout = Instance.new("UIListLayout")
OutputLayout.Padding = UDim.new(0, 2)
OutputLayout.SortOrder = Enum.SortOrder.LayoutOrder
OutputLayout.Parent = OutputScroll

local OutputBtnRow = Instance.new("Frame")
OutputBtnRow.BackgroundTransparency = 1; OutputBtnRow.Parent = Main

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Font = FONT; Status.TextSize = 11
Status.TextColor3 = T.dim
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Center
Status.Text = "Ready"; Status.Parent = Main

local ResizeHandle = Instance.new("TextButton")
ResizeHandle.Name = "ResizeHandle"
ResizeHandle.Size = UDim2.new(0, 32, 0, 32)
ResizeHandle.Position = UDim2.new(1, -38, 1, -38)
ResizeHandle.BackgroundTransparency = 1
ResizeHandle.BorderSizePixel = 0
ResizeHandle.Font = FONT_MONO
ResizeHandle.TextSize = 14
ResizeHandle.TextColor3 = T.faint
ResizeHandle.Text = "◢"
ResizeHandle.AutoButtonColor = false
ResizeHandle.Parent = Main

-- ---------- Buttons ----------
local function makeButton(parent, text, baseBg, textColor)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = baseBg or T.panel2
    b.BorderSizePixel = 0
    b.Font = FONT; b.TextSize = 12
    b.TextColor3 = textColor or T.text
    b.Text = text; b.AutoButtonColor = false
    b.Parent = parent; corner(b, 6)
    local base = b.BackgroundColor3
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1),
            { BackgroundColor3 = base:Lerp(Color3.new(1,1,1), 0.10) }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = base }):Play()
    end)
    return b
end

local EditorButtons, OutputButtons = {}, {}

local function buildButtonRow(row, specs)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = row
    local out = {}
    for i, spec in ipairs(specs) do
        local b = makeButton(row, spec.text, spec.bg, spec.fg)
        b.LayoutOrder = i
        b.Size = UDim2.new(0, spec.w or 72, 1, 0)
        out[spec.key] = b
    end
    return out
end

EditorButtons = buildButtonRow(EditorBtnRow, {
    { key = "run",     text = "Run",     w = 64, bg = T.accent, fg = Color3.new(1,1,1) },
    { key = "library", text = "Library", w = 78 },
    { key = "clear",   text = "Clear",   w = 64 },
    { key = "help",    text = "Help",    w = 64 },
})
OutputButtons = buildButtonRow(OutputBtnRow, {
    { key = "copyLog",   text = "Copy Log",   w = 84 },
    { key = "copyInput", text = "Copy Input", w = 90 },
    { key = "report",    text = "Report",     w = 72 },
    { key = "selftest",  text = "Self-Test",  w = 86 },
    { key = "clearLog",  text = "Clear Log",  w = 86 },
})

-- ---------- Layout ----------
local function getMainSize()
    return Vector2.new(Main.Size.X.Offset, Main.Size.Y.Offset)
end

local function relayout()
    local w, h = getMainSize()
    local pad = 10
    local titleH = 38
    local gap = 6
    local labelH = 14
    local btnH = 30
    local statusH = 18

    TitleBar.Size = UDim2.new(1, 0, 0, titleH)

    local contentX = pad
    local contentY = titleH + gap
    local contentW = w - pad * 2

    local fixedH = labelH + btnH + labelH + btnH + statusH + gap * 6
    local available = math.max(120, (h - titleH - pad - contentY) - fixedH)
    local editorH = math.max(80, math.floor(available * 0.46))
    local outputH = math.max(80, available - editorH)

    local y = contentY
    EditorLabel.Position = UDim2.new(0, contentX, 0, y)
    EditorLabel.Size     = UDim2.new(0, contentW, 0, labelH)
    y = y + labelH + 4

    EditorFrame.Position = UDim2.new(0, contentX, 0, y)
    EditorFrame.Size     = UDim2.new(0, contentW, 0, editorH)
    y = y + editorH + gap

    EditorBtnRow.Position = UDim2.new(0, contentX, 0, y)
    EditorBtnRow.Size     = UDim2.new(0, contentW, 0, btnH)
    y = y + btnH + gap

    OutputLabel.Position = UDim2.new(0, contentX, 0, y)
    OutputLabel.Size     = UDim2.new(0, contentW, 0, labelH)
    y = y + labelH + 4

    OutputFrame.Position = UDim2.new(0, contentX, 0, y)
    OutputFrame.Size     = UDim2.new(0, contentW, 0, outputH)
    y = y + outputH + gap

    OutputBtnRow.Position = UDim2.new(0, contentX, 0, y)
    OutputBtnRow.Size     = UDim2.new(0, contentW, 0, btnH)
    y = y + btnH + gap

    Status.Position = UDim2.new(0, contentX + 2, 0, y)
    Status.Size     = UDim2.new(0, contentW - 4, 0, statusH)

    local function sizeRow(row, count)
        local inner = contentW - (count - 1) * 6
        local cell = math.max(50, math.floor(inner / count))
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") then child.Size = UDim2.new(0, cell, 1, 0) end
        end
    end
    sizeRow(EditorBtnRow, 4)
    sizeRow(OutputBtnRow, 5)
end
relayout()
bootLog("LAYOUT_COMPLETE", "relayout()")

local function onViewportChanged()
    local _, sgSize2 = safeRect()
    local size = getMainSize()
    local maxW = math.max(240, sgSize2.X - 8)
    local maxH = math.max(280, sgSize2.Y - 8)
    local newW = math.min(size.X, maxW)
    local newH = math.min(size.Y, maxH)
    if newW ~= size.X or newH ~= size.Y then
        Main.Size = UDim2.new(0, newW, 0, newH)
    end
    local nx = math.clamp(Main.Position.X.Offset, 0, math.max(0, sgSize2.X - newW))
    local ny = math.clamp(Main.Position.Y.Offset, 0, math.max(0, sgSize2.Y - newH))
    Main.Position = UDim2.new(0, nx, 0, ny)
    relayout()
end
do
    local cam = workspace.CurrentCamera
    if cam then
        local c = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
        onCleanup(function() c:Disconnect() end)
    end
end

-- ============================================================
-- OUTPUT RENDERING
-- ============================================================
local scrollPending = false
local function scrollToBottom()
    if scrollPending then return end
    scrollPending = true
    task.defer(function()
        scrollPending = false
        pcall(function()
            local target = OutputScroll.AbsoluteCanvasSize.Y - OutputScroll.AbsoluteSize.Y
            if target > 0 then
                OutputScroll.CanvasPosition = Vector2.new(0, target)
            end
        end)
    end)
end

local userScrolledUp = false
OutputScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    local maxScroll = OutputScroll.AbsoluteCanvasSize.Y - OutputScroll.AbsoluteSize.Y
    local cur = OutputScroll.CanvasPosition.Y
    userScrolledUp = (maxScroll - cur) > 40
end)

local function timestamp()
    local ok, d = pcall(os.date, "%H:%M:%S")
    if ok and d then return d end
    return string.format("%.2f", os.clock())
end

local function colorForKind(kind)
    if kind == "in"      then return T.accent
    elseif kind == "out" then return T.text
    elseif kind == "err" then return T.err
    elseif kind == "warn"then return T.warn
    elseif kind == "ok"  then return T.ok
    elseif kind == "info"then return T.info
    elseif kind == "dim" then return T.dim
    elseif kind == "sys" then return T.info
    end
    return T.text
end

local function addLine(text, kind, noTs)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.Font = FONT_MONO; lbl.TextSize = 12
    lbl.TextColor3 = colorForKind(kind)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.TextWrapped = true
    lbl.RichText = false
    local prefix = noTs and "" or ("[" .. timestamp() .. "] ")
    lbl.Text = prefix .. tostring(text)
    lbl.Parent = OutputScroll
    return lbl
end

local function record(text, kind, noTs)
    text = tostring(text)
    State.buffer[#State.buffer + 1] = { text = text, kind = kind or "out", ts = timestamp() }
    if kind == "err" then
        State.recentErrors[#State.recentErrors + 1] = text
        if #State.recentErrors > 50 then table.remove(State.recentErrors, 1) end
    elseif kind == "warn" then
        State.recentWarnings[#State.recentWarnings + 1] = text
        if #State.recentWarnings > 50 then table.remove(State.recentWarnings, 1) end
    end
    while #State.buffer > State.maxLines do
        table.remove(State.buffer, 1)
        local old = table.remove(State.lineLabels, 1)
        if old then old:Destroy() end
    end
    local lbl = addLine(text, kind, noTs)
    State.lineLabels[#State.lineLabels + 1] = lbl
    if not userScrolledUp then scrollToBottom() end
end

local function setStatus(text, kind)
    Status.Text = "  " .. text
    Status.TextColor3 = colorForKind(kind or "dim")
end

-- ============================================================
-- PRINT / WARN HOOKS
-- ============================================================
local hooksInstalled = false
do
    local env = (getgenv and getgenv()) or _G
    local prevPrint = env.print
    local prevWarn  = env.warn
    if not prevPrint then prevPrint = print end
    if not prevWarn  then prevWarn  = warn  end

    local function joinArgs(...)
        local n = select("#", ...)
        local out = {}
        for i = 1, n do out[i] = safeToString(select(i, ...)) end
        return table.concat(out, " ")
    end

    local MAX_ECHO = 2000
    local function echoPrefix(line)
        if #line > MAX_ECHO then return "[DC] " .. line:sub(1, MAX_ECHO) .. " …(+" .. (#line - MAX_ECHO) .. ")" end
        return "[DC] " .. line
    end

    local okP = pcall(function()
        env.print = function(...)
            local line = joinArgs(...)
            pcall(record, line, "out")
            pcall(prevPrint, echoPrefix(line))
        end
    end)
    local okW = pcall(function()
        env.warn = function(...)
            local line = joinArgs(...)
            pcall(record, line, "warn")
            pcall(prevWarn, echoPrefix(line))
        end
    end)
    if okP or okW then
        hooksInstalled = true
        onCleanup(function()
            pcall(function() env.print = prevPrint end)
            pcall(function() env.warn  = prevWarn  end)
        end)
    end
end

-- ============================================================
-- SYNTAX HIGHLIGHTING
-- ============================================================
local highlightJob = nil
local isApplyingHighlight = false

local function applyHighlight()
    if isApplyingHighlight then return end
    if not State.highlightEnabled then return end
    if EditorBox:IsFocused() then return end

    isApplyingHighlight = true
    local ok, err = pcall(function()
        local markup = EditorBox.Text
        local plain = stripMarkup(markup)
        local newMarkup = highlight(plain)
        if newMarkup ~= markup then
            local cursorPlain = markupToPlainPos(markup, EditorBox.CursorPosition)
            EditorBox.Text = newMarkup
            EditorBox.CursorPosition = plainToMarkupPos(plain, newMarkup, cursorPlain)
        end
    end)
    isApplyingHighlight = false
    if not ok then
        State.highlightEnabled = false
        pcall(record, "[sys] syntax highlighting disabled (error: " .. tostring(err) .. ")", "warn")
    end
end

local function scheduleHighlight()
    if highlightJob then task.cancel(highlightJob) end
    highlightJob = task.delay(0.35, function()
        highlightJob = nil
        applyHighlight()
    end)
end

EditorBox:GetPropertyChangedSignal("Text"):Connect(function()
    if isApplyingHighlight then return end
    if EditorBox:IsFocused() then return end
    scheduleHighlight()
end)

EditorBox.Focused:Connect(function()
    if highlightJob then task.cancel(highlightJob); highlightJob = nil end
    if not State.highlightEnabled then return end
    if isApplyingHighlight then return end
    isApplyingHighlight = true
    local plain = stripMarkup(EditorBox.Text)
    if plain ~= EditorBox.Text then
        local cur = markupToPlainPos(EditorBox.Text, EditorBox.CursorPosition)
        EditorBox.Text = plain
        EditorBox.CursorPosition = math.clamp(cur, 1, #plain + 1)
    end
    isApplyingHighlight = false
end)

EditorBox.FocusLost:Connect(function()
    task.delay(0.06, applyHighlight)
end)

-- ============================================================
-- DRAG
-- ============================================================
do
    local dragging = false
    local dragStart, startOffX, startOffY

    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart  = input.Position
            startOffX  = Main.Position.X.Offset
            startOffY  = Main.Position.Y.Offset
        end
    end)

    local c1 = UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end

        local delta = input.Position - dragStart
        local _, sgSize2 = safeRect()
        local mw, mh = Main.AbsoluteSize.X, Main.AbsoluteSize.Y
        local nx = math.clamp(startOffX + delta.X, 0, math.max(0, sgSize2.X - mw))
        local ny = math.clamp(startOffY + delta.Y, 0, math.max(0, sgSize2.Y - mh))
        Main.Position = UDim2.new(0, nx, 0, ny)
    end)
    onCleanup(function() c1:Disconnect() end)

    local c2 = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    onCleanup(function() c2:Disconnect() end)
end

-- ============================================================
-- RESIZE
-- ============================================================
do
    local resizing = false
    local resizeStart, sizeStartW, sizeStartH
    local MIN_W, MIN_H = 300, 340

    ResizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeStart = input.Position
            local s = getMainSize()
            sizeStartW, sizeStartH = s.X, s.Y
        end
    end)

    local c1 = UIS.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end

        local delta = input.Position - resizeStart
        local _, sgSize2 = safeRect()
        local maxW = math.max(MIN_W, sgSize2.X - 4)
        local maxH = math.max(MIN_H, sgSize2.Y - 4)
        local nw = math.clamp(sizeStartW + delta.X, MIN_W, maxW)
        local nh = math.clamp(sizeStartH + delta.Y, MIN_H, maxH)
        Main.Size = UDim2.new(0, nw, 0, nh)

        local nx = math.clamp(Main.Position.X.Offset, 0, math.max(0, sgSize2.X - nw))
        local ny = math.clamp(Main.Position.Y.Offset, 0, math.max(0, sgSize2.Y - nh))
        Main.Position = UDim2.new(0, nx, 0, ny)

        relayout()
    end)
    onCleanup(function() c1:Disconnect() end)

    local c2 = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)
    onCleanup(function() c2:Disconnect() end)
end

-- ============================================================
-- PATH RESOLVER
-- ============================================================
local SERVICE_NAMES = {
    Workspace=true,Players=true,Lighting=true,ReplicatedStorage=true,
    ReplicatedFirst=true,ServerScriptService=true,ServerStorage=true,
    StarterGui=true,StarterPack=true,StarterPlayer=true,SoundService=true,
    Chat=true,Teams=true,TextChatService=true,TweenService=true,
    RunService=true,UserInputService=true,ContextActionService=true,
    HttpService=true,CollectionService=true,PathfindingService=true,
    PhysicsService=true,MarketplaceService=true,TeleportService=true,
    DataStoreService=true,MemoryStoreService=true,MessagingService=true,
    LocalizationService=true,PolicyService=true,GuiService=true,
    CoreGui=true,VirtualInputManager=true,VirtualUser=true,
    ScriptContext=true,ContentProvider=true,AssetService=true,
    BadgeService=true,GroupService=true,InsertService=true,
    LogService=true,ProximityPromptService=true,HapticService=true,
    VRService=true,VoiceChatService=true,AnalyticsService=true,
}
local function shortInstancePath(inst)
    if not inst then return "?" end
    local ok, full = pcall(function() return inst:GetFullName() end)
    return ok and full or tostring(inst)
end
local function resolveInstance(path)
    if type(path) ~= "string" or path == "" then return nil, "empty path" end
    path = path:gsub("/", ".")
    local parts = {}
    for p in path:gmatch("[^%.]+") do parts[#parts+1] = p end
    if #parts == 0 then return nil, "empty path" end

    local current
    local first = parts[1]
    if first == "game" then current = game
    elseif first == "workspace" or first == "Workspace" then current = workspace
    elseif first == "Players" or first == "players" then current = Players
    elseif first == "Lighting" then current = Lighting
    elseif SERVICE_NAMES[first] then
        local ok, svc = pcall(function() return game:GetService(first) end)
        if ok and svc then current = svc end
    end
    if not current then
        local ok, svc = pcall(function() return game:GetService(first) end)
        if ok and svc then current = svc else current = game:FindFirstChild(first) end
        if not current then return nil, "cannot resolve first segment '" .. first .. "'" end
    end

    for i = 2, #parts do
        local seg = parts[i]
        if not current then return nil, "path broke at segment " .. i end
        local name, idx = seg:match("^(.-)%[(%d+)%]$")
        if name and name ~= "" then
            local kids = current:GetChildren()
            current = kids[tonumber(idx) + 1]
        elseif seg:match("^%d+$") then
            local kids = current:GetChildren()
            current = kids[tonumber(seg) + 1]
        else
            local next_ = current:FindFirstChild(seg)
            if not next_ then
                return nil, string.format("no child '%s' under %s", seg, shortInstancePath(current))
            end
            current = next_
        end
    end
    return current
end

-- ============================================================
-- COMMANDS
-- ============================================================
local COMMANDS = {}
local function cmdRegister(name, spec) COMMANDS[name:lower()] = spec end

local function treePrefix(prefix, isLast) return prefix .. (isLast and "└── " or "├── ") end
local function buildTree(root, maxDepth, maxNodes, includeClasses)
    local lines, count = {}, 0
    maxDepth = maxDepth or 3
    maxNodes = maxNodes or 250
    local function recurse(node, prefix, depth)
        if count >= maxNodes then return end
        local children = node:GetChildren()
        for i, child in ipairs(children) do
            if count >= maxNodes then
                lines[#lines+1] = prefix .. "└── ...(+more)"
                return
            end
            count = count + 1
            local label = child.Name
            if includeClasses then label = label .. " [" .. child.ClassName .. "]" end
            local isLast = (i == #children)
            lines[#lines+1] = treePrefix(prefix, isLast) .. label
            if depth < maxDepth then
                recurse(child, prefix .. (isLast and "    " or "│   "), depth + 1)
            end
        end
    end
    lines[#lines+1] = includeClasses and (root.Name .. " [" .. root.ClassName .. "]") or root.Name
    recurse(root, "", 1)
    if count >= maxNodes then lines[#lines+1] = "...(truncated at " .. maxNodes .. " nodes)" end
    return lines
end

cmdRegister("help", {
    category = "UTILITY", desc = "Show this help screen or details for a specific command.",
    usage = ":help [command]",
    run = function(args)
        local target = args and trim(args) or ""
        if target ~= "" then
            local c = COMMANDS[target:lower()]
            if not c then record("No such command: " .. target, "err"); return end
            record("COMMAND :" .. target:lower(), "info")
            record("  Category: " .. (c.category or "GENERAL"), "dim")
            record("  Usage:    " .. (c.usage or (":" .. target)), "dim")
            record("  " .. (c.desc or ""), "out")
            return
        end
        local byCategory, order = {}, {}
        for name, c in pairs(COMMANDS) do
            local cat = c.category or "GENERAL"
            if not byCategory[cat] then byCategory[cat] = {}; order[#order+1] = cat end
            byCategory[cat][#byCategory[cat]+1] = { name = name, spec = c }
        end
        table.sort(order)
        record("Charles's DevConsole — command reference", "info")
        record("Type  :help <command>  for details.", "dim")
        for _, cat in ipairs(order) do
            record("", "dim", true)
            record("[" .. cat .. "]", "info")
            local list = byCategory[cat]
            table.sort(list, function(a,b) return a.name < b.name end)
            for _, item in ipairs(list) do
                record(string.format("  %-28s %s",
                    item.spec.usage or (":" .. item.name), item.spec.desc or ""), "out")
            end
        end
    end,
})

cmdRegister("clear", {
    category = "UTILITY", desc = "Clear the output log.", usage = ":clear",
    run = function()
        for _, l in ipairs(State.lineLabels) do l:Destroy() end
        State.lineLabels = {}; State.buffer = {}
        setStatus("Log cleared", "dim")
    end,
})

cmdRegister("history", {
    category = "UTILITY", desc = "Show recent execution history.", usage = ":history",
    run = function()
        if #State.history == 0 then record("(no history)", "dim"); return end
        for i, h in ipairs(State.history) do
            record(string.format("%3d  %s", i, (h:gsub("\n", " ⏎ "))), "out")
        end
    end,
})

cmdRegister("caps", {
    category = "DIAGNOSTICS", desc = "Detect optional executor/runtime capabilities.", usage = ":caps",
    run = function()
        local checks = {
            {"loadstring",loadstring},{"getgenv",getgenv},{"gethui",gethui},
            {"getrawmetatable",getrawmetatable},{"setreadonly",setreadonly},
            {"newcclosure",newcclosure},{"hookfunction",hookfunction},
            {"getnamecallmethod",getnamecallmethod},{"setclipboard",setclipboard},
            {"writefile",writefile},{"readfile",readfile},{"isfile",isfile},
            {"listfiles",listfiles},{"makefolder",makefolder},
            {"identifyexecutor",identifyexecutor},{"getscriptbytecode",getscriptbytecode},
            {"getloadedmodules",getloadedmodules},{"getconnections",getconnections},
            {"firesignal",firesignal},{"firetouchinterest",firetouchinterest},
            {"fireclickdetector",fireclickdetector},{"getnilinstances",getnilinstances},
            {"getinstances",getinstances},{"getreg",getreg},{"getgc",getgc},
            {"getupvalue",getupvalue},{"setupvalue",setupvalue},
            {"getconstants",getconstants},{"getrenv",getrenv},{"getsenv",getsenv},
            {"debug.getinfo",debug and debug.getinfo},{"typeof",typeof},
            {"task.spawn",task and task.spawn},{"task.wait",task and task.wait},
            {"os.clock",os and os.clock},{"os.date",os and os.date},{"os.time",os and os.time},
        }
        local present, missing = {}, {}
        for _, c in ipairs(checks) do
            if c[2] ~= nil then present[#present+1] = c[1] else missing[#missing+1] = c[1] end
        end
        record("Available (" .. #present .. "):", "ok")
        record("  " .. table.concat(present, ", "), "out")
        record("", "dim", true)
        record("Unavailable (" .. #missing .. "):", "warn")
        record("  " .. table.concat(missing, ", "), "dim")
    end,
})

cmdRegister("env", {
    category = "DIAGNOSTICS", desc = "Show environment information (Lua, Roblox, executor).", usage = ":env",
    run = function()
        record("[ Standard Lua ]", "info")
        record("  _VERSION      : " .. tostring(_VERSION or "?"), "out")
        record("  os.clock()    : " .. tostring(os and os.clock and os.clock() or "?"), "out")
        record("  os.time()     : " .. tostring(os and os.time and os.time() or "?"), "out")
        record("", "dim", true)
        record("[ Roblox ]", "info")
        record("  PlaceId       : " .. tostring(game.PlaceId), "out")
        record("  JobId         : " .. tostring(game.JobId), "out")
        record("  PlaceVersion  : " .. tostring(game.PlaceVersion), "out")
        record("  GameId        : " .. tostring(game.GameId), "out")
        record("  CreatorId     : " .. tostring(game.CreatorId), "out")
        record("  CreatorType   : " .. tostring(game.CreatorType), "out")
        local _, sgSize2 = safeRect()
        record("  SafeAreaSize  : " .. tostring(sgSize2), "out")
        record("", "dim", true)
        record("[ Player ]", "info")
        if LP then
            record("  Name          : " .. LP.Name, "out")
            record("  DisplayName   : " .. LP.DisplayName, "out")
            record("  UserId        : " .. tostring(LP.UserId), "out")
            record("  AccountAge    : " .. tostring(LP.AccountAge) .. " days", "out")
        end
        record("", "dim", true)
        record("[ Executor ]", "info")
        if identifyexecutor then
            local ok, name, ver = pcall(identifyexecutor)
            record("  Identified    : " .. tostring(name) .. (ver and (" v" .. tostring(ver)) or ""), "out")
        else
            record("  Identified    : (no identifyexecutor)", "dim")
        end
    end,
})

cmdRegister("players", {
    category = "GAME INFORMATION", desc = "List players with Name, DisplayName, UserId, Character state.",
    usage = ":players",
    run = function()
        local list = Players:GetPlayers()
        record("Players: " .. #list, "info")
        for _, p in ipairs(list) do
            local char = p.Character
            local state = char and "spawned" or "loading"
            local team = p.Team and p.Team.Name or "-"
            local isLocal = (p == LP) and "  <- local" or ""
            record(string.format("  %-24s | %-20s | uid=%-12d | %s | team=%s%s",
                p.Name, p.DisplayName, p.UserId, state, team, isLocal), "out")
        end
    end,
})

cmdRegister("services", {
    category = "GAME INFORMATION", desc = "List services currently present under the DataModel.",
    usage = ":services",
    run = function()
        local services = {}
        for _, v in ipairs(game:GetChildren()) do
            if v:IsA("ServiceProvider") or v.ClassName:match("Service$") then
                services[#services+1] = { name = v.ClassName, inst = v }
            end
        end
        table.sort(services, function(a,b) return a.name < b.name end)
        record("Services present: " .. #services, "info")
        for _, s in ipairs(services) do
            record(string.format("  %-34s children=%d", s.name, #s.inst:GetChildren()), "out")
        end
    end,
})

cmdRegister("remotes", {
    category = "INSPECTION", desc = "List RemoteEvent and RemoteFunction objects visible to the client.",
    usage = ":remotes [search]",
    run = function(args)
        local filter = args and trim(args):lower() or ""
        local found, scanned = {}, 0
        for _, v in ipairs(game:GetDescendants()) do
            scanned = scanned + 1
            if scanned % 2000 == 0 then task.wait() end
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                local full = v:GetFullName()
                if filter == "" or full:lower():find(filter, 1, true) then
                    found[#found+1] = { path = full, cls = v.ClassName }
                end
            end
        end
        table.sort(found, function(a,b) return a.path < b.path end)
        local shown = math.min(#found, 300)
        record(string.format("Remotes found: %d (showing %d)", #found, shown), "info")
        for i = 1, shown do
            local r = found[i]
            record(string.format("  [%s] %s", r.cls, r.path), "out")
        end
        if #found > shown then record("  ...(truncated)", "dim") end
    end,
})

cmdRegister("find", {
    category = "INSPECTION", desc = "Case-insensitive search of Instances by Name or ClassName.",
    usage = ":find <query> [scope] [--limit=N]",
    run = function(args)
        local query, scope, limit = nil, nil, 100
        for token in (args or ""):gmatch("%S+") do
            local l = token:match("^%-%-limit=(%d+)$")
            if l then limit = tonumber(l)
            elseif not query then query = token
            elseif not scope then scope = token end
        end
        if not query or query == "" then record("usage: :find <query> [scope] [--limit=N]", "warn"); return end
        local root
        if scope then
            local r, err = resolveInstance(scope)
            if not r then record("Cannot resolve scope: " .. tostring(err), "err"); return end
            root = r
        else root = game end
        query = query:lower()
        local results, scanned = {}, 0
        for _, v in ipairs(root:GetDescendants()) do
            scanned = scanned + 1
            if scanned % 2000 == 0 then task.wait() end
            if #results >= limit * 3 then break end
            if v.Name:lower():find(query, 1, true) then results[#results+1] = v end
        end
        if #results < limit then
            local seenSet = {}
            for _, v in ipairs(results) do seenSet[v] = true end
            for _, v in ipairs(root:GetDescendants()) do
                if #results >= limit then break end
                if not seenSet[v] and v.ClassName:lower():find(query, 1, true) then
                    results[#results+1] = v; seenSet[v] = true
                end
            end
        end
        record(string.format("Found %d match(es) under %s (scanned %d)",
            #results, shortInstancePath(root), scanned), "info")
        for _, v in ipairs(results) do
            record(string.format("  %s  [%s]", v:GetFullName(), v.ClassName), "out")
        end
    end,
})

cmdRegister("tree", {
    category = "INSPECTION", desc = "Show a depth-limited tree view of an Instance.",
    usage = ":tree <path> [depth]",
    run = function(args)
        local path, depthStr = args:match("^(%S+)%s*(%d*)$")
        if not path or path == "" then record("usage: :tree <path> [depth]", "warn"); return end
        local depth = math.clamp(tonumber(depthStr) or 2, 1, 6)
        local root, err = resolveInstance(path)
        if not root then record("Cannot resolve: " .. tostring(err), "err"); return end
        for _, line in ipairs(buildTree(root, depth, 300, true)) do record(line, "out", true) end
    end,
})

cmdRegister("children", {
    category = "INSPECTION", desc = "List immediate children of an Instance.",
    usage = ":children <path>",
    run = function(args)
        local path = trim(args or "")
        if path == "" then record("usage: :children <path>", "warn"); return end
        local inst, err = resolveInstance(path)
        if not inst then record("Cannot resolve: " .. tostring(err), "err"); return end
        local kids = inst:GetChildren()
        record(string.format("%s — %d children", shortInstancePath(inst), #kids), "info")
        table.sort(kids, function(a,b) return a.Name < b.Name end)
        for _, k in ipairs(kids) do
            record(string.format("  %-36s [%s]", k.Name, k.ClassName), "out")
        end
    end,
})

cmdRegister("inspect", {
    category = "INSPECTION", desc = "Detailed inspection of an Instance.",
    usage = ":inspect <path>",
    run = function(args)
        local path = trim(args or "")
        if path == "" then record("usage: :inspect <path>", "warn"); return end
        local inst, err = resolveInstance(path)
        if not inst then record("Cannot resolve: " .. tostring(err), "err"); return end
        record("Instance: " .. inst:GetFullName(), "info")
        record("  ClassName       : " .. inst.ClassName, "out")
        record("  Name            : " .. inst.Name, "out")
        record("  Parent          : " .. (inst.Parent and inst.Parent:GetFullName() or "<none>"), "out")
        record("  ChildCount      : " .. #inst:GetChildren(), "out")
        local dn = 0
        for _ in ipairs(inst:GetDescendants()) do
            dn = dn + 1; if dn > 5000 then break end
        end
        record("  DescendantCount : " .. (dn > 5000 and "5000+" or tostring(dn)), "out")
        record("  Archivable      : " .. tostring(inst.Archivable), "out")
        local ok, attrs = pcall(function() return inst:GetAttributes() end)
        if ok and attrs and next(attrs) then
            record("  Attributes:", "out")
            local keys = {}
            for k in pairs(attrs) do keys[#keys+1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                record(string.format("    %s = %s", k, serializeValue(attrs[k], { maxDepth = 2 })), "dim")
            end
        end
        local interesting = {}
        local function tryAdd(...)
            for _, prop in ipairs({...}) do
                local okP, val = pcall(function() return inst[prop] end)
                if okP and val ~= nil then interesting[#interesting+1] = { prop, val } end
            end
        end
        tryAdd("Size","Position","Orientation","Anchored","CanCollide","Transparency",
               "Color","Material","Shape","Value","Enabled","Visible","Text","TextSize","Font",
               "Health","MaxHealth","WalkSpeed","JumpPower","Image","ImageColor3",
               "BackgroundColor3","Velocity","AssemblyLinearVelocity","Brightness","Ambient",
               "ClockTime","Volume","SoundId","Playing","Locked","Massless")
        if #interesting > 0 then
            record("  Notable properties:", "out")
            for _, pair in ipairs(interesting) do
                record(string.format("    %-20s = %s", pair[1], serializeValue(pair[2], { maxDepth = 2 })), "dim")
            end
        end
    end,
})

cmdRegister("attrs", {
    category = "INSPECTION", desc = "List attributes of an Instance.", usage = ":attrs <path>",
    run = function(args)
        local inst, err = resolveInstance(trim(args or ""))
        if not inst then record("Cannot resolve: " .. tostring(err), "err"); return end
        local ok, attrs = pcall(function() return inst:GetAttributes() end)
        if not ok or not attrs then
            record("Attributes unavailable for " .. inst:GetFullName(), "warn"); return
        end
        local keys = {}
        for k in pairs(attrs) do keys[#keys+1] = k end
        table.sort(keys)
        record("Attributes of " .. inst:GetFullName() .. " (" .. #keys .. "):", "info")
        for _, k in ipairs(keys) do
            record(string.format("  %s = %s", k, serializeValue(attrs[k], { maxDepth = 3 })), "out")
        end
    end,
})

cmdRegister("scripts", {
    category = "INSPECTION", desc = "List client-visible Script/LocalScript/ModuleScript instances.",
    usage = ":scripts [search]",
    run = function(args)
        local filter = args and trim(args):lower() or ""
        local found, scanned = {}, 0
        for _, v in ipairs(game:GetDescendants()) do
            scanned = scanned + 1
            if scanned % 2000 == 0 then task.wait() end
            if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("ModuleScript") then
                local full = v:GetFullName()
                if filter == "" or full:lower():find(filter, 1, true) then found[#found+1] = v end
            end
        end
        table.sort(found, function(a,b) return a:GetFullName() < b:GetFullName() end)
        record("Scripts found: " .. #found, "info")
        for i = 1, math.min(#found, 200) do
            local v = found[i]
            record(string.format("  [%s] %s", v.ClassName, v:GetFullName()), "out")
        end
        if #found > 200 then record("  ...(truncated)", "dim") end
    end,
})

cmdRegister("egg", {
    category = "INSPECTION", desc = "Search for egg-related instances (or a specific term).",
    usage = ":egg [term]",
    run = function(args)
        local term = trim(args or "")
        if term == "" then term = "egg" end
        local q = term:lower()
        local found, scanned = {}, 0
        for _, v in ipairs(game:GetDescendants()) do
            scanned = scanned + 1
            if scanned % 2000 == 0 then task.wait() end
            if v.Name:lower():find(q, 1, true) then
                found[#found+1] = v
                if #found >= 300 then break end
            end
        end
        record(string.format("Matches for %q: %d", term, #found), "info")
        for _, v in ipairs(found) do
            record(string.format("  %s [%s]", v:GetFullName(), v.ClassName), "out")
        end
    end,
})

-- ============================================================
-- SPY
-- ============================================================
local SPY_THROTTLE = 30
local spyCount, spyWindowStart = 0, os.clock()
local function spyAllowed()
    local now = os.clock()
    if now - spyWindowStart > 1 then spyCount = 0; spyWindowStart = now end
    spyCount = spyCount + 1
    return spyCount <= SPY_THROTTLE
end

cmdRegister("spy", {
    category = "OBSERVATION",
    desc = "Enable/disable remote observation (logs FireServer/InvokeServer).",
    usage = ":spy on|off|status",
    run = function(args)
        local sub = trim(args or ""):lower()
        if sub == "on" then
            if State.spy.active and State.spy.unmount then
                pcall(State.spy.unmount)
            end
            if not getrawmetatable or not setreadonly or not newcclosure then
                record("Spy requires getrawmetatable + setreadonly + newcclosure.", "err")
                return
            end
            local mt = getrawmetatable(game)
            if not mt then record("Spy: no metatable.", "err"); return end
            local oldNamecall = mt.__namecall
            if not oldNamecall then record("Spy: no __namecall.", "err"); return end

            local ourFn = newcclosure(function(self, ...)
                local method = getnamecallmethod and getnamecallmethod() or ""
                if method == "FireServer" or method == "InvokeServer" or method == "Fire" then
                    if spyAllowed() then
                        pcall(function()
                            local a = { ... }
                            local parts = {}
                            for i = 1, math.min(#a, 6) do
                                parts[#parts+1] = formatValueBrief(a[i])
                            end
                            local target = (typeof(self) == "Instance") and self:GetFullName() or tostring(self)
                            record(string.format("[spy] %s %s (%d) %s",
                                method, target, #a, table.concat(parts, ", ")), "info")
                        end)
                    end
                end
                return oldNamecall(self, ...)
            end)

            local okSet = pcall(function()
                setreadonly(mt, false)
                mt.__namecall = ourFn
                setreadonly(mt, true)
            end)
            if not okSet then
                record("Spy: failed to install __namecall hook.", "err")
                return
            end

            State.spy.active = true
            State.spy.unmount = function()
                if not State.spy.active then return end
                pcall(function()
                    setreadonly(mt, false)
                    if mt.__namecall == ourFn then
                        mt.__namecall = oldNamecall
                    end
                    setreadonly(mt, true)
                end)
                State.spy.active = false
                State.spy.unmount = nil
            end
            record("Spy enabled.", "ok")

        elseif sub == "off" then
            if State.spy.unmount then
                pcall(State.spy.unmount)
                record("Spy disabled.", "ok")
            else
                record("Spy is not active.", "dim")
            end

        elseif sub == "status" then
            record("Spy: " .. (State.spy.active and "ACTIVE" or "inactive"), "info")

        else
            record("usage: :spy on|off|status", "warn")
        end
    end,
})
onCleanup(function()
    if State.spy.unmount then pcall(State.spy.unmount) end
end)

-- ============================================================
-- REPORT
-- ============================================================
cmdRegister("report", {
    category = "DIAGNOSTICS", desc = "Generate a full diagnostic report and copy it to the clipboard.",
    usage = ":report",
    run = function()
        local out = {}
        local function w(line) out[#out+1] = line end
        w("=== Charles's DevConsole Diagnostic Report ===")
        w("Version    : " .. CONSOLE_VERSION)
        w("Timestamp  : " .. tostring(os.date and os.date("%Y-%m-%d %H:%M:%S") or "?"))
        w("")
        w("--- Environment ---")
        w("PlaceId       : " .. tostring(game.PlaceId))
        w("JobId         : " .. tostring(game.JobId))
        w("PlaceVersion  : " .. tostring(game.PlaceVersion))
        w("GameId        : " .. tostring(game.GameId))
        w("CreatorId     : " .. tostring(game.CreatorId))
        w("CreatorType   : " .. tostring(game.CreatorType))
        local _, sgSize2 = safeRect()
        w("SafeAreaSize  : " .. tostring(sgSize2))
        w("")
        w("--- Local Player ---")
        if LP then
            w("Name          : " .. LP.Name)
            w("DisplayName   : " .. LP.DisplayName)
            w("UserId        : " .. tostring(LP.UserId))
            w("AccountAge    : " .. tostring(LP.AccountAge))
            w("Character     : " .. (LP.Character and shortInstancePath(LP.Character) or "<none>"))
        end
        w("")
        w("--- Capabilities (present) ---")
        local caps = {
            loadstring=loadstring,getgenv=getgenv,gethui=gethui,
            getrawmetatable=getrawmetatable,setreadonly=setreadonly,
            newcclosure=newcclosure,hookfunction=hookfunction,
            getnamecallmethod=getnamecallmethod,setclipboard=setclipboard,
            identifyexecutor=identifyexecutor,getconnections=getconnections,
            firetouchinterest=firetouchinterest,getnilinstances=getnilinstances,
        }
        local present = {}
        for k,v in pairs(caps) do if v ~= nil then present[#present+1] = k end end
        table.sort(present)
        w("  " .. table.concat(present, ", "))
        w("")
        w("--- Players ---")
        for _, p in ipairs(Players:GetPlayers()) do
            w(string.format("  %s | %s | uid=%d | char=%s",
                p.Name, p.DisplayName, p.UserId, p.Character and "spawned" or "none"))
        end
        w("")
        w("--- Remote Inventory (client-visible, capped) ---")
        local remotes = {}
        local scanned = 0
        for _, v in ipairs(game:GetDescendants()) do
            scanned = scanned + 1
            if scanned % 2000 == 0 then task.wait() end
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                remotes[#remotes+1] = string.format("  [%s] %s", v.ClassName, v:GetFullName())
                if #remotes >= 120 then break end
            end
        end
        for _, line in ipairs(remotes) do w(line) end
        if #remotes >= 120 then w("  ...(truncated at 120)") end
        w("")
        w("--- Recent Errors (" .. #State.recentErrors .. ") ---")
        for _, e in ipairs(State.recentErrors) do w("  " .. e) end
        w("")
        w("--- Recent Warnings (" .. #State.recentWarnings .. ") ---")
        for _, e in ipairs(State.recentWarnings) do w("  " .. e) end
        w("")
        w("--- Execution History (" .. #State.history .. ") ---")
        for i, h in ipairs(State.history) do
            w(string.format("  [%d] %s", i, (h:gsub("\n", " ⏎ "):sub(1, 200))))
        end
        w("")
        w("=== End of Report ===")

        local text = table.concat(out, "\n")
        record("Diagnostic report generated (" .. #text .. " bytes).", "ok")
        if copyToClipboard(text) then
            record("Report copied to clipboard.", "ok")
        else
            record("Clipboard unavailable — showing report inline:", "warn")
            for _, line in ipairs(out) do record(line, "out", true) end
        end
    end,
})

-- ============================================================
-- SELF-TEST
-- ============================================================
cmdRegister("selftest", {
    category = "DIAGNOSTICS", desc = "Run a self-test of the console's own components.", usage = ":selftest",
    run = function()
        local pass, fail, skip = 0, 0, 0
        local function report(name, ok, detail)
            if ok == true then pass = pass + 1
                record(string.format("  [PASS] %s%s", name, detail and (" — " .. detail) or ""), "ok")
            elseif ok == false then fail = fail + 1
                record(string.format("  [FAIL] %s%s", name, detail and (" — " .. detail) or ""), "err")
            else skip = skip + 1
                record(string.format("  [SKIP] %s%s", name, detail and (" — " .. detail) or ""), "dim")
            end
        end
        record("Charles's DevConsole self-test", "info")
        report("GUI root present", ScreenGui and ScreenGui.Parent ~= nil)
        report("Main frame present", Main and Main.Parent ~= nil)
        report("Editor box present", EditorBox and EditorBox.Parent ~= nil)
        report("Output scroll present", OutputScroll and OutputScroll.Parent ~= nil)
        report("Status label present", Status and Status.Parent ~= nil)
        report("Resize handle present", ResizeHandle and ResizeHandle.Parent ~= nil)
        report("Relayout executes without error", (pcall(relayout)))
        local original = EditorBox.Text
        local okEdit = pcall(function()
            EditorBox.Text = "-- selftest"
            assert(stripMarkup(EditorBox.Text) == "-- selftest", "roundtrip mismatch")
        end)
        report("Editor text round-trip", okEdit)
        pcall(function() EditorBox.Text = original end)
        local okHL = pcall(function()
            local markup = highlight("local x = 1 -- hi")
            assert(markup:find("font", 1, true), "no markup produced")
            assert(stripMarkup(markup):find("local x = 1", 1, true), "stripped text mismatch")
        end)
        report("Syntax highlighter", okHL)
        local okSer = pcall(function()
            local s = serializeValue({ a = 1, b = "x", c = { d = true } })
            assert(s:find("a = 1", 1, true), "serializer missing key")
        end)
        report("Value serializer", okSer)
        local okPath = pcall(function()
            assert(resolveInstance("game") == game, "game resolve failed")
            assert(resolveInstance("workspace") == workspace, "workspace resolve failed")
        end)
        report("Path resolver", okPath)
        local loader = loadstring or load
        if loader then
            local chunk = loader("return 1 + 1", "=selftest")
            local okRun, res = pcall(chunk)
            report("Execution engine returns value", okRun and res == 2, "returned " .. tostring(res))
            local chunk2 = loader("error('boom')", "=selftest")
            local okRun2, err = pcall(chunk2)
            report("Error handling catches runtime error", (not okRun2) and tostring(err):find("boom") ~= nil)
        else
            report("Execution engine returns value", nil, "no loadstring/load")
            report("Error handling catches runtime error", nil)
        end
        if setclipboard or toclipboard or setrbxclipboard or writeclipboard then
            report("Clipboard support", copyToClipboard("devconsole-selftest"))
        else
            report("Clipboard support", nil, "no clipboard function")
        end
        report("Command dispatcher present", type(COMMANDS) == "table" and COMMANDS.help ~= nil)
        report("print/warn hooks installed", hooksInstalled == true)
        report("Report generator present", type(COMMANDS.report) == "table")
        report("Cleanup registry has entries", #_cleanup > 0, tostring(#_cleanup) .. " functions")
        record("", "dim", true)
        record(string.format("Self-test complete: %d passed, %d failed, %d skipped",
            pass, fail, skip), fail == 0 and "ok" or "warn")
    end,
})

COMMANDS.eggs = COMMANDS.egg
COMMANDS.capabilities = COMMANDS.caps
COMMANDS.environment = COMMANDS.env

-- ============================================================
-- EXECUTION
-- ============================================================
local function pushHistory(code)
    if #State.history > 0 and State.history[#State.history] == code then return end
    State.history[#State.history + 1] = code
    if #State.history > 100 then table.remove(State.history, 1) end
    State.historyIndex = #State.history + 1
end

local function runCode(code)
    code = stripMarkup(code or EditorBox.Text)
    if trim(code) == "" then setStatus("Nothing to run", "warn"); return end

    if code:sub(1, 1) == ":" then
        local name, args = code:match("^:(%S+)%s*(.*)$")
        if not name then record("Malformed command.  Type  :help.", "err"); return end
        local c = COMMANDS[name:lower()]
        if not c then record("Unknown command: :" .. name .. "  (type :help)", "err"); return end
        pushHistory(code)
        record(code, "in")
        State.execCount = State.execCount + 1
        local ok, err = pcall(c.run, args or "")
        if not ok then
            record("[command error] " .. tostring(err), "err")
            setStatus("Command error", "err")
        else
            setStatus("Command complete", "ok")
        end
        return
    end

    pushHistory(code)
    record(code, "in")
    State.execCount = State.execCount + 1

    local loader = loadstring or load
    if not loader then
        record("[error] no loadstring/load available in this executor", "err")
        setStatus("No loader", "err"); return
    end

    local t0 = os.clock()
    local chunk, compileErr = loader(code, "=DevConsole")
    if not chunk then
        record("[compile error] " .. tostring(compileErr), "err")
        setStatus("Compile error", "err"); return
    end
    local ok, result = pcall(chunk)
    local dt = (os.clock() - t0) * 1000
    if not ok then
        local err = tostring(result)
        record("[runtime error] " .. err, "err")
        if debug and debug.traceback then
            local okTb, tb = pcall(debug.traceback, err, 2)
            if okTb and tb then
                for line in tostring(tb):gmatch("[^\n]+") do record("  " .. line, "dim") end
            end
        end
        setStatus(string.format("Error (%.1f ms)", dt), "err")
    else
        if result ~= nil then
            record("[returned] " .. serializeValue(result, { maxDepth = 3 }), "ok")
        end
        record(string.format("[done in %.1f ms]", dt), "dim")
        setStatus(string.format("Done in %.1f ms", dt), "ok")
    end
end

-- ============================================================
-- LIBRARY PANEL
-- ============================================================
local PRESETS = {
    { name="Dump Remotes", cat="Diagnostics", code=[[-- Dump all RemoteEvents and RemoteFunctions visible to the client
for _, v in ipairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
        print(v:GetFullName(), "[" .. v.ClassName .. "]")
    end
end]] },
    { name="Dump Services", cat="Diagnostics", code=[[for _, v in ipairs(game:GetChildren()) do
    if v.ClassName:match("Service$") then
        print(v.ClassName, "#children=" .. #v:GetChildren())
    end
end]] },
    { name="Place / Job Info", cat="Diagnostics", code=[[print("PlaceId:", game.PlaceId)
print("JobId:", game.JobId)
print("PlaceVersion:", game.PlaceVersion)
print("CreatorId:", game.CreatorId, "CreatorType:", game.CreatorType)]] },
    { name="Players", cat="Diagnostics", code=[[for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    print(p.Name, p.DisplayName, p.UserId, p.Character and "spawned" or "none")
end]] },
    { name="Search 'egg'", cat="Diagnostics", code=[[for _, v in ipairs(game:GetDescendants()) do
    if v.Name:lower():find("egg", 1, true) then
        print(v:GetFullName(), "[" .. v.ClassName .. "]")
    end
end]] },
    { name="Walk Workspace (1 level)", cat="Inspection", code=[[for _, v in ipairs(workspace:GetChildren()) do
    print(v.Name, "[" .. v.ClassName .. "]", "#children=" .. #v:GetChildren())
end]] },
    { name="Walk ReplicatedStorage", cat="Inspection", code=[[for _, v in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
    print(v.Name, "[" .. v.ClassName .. "]")
end]] },
    { name="LocalPlayer Character", cat="Inspection", code=[[local lp = game:GetService("Players").LocalPlayer
print("Name:", lp.Name)
print("Character:", lp.Character)
if lp.Character then
    for _, v in ipairs(lp.Character:GetChildren()) do
        print(" ", v.Name, "[" .. v.ClassName .. "]")
    end
end]] },
    { name="Test: print / warn / error / return", cat="Testing", code=[[print("hello from print")
warn("hello from warn")
local ok, err = pcall(function() error("intentional error") end)
print("pcall ok?", ok, "err:", err)
return "returned value"]] },
    { name="Test: timing / performance", cat="Testing", code=[[local t = os.clock()
local s = 0
for i = 1, 200000 do s = s + i end
print("sum:", s, "elapsed:", (os.clock() - t) * 1000, "ms")]] },
    { name="Observe: check a remote", cat="Observation", code=[[local RS = game:GetService("ReplicatedStorage")
local remote = RS:FindFirstChild("SomeRemote")
if remote and remote:IsA("RemoteEvent") then
    print("Remote exists:", remote:GetFullName())
else
    warn("Edit the preset to point at your remote.") end]] },
    { name="Observe: inspect attributes", cat="Observation", code=[[local inst = workspace
local attrs = inst:GetAttributes()
for k, v in pairs(attrs) do print(k, v) end]] },
}

local LibraryPanel = Instance.new("Frame")
LibraryPanel.Name = "LibraryPanel"
LibraryPanel.Visible = false
LibraryPanel.BackgroundColor3 = T.panel
LibraryPanel.BorderSizePixel = 0
LibraryPanel.ZIndex = 40
LibraryPanel.Parent = Main
corner(LibraryPanel, 8); stroke(LibraryPanel, T.border, 1)

local LibTabs = Instance.new("Frame")
LibTabs.Size = UDim2.new(1, 0, 0, 30)
LibTabs.BackgroundColor3 = T.panel2
LibTabs.BorderSizePixel = 0
LibTabs.ZIndex = 41
LibTabs.Parent = LibraryPanel
corner(LibTabs, 8)

local LibClose = Instance.new("TextButton")
LibClose.Size = UDim2.new(0, 26, 0, 22)
LibClose.Position = UDim2.new(1, -30, 0, 4)
LibClose.BackgroundColor3 = T.panel3
LibClose.BorderSizePixel = 0
LibClose.Font = FONT; LibClose.TextSize = 12
LibClose.TextColor3 = T.dim; LibClose.Text = "✕"
LibClose.AutoButtonColor = false
LibClose.ZIndex = 43; LibClose.Parent = LibTabs
corner(LibClose, 6)
LibClose.MouseButton1Click:Connect(function() LibraryPanel.Visible = false end)

local LibTabRow = Instance.new("Frame")
LibTabRow.Size = UDim2.new(1, -36, 1, 0)
LibTabRow.BackgroundTransparency = 1
LibTabRow.ZIndex = 42; LibTabRow.Parent = LibTabs
padding(LibTabRow, 4, 4, 4, 4)
local LibTabLayout = Instance.new("UIListLayout")
LibTabLayout.FillDirection = Enum.FillDirection.Horizontal
LibTabLayout.Padding = UDim.new(0, 4)
LibTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
LibTabLayout.Parent = LibTabRow

local LibBody = Instance.new("ScrollingFrame")
LibBody.Position = UDim2.new(0, 0, 0, 30)
LibBody.Size = UDim2.new(1, 0, 1, -30)
LibBody.BackgroundTransparency = 1
LibBody.BorderSizePixel = 0
LibBody.ScrollBarThickness = 4
LibBody.ScrollBarImageColor3 = T.panel3
LibBody.CanvasSize = UDim2.new(0, 0, 0, 0)
LibBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
LibBody.ScrollingDirection = Enum.ScrollingDirection.Y
LibBody.ZIndex = 41; LibBody.Parent = LibraryPanel
padding(LibBody, 6, 6, 6, 6)
local LibBodyLayout = Instance.new("UIListLayout")
LibBodyLayout.Padding = UDim.new(0, 3)
LibBodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
LibBodyLayout.Parent = LibBody

local function clearLibBody()
    for _, c in ipairs(LibBody:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
end

local function addLibItem(text, subtext, onClick)
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 32)
    item.BackgroundColor3 = T.panel2
    item.BackgroundTransparency = 0.4
    item.BorderSizePixel = 0
    item.Font = FONT; item.TextSize = 12
    item.TextColor3 = T.text
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Text = "  " .. text .. (subtext and ("   —   " .. subtext) or "")
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.AutoButtonColor = false
    item.ZIndex = 42; item.Parent = LibBody
    corner(item, 5)
    item.MouseEnter:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), { BackgroundTransparency = 0 }):Play()
    end)
    item.MouseLeave:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), { BackgroundTransparency = 0.4 }):Play()
    end)
    item.MouseButton1Click:Connect(onClick)
    return item
end

local function renderTab(tab)
    clearLibBody()
    if tab == "Presets" then
        local byCat, order = {}, {}
        for _, p in ipairs(PRESETS) do
            local cat = p.cat or "General"
            if not byCat[cat] then byCat[cat] = {}; order[#order+1] = cat end
            byCat[cat][#byCat[cat]+1] = p
        end
        table.sort(order)
        for _, cat in ipairs(order) do
            local head = Instance.new("TextLabel")
            head.BackgroundTransparency = 1
            head.Size = UDim2.new(1, 0, 0, 20)
            head.Font = FONT; head.TextSize = 11
            head.TextColor3 = T.dim
            head.TextXAlignment = Enum.TextXAlignment.Left
            head.Text = "  " .. cat:upper()
            head.Parent = LibBody
            for _, p in ipairs(byCat[cat]) do
                addLibItem(p.name, nil, function()
                    EditorBox.Text = p.code
                    LibraryPanel.Visible = false
                    applyHighlight()
                    setStatus("Loaded preset: " .. p.name, "ok")
                end)
            end
        end
    elseif tab == "History" then
        if #State.history == 0 then addLibItem("(no history yet)", nil, function() end)
        else
            for i = #State.history, 1, -1 do
                local code = State.history[i]
                addLibItem(code:gsub("\n", " ⏎ "):sub(1, 80), nil, function()
                    EditorBox.Text = code
                    LibraryPanel.Visible = false
                    applyHighlight()
                    setStatus("Loaded history item #" .. i, "ok")
                end)
            end
        end
    elseif tab == "Commands" then
        local byCat, order = {}, {}
        for name, c in pairs(COMMANDS) do
            local cat = c.category or "GENERAL"
            if not byCat[cat] then byCat[cat] = {}; order[#order+1] = cat end
            byCat[cat][#byCat[cat]+1] = { name = name, spec = c }
        end
        table.sort(order)
        for _, cat in ipairs(order) do
            local head = Instance.new("TextLabel")
            head.BackgroundTransparency = 1
            head.Size = UDim2.new(1, 0, 0, 20)
            head.Font = FONT; head.TextSize = 11
            head.TextColor3 = T.dim
            head.TextXAlignment = Enum.TextXAlignment.Left
            head.Text = "  " .. cat
            head.Parent = LibBody
            local list = byCat[cat]
            table.sort(list, function(a,b) return a.name < b.name end)
            for _, item in ipairs(list) do
                addLibItem(item.spec.usage or (":" .. item.name), nil, function()
                    EditorBox.Text = item.spec.usage or (":" .. item.name)
                    LibraryPanel.Visible = false
                    applyHighlight()
                    setStatus("Loaded command: " .. item.name, "ok")
                end)
            end
        end
    end
end

local LibTabButtons = {}
local function makeLibTab(label)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 90, 1, 0)
    b.BackgroundColor3 = T.panel3
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Font = FONT; b.TextSize = 12
    b.TextColor3 = T.dim; b.Text = label
    b.AutoButtonColor = false
    b.ZIndex = 43; b.Parent = LibTabRow
    corner(b, 5)
    b.MouseButton1Click:Connect(function()
        for _, other in pairs(LibTabButtons) do
            other.BackgroundTransparency = 1
            other.TextColor3 = T.dim
        end
        b.BackgroundTransparency = 0
        b.TextColor3 = T.text
        renderTab(label)
    end)
    LibTabButtons[label] = b
end
makeLibTab("Presets"); makeLibTab("History"); makeLibTab("Commands")
LibTabButtons["Presets"].BackgroundTransparency = 0
LibTabButtons["Presets"].TextColor3 = T.text
renderTab("Presets")

local function placeLibraryPanel()
    local w = Main.AbsoluteSize.X
    local h = Main.AbsoluteSize.Y
    local panelW = math.min(360, w - 30)
    local panelH = math.min(320, h - 120)
    LibraryPanel.Size = UDim2.new(0, panelW, 0, panelH)
    local targetX = math.max(10, w - panelW - 10)
    local targetY = math.max(50, math.floor(h * 0.25))
    LibraryPanel.Position = UDim2.new(0, targetX, 0, targetY)
end
placeLibraryPanel()

-- ============================================================
-- BUTTON WIRING
-- ============================================================
EditorButtons.run.MouseButton1Click:Connect(function() runCode() end)
EditorButtons.clear.MouseButton1Click:Connect(function()
    EditorBox.Text = ""; setStatus("Editor cleared", "dim")
end)
EditorButtons.help.MouseButton1Click:Connect(function()
    LibraryPanel.Visible = false
    runCode(":help")
end)
EditorButtons.library.MouseButton1Click:Connect(function()
    LibraryPanel.Visible = not LibraryPanel.Visible
    if LibraryPanel.Visible then placeLibraryPanel() end
end)

OutputButtons.copyLog.MouseButton1Click:Connect(function()
    if #State.buffer == 0 then setStatus("Log is empty", "warn"); return end
    local out = {}
    for _, e in ipairs(State.buffer) do out[#out+1] = "[" .. e.ts .. "] " .. e.text end
    if copyToClipboard(table.concat(out, "\n")) then
        setStatus(string.format("Copied %d lines to clipboard", #State.buffer), "ok")
    else
        setStatus("Clipboard unavailable", "err")
    end
end)
OutputButtons.copyInput.MouseButton1Click:Connect(function()
    local plain = stripMarkup(EditorBox.Text)
    if plain == "" then setStatus("Editor is empty", "warn"); return end
    if copyToClipboard(plain) then setStatus("Editor copied to clipboard", "ok")
    else setStatus("Clipboard unavailable", "err") end
end)
OutputButtons.report.MouseButton1Click:Connect(function()
    local c = COMMANDS.report
    local ok, err = pcall(c.run, "")
    if not ok then record("[report error] " .. tostring(err), "err") end
end)
OutputButtons.selftest.MouseButton1Click:Connect(function()
    local c = COMMANDS.selftest
    local ok, err = pcall(c.run, "")
    if not ok then record("[selftest error] " .. tostring(err), "err") end
end)
OutputButtons.clearLog.MouseButton1Click:Connect(function()
    for _, l in ipairs(State.lineLabels) do l:Destroy() end
    State.lineLabels = {}; State.buffer = {}
    setStatus("Log cleared", "dim")
end)

-- ============================================================
-- TITLE BUTTONS
-- ============================================================
local RestoreBtn = Instance.new("TextButton")
RestoreBtn.Name = "RestoreBtn"
RestoreBtn.Size = UDim2.new(0, 52, 0, 52)
RestoreBtn.Position = UDim2.new(0, 20, 0.5, -26)
RestoreBtn.BackgroundColor3 = T.accent
RestoreBtn.BorderSizePixel = 0
RestoreBtn.Font = FONT; RestoreBtn.TextSize = 14
RestoreBtn.TextColor3 = Color3.new(1, 1, 1)
RestoreBtn.Text = "DC"
RestoreBtn.Visible = false
RestoreBtn.AutoButtonColor = false
RestoreBtn.Parent = ScreenGui
corner(RestoreBtn, 26); stroke(RestoreBtn, T.border, 1)
RestoreBtn.MouseEnter:Connect(function()
    TweenService:Create(RestoreBtn, TweenInfo.new(0.1), { BackgroundColor3 = T.accentHover }):Play()
end)
RestoreBtn.MouseLeave:Connect(function()
    TweenService:Create(RestoreBtn, TweenInfo.new(0.1), { BackgroundColor3 = T.accent }):Play()
end)

MinBtn.MouseButton1Click:Connect(function()
    Main.Visible = false; RestoreBtn.Visible = true
end)
RestoreBtn.MouseButton1Click:Connect(function()
    Main.Visible = true; RestoreBtn.Visible = false
end)
CloseBtn.MouseButton1Click:Connect(function() runCleanup() end)

-- ============================================================
-- KEYBINDS
-- ============================================================
do
    local conn = UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.F2 then
            if Main.Visible then Main.Visible = false; RestoreBtn.Visible = true
            else Main.Visible = true; RestoreBtn.Visible = false end
        elseif input.KeyCode == Enum.KeyCode.F5 then
            runCode()
        elseif input.KeyCode == Enum.KeyCode.Up then
            if EditorBox:IsFocused() and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
                if #State.history > 0 then
                    State.historyIndex = math.max(1, State.historyIndex - 1)
                    EditorBox.Text = State.history[State.historyIndex] or ""
                    applyHighlight()
                end
            end
        elseif input.KeyCode == Enum.KeyCode.Down then
            if EditorBox:IsFocused() and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
                if #State.history > 0 then
                    State.historyIndex = math.min(#State.history + 1, State.historyIndex + 1)
                    EditorBox.Text = State.history[State.historyIndex] or ""
                    applyHighlight()
                end
            end
        end
    end)
    onCleanup(function() conn:Disconnect() end)
end

-- ============================================================
-- INIT
-- ============================================================
record("Charles's DevConsole v" .. CONSOLE_VERSION .. " ready.", "ok")
record("F2: toggle · F5: run · Ctrl+↑/↓: history", "dim")
record("Type  :help  in the editor and press Run, or click Help.", "dim")
record("Editor supports Luau syntax highlighting (auto, debounced).", "dim")
if not hooksInstalled then
    record("[warn] print/warn hooks not installed — user output may not be captured", "warn")
end
setStatus("Ready", "dim")

bootLog("INITIALIZATION_COMPLETE", "v" .. CONSOLE_VERSION)

-- Deferred visibility verification. Runs after one frame so ScreenGui has had
-- a chance to lay out. Reports to the boot channel, not to the (possibly
-- non-rendering) console.
task.defer(function()
    task.wait(0.2)
    local issues = {}
    if not ScreenGui.Enabled then issues[#issues+1] = "ScreenGui.Enabled=false" end
    if not ScreenGui.Parent then issues[#issues+1] = "ScreenGui has no parent" end
    if not Main.Visible then issues[#issues+1] = "Main.Visible=false" end
    local msz = Main.AbsoluteSize
    if msz.X <= 0 or msz.Y <= 0 then
        issues[#issues+1] = "Main.AbsoluteSize=" .. tostring(msz)
    end
    if #issues == 0 then
        bootLog("MAIN_VISIBLE", tostring(Main.AbsoluteSize) .. " @ " .. tostring(Main.AbsolutePosition))
    else
        bootFail("MAIN_VISIBLE", table.concat(issues, "; "))
    end
end)

task.defer(function()
    pcall(relayout)
    pcall(placeLibraryPanel)
end)