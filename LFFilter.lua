-- LFFilter: class/role filters built into the WoW Forever Group Finder (Browse tab).
--
-- How it works: Blizzard's Browse tab (Blizzard_GroupFinder_VanillaStyle) builds its
-- list by calling LFGBrowseUtil_SortSearchResults(results) and then drawing `results`.
-- We hook that function and remove the listings that don't match your filters, so the
-- normal list (with its own Invite / Send Message buttons) only shows the people you want.
-- A filter panel is docked to the right side of the Group Finder window.

local ADDON_NAME = ...
local LFG_ADDON = "Blizzard_GroupFinder_VanillaStyle"

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ROLES = {
    { key = "TANK",    label = "Tank",   atlas = "groupfinder-icon-role-large-tank",
      coords = { 0, 19/64, 22/64, 41/64 } },
    { key = "HEALER",  label = "Healer", atlas = "groupfinder-icon-role-large-heal",
      coords = { 20/64, 39/64, 1/64, 20/64 } },
    { key = "DAMAGER", label = "DPS",    atlas = "groupfinder-icon-role-large-dps",
      coords = { 20/64, 39/64, 22/64, 41/64 } },
}

-- Layout
local PANEL_W = 214
local PAD = 14
local X_OFFSET = 46 -- clears the Group Finder's side tabs
local ROLE_ICON = 40
local CLASS_ICON = 34
local GOLD = { 1, 0.82, 0 }

local DB
local stats = { shown = 0, total = 0 }
local setupDone = false
local panel, miniButton, statusText, roleHint, classHint
local controls = {} -- everything with a :Sync() method

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------

