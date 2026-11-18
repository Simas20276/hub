--[[
    Universal Hub  |  works on most Roblox games (client-side, no game-specific remotes)
    Toggle menu: RightShift
    Tabs: Movement / Combat / Visuals / Players / Misc
]]

local env = (getgenv and getgenv()) or _G
if env.UHUnload then pcall(env.UHUnload) end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")
local VirtualUser      = game:GetService("VirtualUser")

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse  = LP:GetMouse()

-- flags: se crashar, deixa ambas em false e liga uma de cada vez para descobrir qual causa
local USE_DRAWING = false -- circulo do FOV + tracers (biblioteca Drawing)
local USE_GETHUI  = false -- true = UI via gethui(), false = CoreGui

local hasDrawing = USE_DRAWING and pcall(function() Drawing.new("Line"):Remove() end)

--// connections / cleanup -------------------------------------------------
local conns = {}
local function bind(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end

--// state -----------------------------------------------------------------
local S = {
    -- movement
    speed = false, speedVal = 50,
    cfspeed = false, cfVal = 60,
    jump = false, jumpVal = 100,
    infjump = false,
    fly = false, flyVal = 80,
    noclip = false,
    clicktp = false,
    grav = false, gravVal = 50,
    -- combat
    aim = false, aimHold = true, aimPart = "Head", aimSmooth = 0.35, aimPred = 0,
    fovR = 150, fovShow = true, aimTeam = true, aimWall = true, aimDist = 1000,
    -- visuals
    esp = false, espNames = true, espChams = true, espTracers = false,
    espTeam = false, espTeamColor = true, espDist = 2000,
    fullbright = false, nofog = false,
    fovOn = false, fovVal = 90, unlockZoom = false,
    -- misc
    afk = true,
}

local defaults = {
    gravity = Workspace.Gravity,
    walk = 16, jp = 50,
    light = {
        Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
        Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
    },
    fov = Camera and Camera.FieldOfView or 70,
    zoom = LP.CameraMaxZoomDistance,
}

--// helpers ---------------------------------------------------------------
local function getChar(p) return (p or LP).Character end
local function getHum(p) local c = getChar(p) return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot(p) local c = getChar(p) return c and c:FindFirstChild("HumanoidRootPart") end
local function sameTeam(p) return p.Team ~= nil and p.Team == LP.Team end

do
    local h = getHum()
    if h then defaults.walk, defaults.jp = h.WalkSpeed, h.JumpPower end
end

--// UI --------------------------------------------------------------------
local function new(class, props, children)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = o end
    return o
end

local C = {
    bg = Color3.fromRGB(22, 22, 28), panel = Color3.fromRGB(30, 30, 38),
    item = Color3.fromRGB(40, 40, 50), accent = Color3.fromRGB(130, 90, 255),
    text = Color3.fromRGB(235, 235, 240), dim = Color3.fromRGB(150, 150, 165),
}

local gui = new("ScreenGui", {
    Name = "UH_" .. HttpService:GenerateGUID(false):sub(1, 8),
    ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
})
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
print("[UH] a iniciar...")
do
    local mounted = false
    if USE_GETHUI and gethui then
        mounted = pcall(function() gui.Parent = gethui() end) and gui.Parent ~= nil
    end
    if not mounted then
        mounted = pcall(function() gui.Parent = game:GetService("CoreGui") end) and gui.Parent ~= nil
    end
    if not mounted then
        gui.Parent = LP:WaitForChild("PlayerGui")
    end
    print("[UH] UI montada em: " .. gui:GetFullName())
end

local main = new("Frame", {
    Size = UDim2.fromOffset(560, 390), Position = UDim2.new(0.5, -280, 0.5, -195),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Parent = gui,
}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) })

local top = new("Frame", {
    Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, BorderSizePixel = 0, Parent = main,
}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) })
new("TextLabel", {
    Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
    Text = "Universal Hub  -  RightShift to hide", TextColor3 = C.text, Font = Enum.Font.GothamBold,
    TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = top,
})

