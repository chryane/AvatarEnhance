--[[ Engine.lua - 挂载 / 刷新 / 事件 / 斜杠命令
	 配置键与极坐标方向在挂载时预计算, 刷新路径零字符串拼接、零表分配;
	 事件按帧合并成一次刷新, 徽章自身缓存状态, 未变化不产生 C 调用。
]]

local ADDON_NAME, ns = ...
local config = ns.config

local engine = {}
ns.engine = engine

local entries = {}
local mounted = setmetatable({}, { __mode = "k" }) -- 以框架对象为键, 无全局名的帧也天然唯一

local function mount(parent, spec)
	if mounted[parent] then return end
	mounted[parent] = true

	local region = spec.region
	local entry = {
		parent = parent,
		playerOnly = spec.playerOnly,
		portraitName = spec.portrait,
		roleIcon = spec.sysRole and parent.roleIcon,
		keyEnabled = region .. "Enabled",
		keyClass = region .. "Class",
		keyRole = region .. "Role",
		keyLevel = region .. "Level",
		badges = {},
	}

	local Badge = ns.Badge
	local function add(kind, angle)
		local badge = Badge.new(parent, kind, angle)
		entry.badges[#entry.badges + 1] = badge
		return badge
	end
	if spec.class then entry.classBadge = add("class", spec.classAngle) end
	if spec.role then entry.roleBadge = add("role", spec.roleAngle) end
	if spec.level then entry.levelBadge = add("level", spec.levelAngle) end

	entry.hasBadge = #entry.badges > 0
	entries[#entries + 1] = entry
end

-- 交回暴雪自己的更新函数重算 roleIcon(不能盲目 Show: 无职责时它本就该隐藏)
-- unit 为空 / 框已隐藏时不能交回: 前者 UpdateRoleIcon 不校验单位会报错, 后者布局量未就绪有命中原生崩溃的风险
local function restoreSysRole(entry, unit)
	if entry.sysRoleSet then
		entry.sysRoleSet = nil
		if unit and UnitExists(unit) and entry.parent:IsShown() then
			CompactUnitFrame_UpdateRoleIcon(entry.parent)
		end
	end
end

local function update(entry)
	local unit = entry.parent.unit
	local data = config.data

	if not (unit and UnitExists(unit)) or (entry.playerOnly and not UnitIsPlayer(unit))
		or not data[entry.keyEnabled] then
		for i = 1, #entry.badges do entry.badges[i]:Update(nil) end
		restoreSysRole(entry, unit)
		return
	end

	-- 锚点只对挂了徽章的框有意义: 团队/小队网格框走 sysRole, 不参与定位
	local anchor, baseW
	if entry.hasBadge then
		anchor = entry.anchor
		if not anchor then
			anchor = ns.FindPortrait(entry.parent, entry.portraitName) or entry.parent
			entry.anchor = anchor
		end
		baseW = anchor:GetWidth()
	end

	local roleAtlas = (entry.roleBadge or entry.roleIcon) and data[entry.keyRole]
		and ns.GetRoleAtlas(unit)

	local icon = entry.roleIcon
	if icon then
		if roleAtlas then
			-- 与暴雪 UpdateRoleIcon 同款: 保留布局高度并取成正方形(隐藏态暴雪把宽度收成 1)
			-- size<=0 = 暴雪尚未排版, 写 0x0 会命中原生除零
			local size = icon:GetHeight()
			if size > 0 then
				icon:SetAtlas(roleAtlas)
				icon:SetSize(size, size)
				icon:Show()
				entry.sysRoleSet = true
			end
		else
			restoreSysRole(entry, unit)
		end
	end

	if entry.classBadge then
		entry.classBadge:Update(data[entry.keyClass] and ns.GetClassAtlas(unit), anchor, baseW)
	end
	if entry.roleBadge then
		entry.roleBadge:Update(roleAtlas, anchor, baseW)
	end
	if entry.levelBadge then
		local level = data[entry.keyLevel] and UnitLevel(unit)
		entry.levelBadge:Update(level and level > 0 and level, anchor, baseW)
	end
end

function engine:Remount()
	ns.IterateFrames(mount)
end

function engine:Refresh()
	for i = 1, #entries do update(entries[i]) end
end

-- 值为 true: 框架类事件可能有新框架, 需要重挂载
local EVENTS = {
	PLAYER_ENTERING_WORLD = true,
	GROUP_ROSTER_UPDATE = true,
	RAID_ROSTER_UPDATE = true,
	PLAYER_ROLES_ASSIGNED = true,
	ROLE_CHANGED_INFORM = true,

	PLAYER_TARGET_CHANGED = false,
	PLAYER_FOCUS_CHANGED = false,
	UNIT_NAME_UPDATE = false,
	UNIT_PORTRAIT_UPDATE = false,
	PLAYER_SPECIALIZATION_CHANGED = false,
	UNIT_LEVEL = false, -- 按单位派发; 自己升级另有 PLAYER_LEVEL_CHANGED
	PLAYER_LEVEL_CHANGED = false,
}

-- 同一帧内到达的事件合并成一次: 团队加载时每人一条 UNIT_NAME_UPDATE, 不合并就是 N 次全量刷新。
-- 一次性延时把自己清掉, 空转时没有回调也没有帧脚本。
local queued, needRemount = false, false

local function flush()
	queued = false
	if needRemount then
		needRemount = false
		engine:Remount()
	end
	engine:Refresh()
end

local eventFrame = CreateFrame("Frame", nil, UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		eventFrame:UnregisterEvent("ADDON_LOADED")
		config:Load()
		ns.options:Init()
		for e in pairs(EVENTS) do eventFrame:RegisterEvent(e) end
		engine:Remount()
		engine:Refresh()
		return
	end
	local remount = EVENTS[event] -- 值是"要不要重挂载", 为 false 也是关心的事件
	if remount == nil then return end
	if remount then needRemount = true end
	if queued then return end
	queued = true
	C_Timer.After(0, flush)
end)

-- SLASH_*/SlashCmdList 为游戏规定的注册方式, 属标准全局
SLASH_AVATARENHANCE1 = "/ae"
SLASH_AVATARENHANCE2 = "/avatarenhance"

SlashCmdList["AVATARENHANCE"] = function(input)
	local value = input and tonumber(input:match("scale%s+(%S+)"))
	if value then
		config:Set("scale", value)
		engine:Refresh()
	else
		ns.options:Open()
	end
end
