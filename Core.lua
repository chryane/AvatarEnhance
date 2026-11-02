--[[ Core.lua - 配置 / 素材 / 单位信息
	 泰坦重铸(时光服) 3.80.2.70177 / Interface 38002
]]

local ADDON_NAME, ns = ...

local defaults = {
	scale = 1,
	playerEnabled = true, playerClass = true, playerRole = true,
	targetEnabled = true, targetClass = true, targetRole = true,
	focusEnabled = true, focusClass = true,
	partyEnabled = true, partyClass = true, partyRole = true, partyLevel = false,
	raidEnabled = true, raidRole = true,
}

-- data 即 SavedVariables(加载时补齐默认值, 刷新路径裸读); scale 另存夹取后的值免每次重算
local config = { data = {}, scale = defaults.scale }
ns.config = config

function config:Load()
	local db = rawget(_G, "AvatarEnhanceDB")
	if type(db) ~= "table" then
		db = {}
		rawset(_G, "AvatarEnhanceDB", db)
	end
	for key, value in pairs(defaults) do
		if db[key] == nil then db[key] = value end
	end
	self.data = db
	self:UpdateScale()
end

function config:Set(key, value)
	self.data[key] = value
	if key == "scale" then self:UpdateScale() end
end

function config:UpdateScale()
	local v = tonumber(self.data.scale) or 1
	self.scale = v < 0.5 and 0.5 or v > 2 and 2 or v
end

-- 职责图集: 与暴雪 GetMicroIconForRole 同款(系统"设置职责"菜单 / 组队确认弹窗)
local roleAtlas = {
	TANK    = "UI-LFG-RoleIcon-Tank",
	HEALER  = "UI-LFG-RoleIcon-Healer",
	DAMAGER = "UI-LFG-RoleIcon-DPS",
}

ns.media = {
	-- 外框: 整图即环、无 uv 裁剪(暴雪按 26px 1:1 铺, 故 Layout 的 max 也是 26)
	frameTexture = "Interface\\Common\\RingBorder",
	-- 满幅圆遮罩(圆直径 = 贴图边长): 裁剪直径 == 图标直径, 与外框圆孔之间不留缝
	maskCircle = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\CircleMask",
}

-- 取不到内容一律返回 nil, 由调用方隐藏徽章
function ns.GetClassAtlas(unit)
	local _, class = UnitClass(unit)
	if class then return "classicon-" .. strlower(class) end
end

function ns.GetRoleAtlas(unit)
	return roleAtlas[UnitGroupRolesAssigned(unit)]
end