-- drag
do
    local dragging, startPos, startInput
    bind(top.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startInput = true, main.Position, i.Position
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local tabList = new("Frame", {
    Size = UDim2.new(0, 120, 1, -42), Position = UDim2.fromOffset(6, 38),
    BackgroundTransparency = 1, Parent = main,
}, { new("UIListLayout", { Padding = UDim.new(0, 4) }) })

local content = new("Frame", {
    Size = UDim2.new(1, -140, 1, -42), Position = UDim2.fromOffset(132, 38),
    BackgroundTransparency = 1, Parent = main,
})

local tabs, currentTab = {}, nil
local function selectTab(name)
    for n, t in pairs(tabs) do
        t.page.Visible = (n == name)
        t.btn.BackgroundColor3 = (n == name) and C.accent or C.item
    end
    currentTab = name
end

local function addTab(name)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.item, Text = name, TextColor3 = C.text,
        Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false, Parent = tabList,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    local page = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
        ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = content,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingRight = UDim.new(0, 6) }),
    })
    tabs[name] = { btn = btn, page = page }
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    if not currentTab then selectTab(name) end
    return page
end

local function Toggle(page, text, default, cb)
    local state = default
    local f = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.item, Text = "", AutoButtonColor = false, Parent = page,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    new("TextLabel", {
        Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1,
        Text = text, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = f,
    })
    local box = new("Frame", {
        Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -28, 0.5, -9),
        BackgroundColor3 = state and C.accent or C.bg, BorderSizePixel = 0, Parent = f,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 4) }) })
    local function set(v)
        state = v
        box.BackgroundColor3 = v and C.accent or C.bg
        task.spawn(cb, v)
    end
    f.MouseButton1Click:Connect(function() set(not state) end)
    if default then task.spawn(cb, true) end
    return set
end

local function Slider(page, text, min, max, default, cb, step)
    step = step or 1
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.item, Parent = page,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    local label = new("TextLabel", {
        Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 4), BackgroundTransparency = 1,
        Text = text .. ": " .. tostring(default), TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = f,
    })
    local bar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 6), Position = UDim2.fromOffset(10, 32), BackgroundColor3 = C.bg,
        BorderSizePixel = 0, Parent = f,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local fill = new("Frame", {
        Size = UDim2.fromScale((default - min) / (max - min), 1), BackgroundColor3 = C.accent,
        BorderSizePixel = 0, Parent = bar,
    }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    local dragging = false
    local function setX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = min + (max - min) * rel
        v = math.floor(v / step + 0.5) * step
        v = math.clamp(v, min, max)
        fill.Size = UDim2.fromScale((v - min) / (max - min), 1)
        label.Text = text .. ": " .. tostring(v)
        cb(v)
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setX(i.Position.X)
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setX(i.Position.X)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function Button(page, text, cb)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.item, Text = text, TextColor3 = C.text,
        Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = true, Parent = page,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    b.MouseButton1Click:Connect(function() task.spawn(cb) end)
end

local function Dropdown(page, text, options, default, cb)
    local idx = table.find(options, default) or 1
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.item, Text = text .. ": " .. options[idx],
        TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 13, AutoButtonColor = true, Parent = page,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    b.MouseButton1Click:Connect(function()
        idx = idx % #options + 1
        b.Text = text .. ": " .. options[idx]
        cb(options[idx])
    end)
end

bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end)

--// MOVEMENT --------------------------------------------------------------
local flyBV, flyBG
local function stopFly()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local h = getHum()
    if h then h.PlatformStand = false end
end

bind(RunService.Heartbeat, function(dt)
    local h, r = getHum(), getRoot()
    if not (h and r) then return end

    if S.speed then h.WalkSpeed = S.speedVal end
    if S.jump then h.UseJumpPower = true h.JumpPower = S.jumpVal end
    if S.cfspeed and h.MoveDirection.Magnitude > 0 then
        r.CFrame = r.CFrame + h.MoveDirection * S.cfVal * dt
    end
    if S.grav then Workspace.Gravity = S.gravVal end
end)

bind(RunService.Stepped, function()
    if S.noclip then
        local c = getChar()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end
end)

