if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end -- WoW Forever only (the main file adds the block to BLOCK_TYPES there)
-- Blocks\Ammo.lua
-- Ammo / Soul Shards block factory.

local ADDON_NAME, ns = ...
local K = ns.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local floor       = math.floor
local max         = math.max
local min         = math.min

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf

local SOUL_SHARD = 6265
local AMMO_SLOT  = INVSLOT_AMMO or 0
local LOW_COLOR  = { r = 1, g = 0.25, b = 0.25 }
local REAGENT_BAG = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

-------------------------------------------------------------------------------
--  AMMO / SOUL SHARDS (warlocks count shards, everyone else equipped ammo)
-------------------------------------------------------------------------------
ns.BlockFactories.ammo = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    -- UNIT_INVENTORY_CHANGED: ammo slot stack changes.
    inst.events = { "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }

    local isWarlock = select(2, UnitClass("player")) == "WARLOCK"
    local mouseOver = false

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)

    local icon = button:CreateTexture(nil, "OVERLAY")
    local amountText = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, amountText)

    -- Stacks of an item in every bag, reagent bag slot included (soul bags can sit there).
    local function BagCount(id)
        local n = 0
        for bag = 0, REAGENT_BAG do
            for i = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, i)
                if info and info.itemID == id then n = n + (info.stackCount or 0) end
            end
        end
        return n
    end

    -- Returns count, icon, item id (nil icon/id = no ammo equipped).
    -- Ammo: the ammo slot stack only. Shards: every bag.
    local function Sample()
        if isWarlock then
            return BagCount(SOUL_SHARD), C_Item.GetItemIconByID(SOUL_SHARD), SOUL_SHARD
        end
        local id = GetInventoryItemID("player", AMMO_SLOT)
        if not id then return 0 end
        return GetInventoryItemCount("player", AMMO_SLOT) or 0, GetInventoryItemTexture("player", AMMO_SLOT), id
    end

    function inst:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local gap = ICON_GAP

        local count, tex = Sample()
        local text = BreakUpLargeNumbers and BreakUpLargeNumbers(count) or tostring(count)

        local iconSz = 0
        if s.showIcon ~= false and tex then
            iconSz = fontSize + 2
            icon:SetTexture(tex)
            icon:SetTexCoord(5 / 64, 59 / 64, 5 / 64, 59 / 64)
            icon:SetSize(iconSz, iconSz)
            icon:Show()
        else
            icon:Hide()
        end

        ns.SetFont(amountText, fontSize, barCfg)
        if barCtx.IsVertical() then
            local slotW = VSlotW(inst)
            amountText:SetText(text)
            local totalH = 8
            icon:ClearAllPoints()
            amountText:ClearAllPoints()
            if iconSz > 0 then
                icon:SetPoint("TOP", button, "TOP", 0, -4)
                amountText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
                totalH = totalH + iconSz + 2
            else
                amountText:SetPoint("TOP", button, "TOP", 0, -4)
            end
            totalH = max(totalH + ns.SnapToPixelGrid(amountText:GetStringHeight()) + 4, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 80)
            ns.ResetInlineText(amountText, "LEFT")
            amountText:SetText(text)
            icon:ClearAllPoints()
            amountText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then
                icon:SetPoint("LEFT", button, "LEFT", 0, 0)
                xOff = iconSz + gap
            end
            amountText:SetPoint("LEFT", button, "LEFT", xOff, 0)
            local tw = ns.SnapToPixelGrid(amountText:GetStringWidth())
            local totalW = max(min(slotW, xOff + tw + 4), 10)
            content:SetSize(totalW, barH)
            button:SetSize(totalW, barH)
        end

        local low = s.lowThreshold or 0
        if mouseOver then
            amountText:SetTextColor(ns.GetAccent())
        elseif low > 0 and count <= low then
            local c = s.lowColor or LOW_COLOR
            amountText:SetTextColor(c.r, c.g, c.b)
        else
            amountText:SetTextColor(BlockColorOf(blockCfg))
        end
        MaybeRelayout(inst)
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        local count, _, id = Sample()
        ns.Tip_Begin(button)
        local name = id and C_Item.GetItemNameByID(id)
        ns.Tip_AddDouble(name or (isWarlock and "Soul Shard" or "Ammo"), count, 1, 1, 1, 1, 1, 1)
        ns.Tip_Show()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 50, 24)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end