local function CountSet(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function ClassMatch(classFile)
    if not next(DB.classes) then return true end
    return classFile ~= nil and DB.classes[classFile] == true
end

local function RoleMatch(roles)
    if not next(DB.roles) then return true end
    for role in pairs(roles) do
        if DB.roles[role] then return true end
    end
    return false
end

local function FiltersActive()
    return DB.soloOnly or next(DB.classes) ~= nil or next(DB.roles) ~= nil
end

local function ActiveFilterCount()
    return CountSet(DB.classes) + CountSet(DB.roles) + (DB.soloOnly and 1 or 0)
end

local function ResultMatches(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then return false end
    if info.hasSelf then return true end -- always keep your own listing

    local numMembers = info.numMembers or 1

    if numMembers > 1 then
        if DB.soloOnly then return false end
        -- Groups: keep if any member matches.
        for i = 1, numMembers do
            local m = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
            if m then
                local roles = {}
                if m.assignedRole then roles[m.assignedRole] = true end
                if ClassMatch(m.classFilename) and RoleMatch(roles) then return true end
            end
        end
        return false
    end

    -- Solo player: use the roles they ticked when listing.
    local m = C_LFGList.GetSearchResultPlayerInfo(resultID, 1) or C_LFGList.GetSearchResultLeaderInfo(resultID)
    if not m then
        return next(DB.classes) == nil and next(DB.roles) == nil
    end
    local roles = {}
    local lfg = m.lfgRoles
    if lfg then
        if lfg.tank then roles.TANK = true end
        if lfg.healer then roles.HEALER = true end
        if lfg.dps then roles.DAMAGER = true end
    end
    if m.assignedRole and m.assignedRole ~= "NONE" then roles[m.assignedRole] = true end
    return ClassMatch(m.classFilename) and RoleMatch(roles)
end

-- Post-hook on LFGBrowseUtil_SortSearchResults: trims the results table in place.
local function FilterResults(results)
    if not DB or type(results) ~= "table" then return end
    stats.total = #results
    if FiltersActive() then
        for i = #results, 1, -1 do
            local ok, keep = pcall(ResultMatches, results[i])
            if ok and not keep then
                table.remove(results, i)
            end
        end
    end
    stats.shown = #results
end

---------------------------------------------------------------------------
-- Status text / hints
---------------------------------------------------------------------------

local function UpdateStatus()
    if statusText then
        if stats.total == 0 then
            statusText:SetText("|cff888888Search to see players|r")
        elseif FiltersActive() then
            local color = stats.shown > 0 and "ffffffff" or "ffff5555"
            statusText:SetFormattedText("Showing |c%s%d|r of %d", color, stats.shown, stats.total)
        else
            statusText:SetFormattedText("%d listings |cff888888(no filters)|r", stats.total)
        end
    end

    if roleHint then
        local n = CountSet(DB.roles)
        roleHint:SetText(n == 0 and "Any role" or (n .. " selected"))
    end
    if classHint then
        local n = CountSet(DB.classes)
        classHint:SetText(n == 0 and "Any class" or (n .. " selected"))
    end

    if miniButton then
        local n = ActiveFilterCount()
        miniButton:SetText(n > 0 and string.format("Filters (%d)", n) or "Filters")
    end
end

-- Post-hook on LFGBrowseFrame:UpdateResults: fixes the empty-list message.
local function AfterUpdateResults(browse)
    if not browse.searching and not browse.searchFailed
        and (browse.totalResults or 0) > 0 and #(browse.results or {}) == 0 then
        browse.NoResultsFound:SetText("No players match your filters.")
        browse.NoResultsFound:Show()
    end
    UpdateStatus()
end

-- Re-run Blizzard's list update so filter changes apply immediately.
local function ReapplyFilters()
    for _, c in ipairs(controls) do c:Sync() end
    if LFGBrowseFrame and LFGBrowseFrame:IsShown() and LFGBrowseFrame.UpdateResultList then
        LFGBrowseFrame:UpdateResultList()
    end
    UpdateStatus()
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function PlayToggleSound(on)
    if SOUNDKIT and PlaySound then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

local function HasAtlas(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function ShowTooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    for i = 1, select("#", ...) do
        GameTooltip:AddLine((select(i, ...)), nil, nil, nil, true)
    end
    GameTooltip:Show()
end

local function AddDivider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD, y)
    line:SetPoint("TOPRIGHT", -PAD, y)
    return line
end

local function AddHeader(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", PAD, y)
    fs:SetText(text)
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -PAD, y - 2)
    return fs, hint
end

-- Square icon that toggles on/off. Selected = full colour with a coloured frame;
-- unselected = greyed out.
local function MakeIconToggle(parent, size, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)

    b.frame = b:CreateTexture(nil, "BACKGROUND")
    b.frame:SetPoint("TOPLEFT", -2, 2)
    b.frame:SetPoint("BOTTOMRIGHT", 2, -2)
    local c = opts.color or GOLD
    b.frame:SetColorTexture(c[1], c[2], c[3], 0.9)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    if opts.atlas and HasAtlas(opts.atlas) then
        b.icon:SetAtlas(opts.atlas)
    elseif opts.file then
        b.icon:SetTexture(opts.file)
        if opts.coords then b.icon:SetTexCoord(unpack(opts.coords)) end
    end

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")

    if opts.label then
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
        b.label:SetText(opts.label)
    end

    b.Sync = function(self)
        local on = opts.get()
        self.frame:SetShown(on)
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.45)
        if self.label then
            if on then
                local lc = opts.labelColor or GOLD
                self.label:SetTextColor(lc[1], lc[2], lc[3])
            else
                self.label:SetTextColor(0.55, 0.55, 0.55)
            end
        end
    end

    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function()
        local on
        if IsShiftKeyDown() and opts.only then
            opts.only()
            on = true
        else
            on = not opts.get()
            opts.set(on or nil)
        end
        PlayToggleSound(on)
        ReapplyFilters()
    end)
    b:SetScript("OnEnter", function(self) ShowTooltip(self, opts.tooltipTitle, unpack(opts.tooltipLines or {})) end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    table.insert(controls, b)
    return b
end

-- Small text button used for "clear" links next to section headers.
local function MakeLinkButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetSize(math.max(32, fs:GetStringWidth() + 6), 14)
    b:SetNormalFontObject("GameFontNormalSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetScript("OnClick", function() PlayToggleSound(false); onClick() end)
    return b
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function SetCollapsed(collapsed)
    DB.collapsed = collapsed
    panel:SetShown(not collapsed)
    miniButton:SetShown(collapsed)
    UpdateStatus()
end

-- Position is stored as an offset from the Group Finder's top-right corner,
-- so the panel follows the Group Finder wherever it opens.
local function ApplyPosition()
    local x, y = X_OFFSET, -10
    if DB.pos then x, y = DB.pos.x, DB.pos.y end
    for _, f in ipairs({ panel, miniButton }) do
        if f then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", LFGParentFrame, "TOPRIGHT", x, y)
        end
    end
end

local function MakeDraggable(f)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        local left, top = self:GetLeft(), self:GetTop()
        local pRight, pTop = LFGParentFrame:GetRight(), LFGParentFrame:GetTop()
        if left and top and pRight and pTop then
            DB.pos = { x = left - pRight, y = top - pTop }
        end
        ApplyPosition()
    end)
end

local function BuildPanel()
    panel = CreateFrame("Frame", "LFFilterPanel", LFGBrowseFrame, "BackdropTemplate")
    panel:SetWidth(PANEL_W)
    panel:EnableMouse(true)
    MakeDraggable(panel)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.94)
    panel:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)

    -- Title bar ----------------------------------------------------------
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -12)
    title:SetText("Filters")

    local dragHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dragHint:SetPoint("LEFT", title, "RIGHT", 8, -1)
    dragHint:SetText("drag to move")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() PlayToggleSound(false); SetCollapsed(true) end)

    local y = -38
    AddDivider(panel, y)

    -- Roles ---------------------------------------------------------------
    y = y - 10
    local _, rHint = AddHeader(panel, "Roles", y)
    roleHint = rHint
    local clearRoles = MakeLinkButton(panel, "clear", function() wipe(DB.roles); ReapplyFilters() end)
    clearRoles:SetPoint("RIGHT", roleHint, "LEFT", -6, 0)

    y = y - 22
    local roleSpacing = (PANEL_W - 2 * PAD) / #ROLES
    for i, r in ipairs(ROLES) do
        local b = MakeIconToggle(panel, ROLE_ICON, {
            atlas = r.atlas,
            file = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES",
            coords = r.coords,
            label = r.label,
            get = function() return DB.roles[r.key] end,
            set = function(v) DB.roles[r.key] = v end,
            only = function() wipe(DB.roles); DB.roles[r.key] = true end,
            tooltipTitle = r.label,
            tooltipLines = { "Show players who listed as " .. r.label .. ".",
                             "|cff888888Shift-click to pick only this role.|r" },
        })
        local cx = PAD + roleSpacing * (i - 0.5)
        b:SetPoint("TOP", panel, "TOPLEFT", cx, y)
    end
    y = y - ROLE_ICON - 26

    AddDivider(panel, y)

    -- Classes -------------------------------------------------------------
    y = y - 10
    local _, cHint = AddHeader(panel, "Classes", y)
    classHint = cHint
    local clearClasses = MakeLinkButton(panel, "clear", function() wipe(DB.classes); ReapplyFilters() end)
    clearClasses:SetPoint("RIGHT", classHint, "LEFT", -6, 0)

    y = y - 22
    local cols = 3
    local colSpacing = (PANEL_W - 2 * PAD) / cols
    local rowHeight = CLASS_ICON + 22
    for i, classFile in ipairs(CLASSES) do
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        local color = cc and { cc.r, cc.g, cc.b } or GOLD
        local b = MakeIconToggle(panel, CLASS_ICON, {
            atlas = "groupfinder-icon-class-" .. string.lower(classFile),
            file = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
            coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile],
            label = name,
            color = color,
            labelColor = color,
            get = function() return DB.classes[classFile] end,
            set = function(v) DB.classes[classFile] = v end,
            only = function() wipe(DB.classes); DB.classes[classFile] = true end,
            tooltipTitle = name,
            tooltipLines = { "Show " .. name .. "s.",
                             "|cff888888Shift-click to pick only this class.|r" },
        })
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:SetPoint("TOP", panel, "TOPLEFT", PAD + colSpacing * (col + 0.5), y - row * rowHeight)
    end
    y = y - math.ceil(#CLASSES / cols) * rowHeight - 2

    AddDivider(panel, y)

    -- Options -------------------------------------------------------------
    y = y - 6
    local solo = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    solo:SetSize(24, 24)
    solo:SetPoint("TOPLEFT", PAD - 4, y)
    local soloLabel = solo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soloLabel:SetPoint("LEFT", solo, "RIGHT", 2, 1)
    soloLabel:SetText("Solo players only")
    solo:SetScript("OnClick", function(self)
        DB.soloOnly = self:GetChecked() and true or false
        PlayToggleSound(DB.soloOnly)
        ReapplyFilters()
    end)
    solo:SetScript("OnEnter", function(self)
        ShowTooltip(self, "Solo players only", "Hide groups and only show people listed on their own.")
    end)
    solo:SetScript("OnLeave", GameTooltip_Hide)
    solo.Sync = function(self) self:SetChecked(DB.soloOnly and true or false) end
    table.insert(controls, solo)
    y = y - 30

    AddDivider(panel, y)

    -- Footer --------------------------------------------------------------
    y = y - 10
    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOP", panel, "TOP", 0, y)
    y = y - 22

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(110, 22)
    reset:SetPoint("TOP", panel, "TOP", 0, y)
    reset:SetText("Reset all")
    reset:SetScript("OnClick", function()
        wipe(DB.classes)
        wipe(DB.roles)
        DB.soloOnly = false
        PlayToggleSound(false)
        ReapplyFilters()
    end)
    reset:SetScript("OnEnter", function(self)
        ShowTooltip(self, "Reset all", "Clear every filter and show all listings.")
    end)
    reset:SetScript("OnLeave", GameTooltip_Hide)
    y = y - 22 - PAD

    panel:SetHeight(-y)

    panel:SetScript("OnShow", function()
        for _, c in ipairs(controls) do c:Sync() end
        UpdateStatus()
    end)

    -- Small button shown when the panel is closed.
    miniButton = CreateFrame("Button", nil, LFGBrowseFrame, "UIPanelButtonTemplate")
    miniButton:SetSize(96, 24)
    MakeDraggable(miniButton)
    miniButton:SetScript("OnClick", function() PlayToggleSound(true); SetCollapsed(false) end)
    miniButton:SetScript("OnEnter", function(self)
        ShowTooltip(self, "LFFilter", "Open the class and role filters.",
            "|cff888888Drag to move. /lff reset puts it back.|r")
    end)
    miniButton:SetScript("OnLeave", GameTooltip_Hide)

    ApplyPosition()
    for _, c in ipairs(controls) do c:Sync() end
    SetCollapsed(DB.collapsed and true or false)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local function TrySetup()
    if setupDone or not DB then return end
    if not (LFGParentFrame and LFGBrowseFrame and LFGBrowseUtil_SortSearchResults) then return end
    setupDone = true
    hooksecurefunc("LFGBrowseUtil_SortSearchResults", FilterResults)
    if LFGBrowseFrame.UpdateResults then
        hooksecurefunc(LFGBrowseFrame, "UpdateResults", AfterUpdateResults)
    end
    BuildPanel()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        LFFilterDB = LFFilterDB or {}
        DB = LFFilterDB
        DB.classes = DB.classes or {}
        DB.roles = DB.roles or {}
        if DB.soloOnly == nil then DB.soloOnly = true end
    end
    -- The Group Finder loads on demand; hook it whenever it shows up.
    if event == "PLAYER_LOGIN" or name == LFG_ADDON or name == ADDON_NAME then
        TrySetup()
    end
end)

SLASH_LFFILTER1 = "/lff"
SLASH_LFFILTER2 = "/lffilter"
SlashCmdList.LFFILTER = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        if DB then DB.pos = nil end
        if panel then ApplyPosition() end
        print("|cff33ff99LFFilter|r: panel position reset.")
        return
    end
    if panel and LFGParentFrame and LFGParentFrame:IsShown() then
        SetCollapsed(not DB.collapsed)
    else
        print("|cff33ff99LFFilter|r: open the Group Finder and go to the Browse tab - the filters are docked on its right side.")
    end
end