bind(RunService.RenderStepped, function()
    Camera = Workspace.CurrentCamera
    local h, r = getHum(), getRoot()
    if S.fly and h and r then
        if not (flyBV and flyBV.Parent) then
            flyBV = new("BodyVelocity", { MaxForce = Vector3.one * 9e9, Velocity = Vector3.zero, Parent = r })
        end
        if not (flyBG and flyBG.Parent) then
            flyBG = new("BodyGyro", { MaxTorque = Vector3.one * 9e9, P = 9e4, CFrame = r.CFrame, Parent = r })
        end
        h.PlatformStand = true
        local cf, d = Camera.CFrame, Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then d = d + cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then d = d - cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then d = d + cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then d = d - cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then d = d + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then d = d - Vector3.new(0, 1, 0) end
        flyBV.Velocity = d.Magnitude > 0 and d.Unit * S.flyVal or Vector3.zero
        flyBG.CFrame = cf
    end
end)

bind(UIS.JumpRequest, function()
    if S.infjump then
        local h = getHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

bind(UIS.InputBegan, function(i, gp)
    if gp or not S.clicktp then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        local r = getRoot()
        if r and Mouse.Hit then r.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0)) end
    end
end)

local pMove = addTab("Movement")
Toggle(pMove, "Speed (WalkSpeed)", false, function(v)
    S.speed = v
    if not v then local h = getHum() if h then h.WalkSpeed = defaults.walk end end
end)
Slider(pMove, "Walk speed", 16, 300, S.speedVal, function(v) S.speedVal = v end)
Toggle(pMove, "CFrame speed", false, function(v) S.cfspeed = v end)
Slider(pMove, "CFrame speed value", 10, 300, S.cfVal, function(v) S.cfVal = v end)
Toggle(pMove, "Jump power", false, function(v)
    S.jump = v
    if not v then local h = getHum() if h then h.JumpPower = defaults.jp end end
end)
Slider(pMove, "Jump power value", 50, 400, S.jumpVal, function(v) S.jumpVal = v end)
Toggle(pMove, "Infinite jump", false, function(v) S.infjump = v end)
Toggle(pMove, "Fly (WASD / Space / Shift)", false, function(v)
    S.fly = v
    if not v then stopFly() end
end)
Slider(pMove, "Fly speed", 10, 300, S.flyVal, function(v) S.flyVal = v end)
Toggle(pMove, "Noclip", false, function(v) S.noclip = v end)
Toggle(pMove, "Ctrl + Click teleport", false, function(v) S.clicktp = v end)
Toggle(pMove, "Custom gravity", false, function(v)
    S.grav = v
    if not v then Workspace.Gravity = defaults.gravity end
end)
Slider(pMove, "Gravity", 0, 300, S.gravVal, function(v) S.gravVal = v end)

--// COMBAT (aimbot) -------------------------------------------------------
local fovCircle
if hasDrawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
    fovCircle.Visible = false
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function visible(part, char)
    rayParams.FilterDescendantsInstances = { getChar() or Instance.new("Folder"), Camera }
    local origin = Camera.CFrame.Position
    local res = Workspace:Raycast(origin, part.Position - origin, rayParams)
    return res == nil or res.Instance:IsDescendantOf(char)
end

local function getTarget()
    local best, bestD
    local mpos = UIS:GetMouseLocation()
    local myRoot = getRoot()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and not (S.aimTeam and sameTeam(p)) then
            local c = p.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local part = c and (c:FindFirstChild(S.aimPart) or c:FindFirstChild("HumanoidRootPart"))
            if part and h and h.Health > 0 then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - mpos).Magnitude
                    local inRange = (not myRoot) or (myRoot.Position - part.Position).Magnitude <= S.aimDist
                    if d <= S.fovR and inRange and (not bestD or d < bestD) and (not S.aimWall or visible(part, c)) then
                        best, bestD = part, d
                    end
                end
            end
        end
    end
    return best
end

bind(RunService.RenderStepped, function()
    if fovCircle then
        fovCircle.Visible = S.aim and S.fovShow
        fovCircle.Radius = S.fovR
        fovCircle.Position = UIS:GetMouseLocation()
    end
    if not S.aim then return end
    if S.aimHold and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
    local t = getTarget()
    if t then
        local pos = t.Position + t.AssemblyLinearVelocity * S.aimPred
        Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, pos), S.aimSmooth)
    end
end)

