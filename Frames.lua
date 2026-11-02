--[[ Frames.lua - 目标框架发现
	 只识别不修改: 不碰暴雪框架的属性 / 脚本 / 缩放 / 可见性。
]]

local _, ns = ...

-- 有全局名的固定框架; portrait 为肖像贴图的全局名(.portrait 缺失时的兜底)
local staticSpecs = {
	{ name = "PlayerFrame", region = "player", class = true, role = true,
	  classAngle = 45, roleAngle = -45, portrait = "PlayerPortrait" },
	{ name = "TargetFrame", region = "target", class = true, role = true, playerOnly = true,
	  classAngle = 135, roleAngle = 225, portrait = "TargetFramePortrait" },
	{ name = "FocusFrame",  region = "focus",  class = true, playerOnly = true,
	  classAngle = 135, portrait = "FocusFramePortrait" },
}

-- 团队成员 CompactRaidGroup<组>Member<位>; 团队风格小队 CompactPartyFrameMember<位>
-- (CompactPartyFrame 继承 CompactRaidGroupTemplate, 组名无编号 => outerMax=1 时不拼组号)
local gridSpecs = {
	{ prefix = "CompactRaidGroup", outerMax = 8, inner = "Member", innerMax = 5,
	  region = "raid", sysRole = true },
	{ prefix = "CompactPartyFrame", outerMax = 1, inner = "Member", innerMax = 5,
	  region = "party", sysRole = true },
}

-- 无全局名的帧池成员: 新版小队框经 SetParentKey 以 PartyFrame.MemberFrameN 访问
local childSpecs = {
	{ host = "PartyFrame", keyPrefix = "MemberFrame", max = 4, region = "party",
	  class = true, role = true, level = true,
	  classAngle = 45, roleAngle = -45, levelAngle = 225 },
}

-- 网格全局名一次生成后缓存, 避免每次重挂载重复拼接字符串
local function gridNames(spec)
	local list = spec.names
	if not list then
		list = {}
		local withIndex = spec.outerMax > 1
		for g = 1, spec.outerMax do
			for m = 1, spec.innerMax do
				list[#list + 1] = spec.prefix .. (withIndex and g or "") .. spec.inner .. m
			end
		end
		spec.names = list
	end
	return list
end

function ns.IterateFrames(cb)
	for i = 1, #staticSpecs do
		local spec = staticSpecs[i]
		local parent = _G[spec.name]
		if parent then cb(parent, spec) end
	end

	for i = 1, #gridSpecs do
		local spec = gridSpecs[i]
		local names = gridNames(spec)
		for j = 1, #names do
			local parent = _G[names[j]]
			if parent then cb(parent, spec) end
		end
	end

	for i = 1, #childSpecs do
		local spec = childSpecs[i]
		local host = _G[spec.host]
		if host then
			for j = 1, spec.max do
				local child = host[spec.keyPrefix .. j]
				if child then cb(child, spec) end
			end
		end
	end
end
