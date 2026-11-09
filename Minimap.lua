local L = ChessLocale or setmetatable({}, { __index = function(_, k) return k end })

_G.ChessAddon = _G.ChessAddon or {}
local API = _G.ChessAddon

local ChessMinimap = {}
local minimapBtn = nil

local btnAngle = 210

local function updatePosition()
    if not minimapBtn then return end
    local rad    = math.rad(btnAngle)
    local radius = 80
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function ChessMinimap:Initialize()
    if minimapBtn then return end

    if ChessDB and ChessDB.settings and ChessDB.settings.minimapAngle then
        btnAngle = ChessDB.settings.minimapAngle
    end

    minimapBtn = CreateFrame("Button", "ChessMinimapButton", Minimap)
    minimapBtn:SetSize(31, 31)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapBtn:RegisterForDrag("LeftButton")
    minimapBtn:SetMovable(true)

    local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_06")
    minimapBtn.icon = icon

    local overlay = minimapBtn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local ring = minimapBtn:CreateTexture(nil, "OVERLAY")
    ring:SetSize(52, 52)
    ring:SetPoint("CENTER", 0, 1)
    ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    ring:SetBlendMode("ADD")
    ring:SetVertexColor(1, 0.85, 0.15)
    ring:Hide()
    minimapBtn.ring = ring

    local glow = minimapBtn:CreateTexture(nil, "OVERLAY")
    glow:SetSize(26, 26)
    glow:SetPoint("CENTER", 0, 1)
    glow:SetTexture("Interface\\Cooldown\\star4")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.9, 0.2)
    glow:SetAlpha(0)
    minimapBtn.glow = glow

    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    minimapBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if API.ToggleBoard then API.ToggleBoard() end
        elseif button == "RightButton" then
            if API.ShowBoard then API.ShowBoard() end
        end
    end)

    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFFFFD700"..L["MM_TITLE"].."|r", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["MM_LEFT"], 1, 1, 1)
        GameTooltip:AddLine(L["MM_RIGHT"], 1, 1, 1)
        GameTooltip:AddLine(L["MM_DRAG"], 1, 1, 1)
        GameTooltip:AddLine(" ")
        local st = API.GetState and API.GetState() or nil
        if st and st.active then
            local turn = st.myTurn and ("|cFF00FF00"..L["MM_YOUR_TURN"].."|r")
                                    or  ("|cFFAAAAAA"..L["MM_OPP_TURN"].."|r")
            GameTooltip:AddLine(string.format(L["MM_IN_GAME"], turn), 1, 1, 1)
        else
            GameTooltip:AddLine("|cFFAAAAAA"..L["MM_NO_GAME"].."|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)

    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapBtn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = GetCursorPosition()
            local scale  = Minimap:GetEffectiveScale()
            mx = mx / scale
            my = my / scale
            local cx, cy = Minimap:GetCenter()
            local rad = math.atan2(my - cy, mx - cx)
            btnAngle  = math.deg(rad)
            updatePosition()
        end)
    end)

    minimapBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        if ChessDB then
            ChessDB.settings = ChessDB.settings or {}
            ChessDB.settings.minimapAngle = btnAngle
        end
    end)

    updatePosition()
    minimapBtn:Show()

    local flash = CreateFrame("Frame")
    flash.t = 0
    flash.left = 0
    flash:Hide()
    flash:SetScript("OnUpdate", function(self, dt)
        self.t = self.t + dt
        self.left = self.left - dt

        local phase = (self.t * 2) % 1
        local a = phase < 0.5 and (phase * 2) or (2 - phase * 2)
        if minimapBtn.glow then minimapBtn.glow:SetAlpha(a) end
        if self.left <= 0 then
            if minimapBtn.glow then minimapBtn.glow:SetAlpha(0) end
            self:Hide()
        end
    end)
    minimapBtn.flashFrame = flash

    API.onUpdate = function() ChessMinimap:UpdateIcon() end
    API.Alert = function()
        flash.t = 0
        flash.left = 4
        flash:Show()
        PlaySound(8959)
    end
    ChessMinimap:UpdateIcon()
end

function ChessMinimap:UpdateIcon()
    if not minimapBtn or not minimapBtn.icon then return end
    local st = API.GetState and API.GetState() or nil
    if st and st.active and st.myTurn then
        minimapBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_04")
    else
        minimapBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_06")
    end

    if minimapBtn.ring then
        local pending = API.PendingPvPTurn and API.PendingPvPTurn()
        if pending then minimapBtn.ring:Show() else minimapBtn.ring:Hide() end
    end
end

function ChessMinimap:Show()
    if minimapBtn then minimapBtn:Show() end
end

function ChessMinimap:Hide()
    if minimapBtn then minimapBtn:Hide() end
end

function ChessMinimap:Toggle()
    if not minimapBtn then return end
    if minimapBtn:IsShown() then minimapBtn:Hide() else minimapBtn:Show() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "Chess" then
        ChessMinimap:Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