local pCombat = addTab("Combat")
Toggle(pCombat, "Aimbot", false, function(v) S.aim = v end)
Toggle(pCombat, "Hold right mouse to aim", true, function(v) S.aimHold = v end)
Dropdown(pCombat, "Aim part", { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }, "Head", function(v) S.aimPart = v end)
Slider(pCombat, "Smoothness (1 = instant)", 0.05, 1, S.aimSmooth, function(v) S.aimSmooth = v end, 0.05)
Slider(pCombat, "Prediction", 0, 0.3, 0, function(v) S.aimPred = v end, 0.01)
Slider(pCombat, "FOV radius", 20, 600, S.fovR, function(v) S.fovR = v end)
Slider(pCombat, "Max distance", 50, 3000, S.aimDist, function(v) S.aimDist = v end, 50)
Toggle(pCombat, "Show FOV circle", true, function(v) S.fovShow = v end)
Toggle(pCombat, "Team check", true, function(v) S.aimTeam = v end)
Toggle(pCombat, "Wall check", true, function(v) S.aimWall = v end)

--// VISUALS (ESP) --------------------------------------------------------
local esp = {}

local function clearESP(p)
    local e = esp[p]
    if not e then return end
    for k, o in pairs(e) do
        if k ~= "char" then
            pcall(function() if o.Remove then o:Remove() else o:Destroy() end end)
        end
    end
    esp[p] = nil
end

local function buildESP(p, c)
    local head = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
    local hl = new("Highlight", {
        Adornee = c, FillTransparency = 0.6, OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = gui,
    })
    local bb = new("BillboardGui", {
        Adornee = head, AlwaysOnTop = true, Size = UDim2.fromOffset(200, 40),
        StudsOffset = Vector3.new(0, 2.5, 0), Parent = gui,
    })
    local lbl = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1),
        TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBold, TextSize = 13, Parent = bb,
    })
    local e = { char = c, hl = hl, bb = bb, lbl = lbl }
    if hasDrawing then
        local ln = Drawing.new("Line")
        ln.Thickness = 1
        ln.Visible = false
        e.tracer = ln
    end
    esp[p] = e
    return e
end

bind(RunService.RenderStepped, function()
    local myRoot = getRoot()
    local vp = Camera.ViewportSize
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local c = p.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local dist = (r and myRoot) and (r.Position - myRoot.Position).Magnitude or 0
            local show = S.esp and r and h and h.Health > 0 and dist <= S.espDist and not (S.espTeam and sameTeam(p))

            if not show then
                local e = esp[p]
                if e then
                    e.hl.Enabled, e.bb.Enabled = false, false
                    if e.tracer then e.tracer.Visible = false end
                end
            else
                local e = esp[p]
                if e and e.char ~= c then clearESP(p) e = nil end
                e = e or buildESP(p, c)
                local col = (S.espTeamColor and p.Team) and p.TeamColor.Color or Color3.fromRGB(255, 70, 70)
                e.hl.Enabled = S.espChams
                e.hl.FillColor, e.hl.OutlineColor = col, col
                e.bb.Enabled = S.espNames
                e.lbl.TextColor3 = col
                e.lbl.Text = string.format("%s\n[%dm | %d HP]", p.DisplayName, dist, h.Health)
                if e.tracer then
                    local sp, on = Camera:WorldToViewportPoint(r.Position)
                    e.tracer.Visible = S.espTracers and on
                    e.tracer.Color = col
                    e.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                    e.tracer.To = Vector2.new(sp.X, sp.Y)
                end
            end
        end
    end
end)

bind(Players.PlayerRemoving, clearESP)

-- world visuals
bind(RunService.RenderStepped, function()
    if S.fullbright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
    end
    if S.nofog then Lighting.FogEnd = 9e9 end
    if S.fovOn then Camera.FieldOfView = S.fovVal end
    if S.unlockZoom then LP.CameraMaxZoomDistance = 1000 LP.CameraMode = Enum.CameraMode.Classic end
end)

local function restoreLighting()
    for k, v in pairs(defaults.light) do Lighting[k] = v end
end

local pVis = addTab("Visuals")
Toggle(pVis, "ESP", false, function(v) S.esp = v end)
Toggle(pVis, "ESP chams (highlight)", true, function(v) S.espChams = v end)
Toggle(pVis, "ESP names / distance / health", true, function(v) S.espNames = v end)
Toggle(pVis, "ESP tracers", false, function(v) S.espTracers = v end)
Toggle(pVis, "ESP hide teammates", false, function(v) S.espTeam = v end)
Toggle(pVis, "ESP use team colors", true, function(v) S.espTeamColor = v end)
Slider(pVis, "ESP max distance", 100, 5000, S.espDist, function(v) S.espDist = v end, 100)
Toggle(pVis, "Fullbright", false, function(v)
    S.fullbright = v
    if not v then restoreLighting() end
end)
Toggle(pVis, "No fog", false, function(v)
    S.nofog = v
    if not v then Lighting.FogEnd = defaults.light.FogEnd end
end)
Toggle(pVis, "Custom FOV", false, function(v)
    S.fovOn = v
    if not v then Camera.FieldOfView = defaults.fov end
end)
Slider(pVis, "Field of view", 30, 120, S.fovVal, function(v) S.fovVal = v end)
Toggle(pVis, "Unlock camera zoom", false, function(v)
    S.unlockZoom = v
    if not v then LP.CameraMaxZoomDistance = defaults.zoom end
end)

--// PLAYERS ---------------------------------------------------------------
local function others()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and getRoot(p) then t[#t + 1] = p end
    end
    return t
end

local function nearest()
    local me, best, bd = getRoot(), nil, math.huge
    if not me then return end
    for _, p in ipairs(others()) do
        local d = (getRoot(p).Position - me.Position).Magnitude
        if d < bd then best, bd = p, d end
    end
    return best
end

local specIdx = 0
local function spectate(step)
    local list = others()
    if #list == 0 then return end
    specIdx = (specIdx + step - 1) % #list + 1
    local h = getHum(list[specIdx])
    if h then Camera.CameraSubject = h end
end

local pPlr = addTab("Players")
Button(pPlr, "Teleport to nearest player", function()
    local p, r = nearest(), getRoot()
    if p and r then r.CFrame = getRoot(p).CFrame * CFrame.new(0, 0, 3) end
end)
Button(pPlr, "Teleport to random player", function()
    local list, r = others(), getRoot()
    if #list > 0 and r then r.CFrame = getRoot(list[math.random(#list)]).CFrame * CFrame.new(0, 0, 3) end
end)
Button(pPlr, "Spectate next", function() spectate(1) end)
Button(pPlr, "Spectate previous", function() spectate(-1) end)
Button(pPlr, "Stop spectating", function()
    local h = getHum()
    if h then Camera.CameraSubject = h end
end)

--// MISC ------------------------------------------------------------------
bind(LP.Idled, function()
    if S.afk then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

local function serverHop()
    local ok, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
    end)
    if not ok or not data or not data.data then return end
    local pool = {}
    for _, s in ipairs(data.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers then pool[#pool + 1] = s.id end
    end
    if #pool > 0 then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, pool[math.random(#pool)], LP)
    end
end

local unload
local pMisc = addTab("Misc")
Toggle(pMisc, "Anti-AFK", true, function(v) S.afk = v end)
Button(pMisc, "Reset character", function()
    local h = getHum()
    if h then h.Health = 0 end
end)
Button(pMisc, "Rejoin server", function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
end)
Button(pMisc, "Server hop", serverHop)
Button(pMisc, "Unload hub", function() unload() end)

--// unload ----------------------------------------------------------------
unload = function()
    for k, v in pairs(S) do if type(v) == "boolean" then S[k] = false end end
    stopFly()
    for p in pairs(esp) do clearESP(p) end
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    restoreLighting()
    Workspace.Gravity = defaults.gravity
    LP.CameraMaxZoomDistance = defaults.zoom
    if Camera then Camera.FieldOfView = defaults.fov end
    local h = getHum()
    if h then
        h.WalkSpeed, h.JumpPower, h.PlatformStand = defaults.walk, defaults.jp, false
        Camera.CameraSubject = h
    end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
    env.UHUnload = nil
end
env.UHUnload = unload
print("[UH] carregado. RightShift para mostrar/esconder o menu.")
