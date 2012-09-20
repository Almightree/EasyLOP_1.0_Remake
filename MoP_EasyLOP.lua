EasyLOP = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceEvent-2.0", "AceDB-2.0", "AceHook-2.1")

-- to do:  build a cancel function to cancel entire process, clear out tables, etc.  when user does a cancel.  Only the addonOwner will be able to cancel because only the addonOwner will see the windows that prompt it.
-- Set Normal/Heroic automatically based on number of raiders or points imported.

Version = 1.46
bVashjTest = true
bMLQualified = false
--bAcceptAnnounce = false - moved to Defaults table
bPendingAnnounce = false
bDebugMode = false
--bDebugMode = true
bHarassPlayer = true
bSuspendProcess = false
bWaitingOnVerCheck = false
bSkipSyncMessage = false
bDeactivated = false
bGoOnToAccept = false -- Used to manage the flow from the CAPTURE_DEORGREED static popup box - if out of a loot flow, will just update the DEer/Greeder; if in a flow, will go on to AcceptAnnouncement function
--bAutoAward = false --Have ELOP give loot to the winner automatically. - moved to Defaults table
tse = "EasyLOPThreeSecondEvent"
strGrey = "|cff9d9d9d"
strGreen = "|cff1eff00"
strRed = "|cffe60000"


prevtLoots = {} -- tLoots from last LOOT_OPENED.   No quant.  info kept as itemlinks
tLootList = {} -- All loots that dropped from last LOOT_OPENED, whether eligible for points or not.    No quant.  info kept as itemlinks
tRaidMembers = {}
tRollItems = {}
tRaidLeads = {}
eventLog = {}

tLoots = { --[[
	loot1 = {
		item = (itemlink)
		quant = (number of identical items in different slots on corpse [ie, tokens])
		winbid = (the tWinners entry or entries - this is a bid table or a table of bid tables, so it includes bidder, bidtype, item, and points)
	}
]]} -- Loots that are eligible for points resolution   

tBids = {
	--[[bid1 = {
		bidder = "Bidder1", 
		bidType = "save",
		item = itemlink, 
		points = 0}]]
}


tWinners = {
	--[[winner1 = {
	 bidder = "Test", 
	 bidType = "Testshroud", 
	 item = itemlink, 
	 points = 13}
	]]
}

tPrevBids = {}
tMsgQ = {}

--****** This table is related to points importing	
defaults = {  
	charPoints = {	},
	RaidID = 0,
	ExportTime = 0, 
	RaidType = "", 
	bAutoAward = false, 
	bAutoAnnounce = true, 
	DEer = ""
}
--******

local options = {
	type = 'group',
	desc = "Commands",
	args = {
		announce = {
			type = 'execute',
			name = 'Announce winner(s)',
			desc = "After determining winners, use this command to announce and charge winners.",
			func = "AcceptAnnouncement"
		}, 
		openbids = {
			type = 'execute',
			name = 'Open bidding',
			desc = "Start bidding on the earliest eligible loot in the current loot window",
			func = "OpenBids"
		}, 
		bid = {
			type = 'text',
			name = 'bid',
			desc = 'Manually call for bids on a single item.',
			--set  = 'ImportData',
			set = 'Bid',
			get  = false,
			usage = 'itemlink',
			validate = function(v) return v == nil or (type(v) == 'string' and string.find(v, "|r")) end,
		},
		closebids = {
			type = 'execute',
			name = 'Close bidding',
			desc = "Close bidding on the current item and determine winner",
			func = "CloseBids"
		},
		setDE = {
			type = 'text',
			name = 'setDE',
			desc = "Assign a designated disenchanter for unclaimed loot.",
			usage = "<character name>",
			get = "getDE",
			set = "setDE"
		},
		setGreed = {
			type = 'text',
			name = 'setGreed',
			desc = "Assign a designated individual to hold on to epic greed loot.",
			usage = "<character name>",
			get = "getGreed",
			set = "setGreed"
		},
		autoannounce = {
			type = 'toggle',
			name = 'Toggle Auto-announce',
			desc = "When active, will announce all loot on body in raid warning",
			get = function()
				return bAutoAnnounce
			end,
			set = function(v)
				bAutoAnnounce = v
				EasyLOP.db.profile.bAutoAnnounce = v
			end,
			map = {[false] = "Disabled", [true] = "Enabled"}
		},
		autoaward = {
			type = 'toggle',
			name = 'Toggle Auto-awarding of loot',
			desc = "While ML is loot method and you are ML, will automatically award loot to the person who wins the bid",
			get = function()
				return bAutoAward
			end,
			set = function(v)
				bAutoAward = v
				EasyLOP.db.profile.bAutoAward = v
				ELOP_FrameCBAutoAward:SetChecked(v)
				EasyLOP:ELOP_FrameRefresh()
				--EasyLOP:Print(ELOP_FrameCBAutoAward:GetChecked())
			end,
			map = {[false] = "Disabled", [true] = "Enabled"}
		},
		off = {
			type = 'toggle',
			name = 'EasyLOP',
			desc = "While 'inactive', EasyLOP will not announce loot, prompt you to call for bids, or respond to queries from other EasyLOP users.",
			get = function()
				return bDeactivated
			end,
			set = function(v)
				bDeactivated = v
			end,
			map = {[false] = "Active", [true] = "Inactive"}
		},
		debugmode = {
			type = 'toggle',
			name = 'Toggle Debug mode',
			desc = "When active, all loot will be announced and treated as lootable, including greys.",
			get = function()
				return bDebugMode
			end,
			set = function(v)
				bDebugMode = v
				if v == false then
					iRarityThreshold = 4
				else
					iRarityThreshold = 2
				end
			end,
			map = {[false] = "Disabled", [true] = "Enabled"}
		},--[[
		parsing = {
			type = 'toggle',
			name = 'Toggle Parsing logic',
			desc = "When active, whispers are acknowledged.  Code not complete.",
			get = function()
				return bParsing
			end,
			set = function(v)
				bParsing = v
			end,
			map = {[false] = "Disabled", [true] = "Enabled"}
		},
		badgecount = {
			type = 'execute',
			name = "Badge Announcement",
			desc = "Announce to raid how many badges have been collected.",
			func = "BadgeAnnounce"
		},]]
		ver = {
			type = 'execute',
			name = "Version check",
			desc = "Check your EasyLOP version, as well as the versions of all other raid members.",
			func = "VerCheck"
		},--[[
		announceloot = {
			type = 'execute',
			name = "Force announcement of loot",
			desc = "Announce current loot list via raid warning.",
			func = "ForceAnnounce"
		},]]
		listbids = {
			type = 'execute',
			name = "List bids on the current loot",
			desc = "Lists all bids received for the current item.",
			func = "spitbids"
		},
		oldbids = {
			type = 'execute',
			name = "List previous bids",
			desc = "Lists all bids received since your last ui reload.",
			func = "oldbids"
		},--[[
		testbong = {
			type = 'execute',
			name = "test function only",
			desc = "test only",
			func = "testbong"
		},]]
		imp = {
			type = 'execute',
			name = 'Import',
			desc = 'Import raid information and points',
			--set  = 'ImportData',
			func = "UserImport"
			--get  = false,
			--usage = '10-man|25-man|10|25',
			--validate = function(v) return type(v) == 'string' and (v == "25-man" or v == "10-man" or v == "10" or v == "25" or v == "") end,
		},
		unlock = {
			type = 'execute',
			name = 'UserUnlock',
			desc = 'Allow a new loot window to be loaded into EasyLOP without completing the current one.',
			func = 'Unlock'
		},
		clear = {
			type = 'execute',
			--name = 'ClearPoints',
			name = 'UserClear',
			desc = 'Clear the points list in the database',
			func = 'Clear'
		},
		pts = {
			type = 'text',
			name = 'Get points',
			desc = 'View raid points for a character',
			--set  = 'GetPoints',
			set = 'UserGet',
			get  = false,
			usage = '<character name>',
			validate = function(v) return type(v) == 'string' and v:trim():len() > 0 end,
		},--[[
		list = {
			type = "text",
			name = "List roster",
			desc = "List the raid roster",
			set  = "ListRoster",
			get  = false,
			usage= "standby|slotted",
			validate = function(v) return v == "standby" or v == "slotted" end,
		},]]
		charge = {
			type = 'text',
			name = 'Charge points',
			desc = 'Manually charge a player for a piece of loot they won.  Will apply only to your local copy of the points.',
			--set  = 'ModifyPoints',
			set = 'UserModify',
			get  = false,
			input = true,
			usage = '<character name> <save|std|shroud>',
			--validate = function(v) return type(v) == 'string' and v:trim():len() > 0 end,
		},
		set = {
			type = 'text',
			name = 'Set points',
			desc = "Set a player's points to a certain value.  Applies to all ELOP users.",
			--set = "SetPoints",
			set = 'UserSet',
			get = false,
			input = true,
			usage = "<character name> <new total>"
		},
		x = {
			type = 'text',
			name = 'Explain LOP',
			desc = 'Send series of tells to a player explaining the basics of the LOP system.',
			--set  = 'ModifyPoints',
			set = 'ExplainLOP',
			get  = false,
			input = true,
			usage = '<character name>',
		},
		 report = {
			type = 'execute',
			name = 'Show report',
			desc = "Report all points-based events to chat console.",
			func = "PrintEventLog"
		}, --[[
		options = {
			type = 'execute',
			name = 'ELOP Options Menu',
			desc = "Displays the EasyLOP options window.",
			func = "showOptions"
		},]]
	}
}

StaticPopupDialogs["CONFIRM_WINNER"] = {
  --text = strPopup,
  text = "Winner(s) of %s:  %s",
  button1 = "Announce & Charge",
  button2 = "Cancel",
  OnAccept = function()
      EasyLOP:AcceptAnnouncement()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

StaticPopupDialogs["END_ROLLS"] = {
  --text = strPopup,
  text = 'Rolloff in progress.  Click "End Rolls" to force a pass on those who have not yet rolled.  Otherwise EasyLOP will determine the winner automatically once all bidders have rolled.',
  button1 = "End Rolls",
  OnAccept = function()
      EasyLOP:ForceEndRolls()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

StaticPopupDialogs["CAPTURE_DEORGREED"] = {
  --text = strPopup,
  preferredIndex = 3,
  text = "Type the name of your designated %s.",
  button1 = "Accept",
  button2 = "Cancel",
  --[[OnShow = function()
	getglobal(this:GetName().."EditBox"):SetText("Replace this text.")
  end,]]    -- code to preset a default value in the text box.
  OnAccept = function()
	if bSendToGreed == false then
        local editText = self.editBox:GetText()
		EasyLOP:setDE(editText)
		EasyLOP:ELOP_FrameRefresh()
	else
        local editText = self.editBox:GetText()
		EasyLOP:setGreed(editText)
		EasyLOP:ELOP_FrameRefresh()
	end
	
	if bGoOnToAccept == true then
		bGoOnToAccept = false
		EasyLOP:AcceptAnnouncement()
	end
	--EasyLOP:Print("Text entered was: " .. getglobal(this:GetParent():GetName().."EditBox"):GetText())
  end,
  OnCancel = function()
	bHarassPlayer = false
	if bGoOnToAccept == true then
		bGoOnToAccept = false
		EasyLOP:AcceptAnnouncement()
	end
  end,
  hasEditBox = true,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

StaticPopupDialogs["NO_BIDDERS"] = {
  --text = strPopup,
  text = "There were no bidders.  Do you want %s to be Disenchanted, or go into the Greed pile?",
  button1 = "Disenchant",
  button2 = "Greed",
  OnAccept = function()
	bSendToGreed = false
	if EasyLOP:CheckForName() == true or bHarassPlayer == false or lootSystem ~= 'master' then
		EasyLOP:AcceptAnnouncement()
	else
		bGoOnToAccept = true
		StaticPopup_Show("CAPTURE_DEORGREED", "disenchanter")
	end
  end,
  OnCancel = function()
	bSendToGreed = true
	if EasyLOP:CheckForName() == true or bHarassPlayer == false or lootSystem ~= 'master' then
		EasyLOP:AcceptAnnouncement()
	else
		bGoOnToAccept = true
		StaticPopup_Show("CAPTURE_DEORGREED", "greeder")
	end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

function EasyLOP:CheckForName()
	if bSendToGreed == false then
		if self.DEer ~= "" then
			return true
		else
			return false
		end
	else
		if self.Greeder ~= "" then
			return true
		else
			return false
		end
	end
end

StaticPopupDialogs["BEGIN_BIDS"] = {
  --text = strPopup,
  --text = "Do you want to open bidding on the next item?",
  text = "Do you want to open bidding on %s?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function()
      EasyLOP:OpenBids()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

StaticPopupDialogs["CLOSE_BIDS"] = {
  --text = strPopup,
  --text = "Do you want to end the current bidding session?",
  text = "Bidding is currently open on %s.",
  button1 = "Close Bids",
  button2 = "Cancel",
  OnAccept = function()
      EasyLOP:CloseBids()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

StaticPopupDialogs["PROMPT_FOR_25"] = {
  --text = strPopup,
  --text = "Do you want to open bidding on the next item?",
  text = "You have 10-man points loaded, but more than 10 people in the raid.  Do you want to import 25-man points now?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function() 
      EasyLOP:UserImport("25-man")
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

StaticPopupDialogs["PROMPT_FOR_10"] = {
  --text = strPopup,
  --text = "Do you want to open bidding on the next item?",
  text = "You have 25-man points loaded, but 10 or fewer people in the raid.  Do you want to import 10-man points now?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function() 
      EasyLOP:UserImport("10-man")
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0
};

--[[
StaticPopupDialogs["ANNOUNCE_ROLLOFF"] = {
  --text = strPopup,
  text = "Do you want to call for rolls?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function()
      EasyLOP:AnnounceRolloff()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
};]]

function EasyLOP:OnInitialize()

	bMLQualified = false
	bAutoAnnounce = true
	bParsing = true
	bBidsActive = false
	bRolloffs = false
	bOverrideSync = false
	bSendToGreed = false -- false = give to DEer, true = give to Greeder
	numLoots = 0
	numQualLoots = 0
	combatEntries = 0
	numWarnings = 0
	self.DEer = ""
	self.Greeder = ""
	lootSystem, throwaway, masterLooterID = GetLootMethod() -- 'freeforall', 'master', 'group'
	addonOwner = ""
	
	numTBD = 0
	iCurrentLootIndex = 1
	iTotalBadges = 0
	iRarityThreshold = 4  -- Set to 4 to have the addon handle epics and above only; set to 0 to test from bags in-game and on greys from trash.
	msgQIndex = 1
	
	if type(RegisterAddonMessagePrefix) == "function" then
		if not RegisterAddonMessagePrefix("ELOP") then -- main prefix for DBM4
			DBM:AddMsg("Error: unable to register EASYLOP addon message prefix (reached client side addon message filter limit), synchronization will be unavailable") -- TODO: confirm that this actually means that the syncs won't show up
		end
		--RegisterAddonMessagePrefix("ELOP-Ver") -- to see old clients which will still try to communicate with us
	end
	
	EasyLOP:Print("EasyLOP successfully loaded.  Version " .. Version)
	--RegisterOptionsTable('EasyLOP',options)
	self:RegisterChatCommand({"/lop", "/el", "/easylop"}, options, "LOP")
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("CHAT_MSG_WHISPER")
	self:RegisterEvent("LOOT_SLOT_CLEARED")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("CHAT_MSG_RAID_WARNING")
	self:RegisterEvent("CHAT_MSG_RAID")
	self:RegisterEvent("CHAT_MSG_RAID_LEADER")
	self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
	self:RegisterEvent("CHAT_MSG_LOOT")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("START_LOOT_ROLL")
	self:RegisterEvent("RAID_ROSTER_UPDATE")
	--self:RegisterEvent("LOOT_CLOSED")
	--SetLootMethod("master","Felysha",1)
	--SetLootThreshold(1)
	
	-- Hook text functions in order to cut down reply spam.
	--hooksecurefunc('ChatEdit_ParseText',EasyLOP:TrimReplySpam)
	
	
	
	-- ******  Saved Variables IMPORTING RELATED ITEMS
	EasyLOP:RegisterDB("EasyLOPDB", "EasyLOPDB_Points", "Default")
	EasyLOP:RegisterDefaults( 'profile', defaults )
	--******
	
	-- Load saved variables
	EasyLOP:LoadSavedVariables()
	
	-- Create options frame
	EasyLOP:CreateOptionsFrame()
end

function EasyLOP:LoadSavedVariables()
	bAutoAward = EasyLOP.db.profile.bAutoAward
	ELOP_FrameCBAutoAward:SetChecked(bAutoAward)
	EasyLOP:ELOP_FrameRefresh()
	
	bAutoAnnounce = EasyLOP.db.profile.bAutoAnnounce
	self.DEer = EasyLOP.db.profile.DEer
end

function EasyLOP:OnEnable()
	if EasyLOP:ValidatePoints() == true then
		self:Print("Points last loaded: " .. EasyLOP.db.profile.ExportTime)
		self:Print("Points loaded are for the " .. EasyLOP.db.profile.RaidType .. " pool.")
	end
	--Check date of points load, if old warn user.
	--if 
end
--[[
function EasyLOP:ELOPOptions_OnLoad(panel)
	panel.name = "EasyLOP"
	InterfaceOptions_AddCategory(panel)
end]]

function EasyLOP:ValidatePoints()
	if GetNumGroupMembers() < 2 then
		--self:Print("returning...")
		return
	end
	--if GetNumRaidMembers() < 1 then
	--	self:Print("returning...")
	--	return
	--end
	if EasyLOP.db == nil or EasyLOP.db.profile.RaidType == nil or EasyLOP.db.profile.RaidType == "" or EasyLOP.db.profile.ExportTime == 0 or EasyLOP.db.profile.ExportTime == nil then
		self:Print("|cffe60000 POINT RECORDS HAVE NOT YET BEEN IMPORTED.  To import point records, download the latest points info from the LO site, save it to the EasyLOP directory as 'Leftovers_Points.lua', restart WoW, and type /lop imp 25/10'|r")
		return false
	else
		strDate = date()
		for word in string.gmatch(strDate, "../../..") do 
			strDate = word
		end
		currentDate = strDate
		
		for word in string.gmatch(EasyLOP.db.profile.ExportTime, "../../..") do
			strDate = word
		end
		
		lastDate = strDate
		
		--if currentDate == lastDate then
		--	return true
		if currentDate ~= lastDate and numWarnings < 4 then
			--self:Print("Warning number " .. numWarnings)
			self:Print("|cffe60000 OLD POINTS DETECTED.  Points records have not yet been loaded today.  To import current point records, download the latest points info from the LO site, save it to the EasyLOP directory as 'Leftovers_Points.lua', restart WoW, and type /lop imp 25/10'|r")
			numWarnings = numWarnings + 1
			return false
		end
	end

	--Count number of raid members and compare to points pool loaded.
	raidCount = GetNumGroupMembers()

	if EasyLOP.db.profile.RaidType == "10-man" and raidCount > 10 then
		self:Print(strRed .. "WARNING:  You have 10-man points loaded but there are more than 10 people in the raid.")
		StaticPopup_Show ("PROMPT_FOR_25")
		return false
	elseif EasyLOP.db.profile.RaidType == "25-man" and raidCount < 11 then
		self:Print(strRed .. "WARNING:  You have 25-man points loaded but there are 10 or fewer people in the raid.")
		StaticPopup_Show ("PROMPT_FOR_10")
		return false
	end
	
	return true
end

function EasyLOP:getDE()
	return self.DEer
end

function EasyLOP:setDE(DEname)
	self.DEer = DEname
	if self.DEer == "" then
		self:Print("Cleared designated Disenchanter.  No Disenchanter now assigned.")
	else
		self:Print( DEname .. " assigned as the Disenchanter.")
	end
	
	EasyLOP.db.profile.DEer = DEname
end

function EasyLOP:getGreed()
	return self.Greeder
end

function EasyLOP:setGreed(GrName)
	self.Greeder = GrName
end

function EasyLOP:getItemName(itemLink)
	local sName, sLink, iRarity, iLevel, iMinLevel, sType, sSubType, iStackCount = GetItemInfo(itemLink)
	return sName
end

function EasyLOP:getItemTexture(itemLink)
	local sName, sLink, iRarity, iLevel, iMinLevel, sType, sSubType, iStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemLink)
	return itemTexture
end

function EasyLOP:LOOT_OPENED()
	
	if bDeactivated == true then
		return
	end
	--self:Print("LOOT_OPENED called!")
	EasyLOP:ValidatePoints()
	
	--Reset all variables
	bMLQualified = false
	--bBidsActive = false
	
	--reset loot table but keep copy of previous
	for i, loot in pairs(tLoots) do
		prevtLoots[i] = tLoots[i].item
	end
	
	
	-- determine rarity of all items, and assign LOP-eligible (epic) items to tTempLoots for comparison
	tLootList = {} -- list of all loots on corpse, regardless of rarity
	tTempLoots = {} -- temporary build of tLoots, for comparison purposes
	numQualLoots = 0
	numLoots = GetNumLootItems()
	--self:Print("Number of Loot Items:" .. numLoots)
	tMsgQ = {}
	strLootList = "*Loots: "
	strLootList2 = ""
	strLootList3 = ""

	for i = 1, numLoots, 1 do	
		if LootSlotHasItem(i) then
			local sName, sLink, iRarity, iLevel, iMinLevel, sType, sSubType, iStackCount = GetItemInfo(GetLootSlotLink(i))
			--self:Print("Slot " .. i .. " has " .. sLink .. ", rarity " .. iRarity .. ".")
			if iRarity >= iRarityThreshold then
				if sName == "Badge of Justice" or sName == "Emblem of Valor" or sName == "Emblem of Heroism" or sName == "Emblem of Conquest" or sName == "Emblem of Triumph" or sName == "Ashen Sack of Gems" or sName == "Emblem of Frost" or sName == "Eternal Ember" or sName == "Essence of Destruction" then
					--local lootIcon, lootName, lootQuantity, rarity = GetLootSlotInfo(i)
					--LootSlot(i)
					--iTotalBadges = iTotalBadges + lootQuantity
				elseif sName == "Abyss Crystal" or sName == "Void Crystal" or sName == "Nexus Crystal" or sName == "Maelstrom Crystal" or sName == "Sha Crystal" then
					local lootIcon, lootName, lootQuantity, rarity = GetLootSlotInfo(i)
					LootSlot(i)
				else
					bMLQualified = true
					numQualLoots = numQualLoots + 1
					table.insert(tLootList, sLink)
					
					-- Find if the item is already in tLoots, if so, increment quant.  Otherwise, add it with quant 1.
					bExisted = false
					for i, item in pairs(tTempLoots) do 
						local xName, xLink, xRarity, xLevel, xMinLevel, xType, xSubType, xStackCount = GetItemInfo(tTempLoots[i].item)
						--self:Print("Checking " .. xName .. " in tLoots against " .. sName .. ".")
						--if tLoots[i].item == sLink then
						if xName == sName then
							tTempLoots[i].quant = tTempLoots[i].quant + 1
							bExisted = true
						end
					end
					
					if bExisted == false then
						thisLoot = {}
						thisLoot.item = sLink
						thisLoot.quant = 1
						table.insert(tTempLoots, thisLoot)
					end
				end
			end
		else 
			table.insert(tLootList, "money")
		end
	end
	
	if bSuspendProcess == true and bMLQualified == true then
		self:Print("The looting process is currently locked by " .. addonOwner .. ".  All current loot must be assigned before new loot can be handled.  If this is an error, use /lop unlock.")
		return
	end
	
	--[[method, x, y = GetLootMethod()
	if method == "group" then
		
		return
	end]]
	
	for i, loot in pairs(tTempLoots) do
		loot.winbid = {}
	end
	
	-- update tLoots on all addons currently running
	--[[strAddonLootList = ""
	for i, item in pairs(tLoots) do
		strAddonLootList = strAddonLootList .. tTempLoots[i].item .. " " .. tTempLoots[i].quant .. " " 
	end]]
	
	--SendAddonMessage("ELOP_UPDATE_TLOOTS", strAddonLootList, "RAID")
	
	--[[ Identify raiders and the slot they occupy - this code works if needed, just uncomment/amend as necessary
	if bMLQualified == true then 
		for i = 1, 40, 1 do  
			strRaidSlot = "Slot " .. i .. ": "
			if GetMasterLootCandidate(i) ~= nil then
				strRaidSlot = strRaidSlot .. GetMasterLootCandidate(i)
				self:Print(strRaidSlot)
			end
		end
	end]]

	if bMLQualified == true then		
		--[[Update all other EasyLOP Addons running so multiple people don't bong the loot.   **TBI**
		strLoots = ""
		for i, item in ipairs(tLoots) do
			strLoots = 
		SendAddonMessage("ELOP_TLOOTS_UPDATED", ]]
		--link loots of ML qualified level 
		if bAutoAnnounce == true then
			bTempSuspend = false
			-- If this is the same loot window that is already saved in tLoots, don't re-announce it to the raid. 
			iEntriesMade = 0
			for i, loot in pairs(tTempLoots) do
				--self:Print("Incrementing iEntriesMade")
				iEntriesMade = iEntriesMade + 1
				if tTempLoots[i+1] == nil then
					strComma = ""
				else
					strComma = ", "
				end
				
				if tTempLoots[i].quant > 0 then
					if tTempLoots[i].quant == 1 then
						if iEntriesMade <= 2 then 
							--self:Print("Adding " .. tTempLoots[i].item .. " to list1.")
							strLootList = strLootList .. tTempLoots[i].item .. strComma
						elseif iEntriesMade <= 6 then
							--self:Print("Adding " .. tTempLoots[i].item .. " to list2.")
							strLootList2 = strLootList2 .. tTempLoots[i].item .. strComma
						elseif iEntriesMade > 6 then
							--self:Print("Adding " .. tTempLoots[i].item .. " to list3.")
							strLootList3 = strLootList3 .. tTempLoots[i].item .. strComma
						end
					else
						if iEntriesMade <= 2 then 
							--self:Print("Adding " .. tLoots[i].item .. " x " .. tTempLoots[i].quant .. " to list1.")
							strLootList = strLootList .. tTempLoots[i].item .. " x " .. tTempLoots[i].quant .. strComma
						elseif iEntriesMade <= 6 then
							--self:Print("Adding " .. tLoots[i].item .. " x " .. tTempLoots[i].quant.. " to list2.")
							strLootList2 = strLootList2 .. tTempLoots[i].item .. " x " .. tTempLoots[i].quant .. strComma
						elseif iEntriesMade > 6 then
							--self:Print("Adding " .. tLoots[i].item .. " x " .. tTempLoots[i].quant.. " to list3.")
							strLootList3 = strLootList3 .. tTempLoots[i].item .. " x " .. tTempLoots[i].quant .. strComma
						end
					end
				end
			end
			
			-- If the secondary loot lists were populated, add them to the queue
			if strLootList2 ~= "" then
				table.insert(tMsgQ, strLootList2)
				
				if strLootList3 ~= "" then
					table.insert(tMsgQ, strLootList3)
				end
			end
			
			-- Compare tTempLoots to current tLoots.  If duplicates are found, and there are unwon items in tLoots currently, do not overwrite tLoots.
			--Otherwise, overwrite tLoots with the tLootList
			bCheckUnwon = false
			bOverwrite = true
			
			-- check for a match between the current tLoots table and the loot window that was just opened.
			for i, temploot in pairs(tTempLoots) do
				for j, tloot in pairs(tLoots) do
					if temploot.item == tloot.item then
						--bCheckUnwon = true
						bOverwrite = false
					end
				end
			end
			--[[
			-- if a match was found, check for unwon items in the current tLoots table.  If there are any pending items, do not overwrite tLoots.
			if bCheckUnwon == true then
				self:Print("CheckUnwon is true.")
				for i, loot in pairs(tLoots) do
					self:Print( tLoots[i].item )
					if loot.winbid[1] == nil then
						--self:Print("loot.winbid[1] is nil.")
						bOverwrite = false
					else
						for j, winningbid in pairs(loot.winbid) do
							--self:Print("winningbid.bidder is " .. winningbid.bidder)
							if winningbid.bidder == nil then
								bOverwrite = false
							end
						end
					end
				end
			end]]   -- Removing this code means that it will not re-bong the loot list, even if unwon items are present.  This help coordinate multiple addons.
			
			-- if Overwrite is true, this is a whole new loot window.  reset defaults and copy the new tLoots table.
			if bOverwrite == true then
				SendAddonMessage("ELOP", "ELOP_SET_SUSPEND^true " .. UnitName("player"), "RAID")
				if bBidsActive == true then
					self:Print("Your current bidding session on " .. tLoots[iCurrentLootIndex].item .. " has been cancelled.  Any bids received have been lost.  You can open a new bidding session by re-opening the original corpse's loot window and re-starting the process.")
				elseif bPendingAnnounce == true then
					self:Print("You have not announced the winner of the " .. tLoots[iCurrentLootIndex].item .. " and no one has been charged for winning it.  Automation of this process may no longer be possible.  Use /lop charge <playername> <bidtype> to manually charge the winner.")
				end
				
				SendAddonMessage("ELOP","ELOP_KILL_POPUPS^", "RAID")
				
				--self:Print("Overwrite is true.")
				bBidsActive = false
				iCurrentLootIndex = 1
				SendAddonMessage("ELOP","ELOP_UPDATE_INDEX^".. iCurrentLootIndex .. " " .. UnitName("player") .. " OpenBids", "RAID")				
				tLoots = {}
				
				--[[			
				elseif prefix == "ELOP_CLEAR_TLOOTS" then
					tLoots = {}
				elseif prefix == "ELOP_ADD_TLOOTS_ENTRY" then
					-- insert code
				elseif prefix == "ELOP_UPDATE_TLOOTS_ENTRY" then
					-- insert code					
					
				bid1 = {
				bidder = "Bidder1", 
				bidType = "save",
				item = "item:6948:0:0:0:0:0:0:0", 
				points = 0}
		
				tLoots = { --
					loot1 = {
						item = (itemlink)
						quant = (number of identical items in different slots on corpse [ie, tokens])
						winbid = (the tWinners entry or entries - this is a bid table or a table of bid tables, so it includes bidder, bidtype, item, and points)
					}
				]]
		
				-- Update the tLoots table for all ELOP addons (including this one)
				SendAddonMessage("ELOP","ELOP_CLEAR_TLOOTS^", "RAID")
				
				for i, loot in pairs(tTempLoots) do
					--table.insert(tLoots, loot)
					sendString = i .. " " 
					sendString = sendString .. loot.quant .. " " 
					sendString = sendString .. loot.item
					SendAddonMessage("ELOP", "ELOP_ADD_TLOOTS_ENTRY^".. sendString, "RAID")
					--self:Print("Send addon message:  " .. sendString)
				end
				
				SendChatMessage(strLootList, "RAID_WARNING")
					
				
				-- insert here
				local strTexture = "|T" .. EasyLOP:getItemTexture(tTempLoots[iCurrentLootIndex].item) .. ":32:32|t" .. tTempLoots[iCurrentLootIndex].item
				--self:Print( "Texture string is:  " .. strTexture)
				SendAddonMessage("ELOP", "ELOP_SHOW_OPENBIDS^" .. strTexture, "RAID")
				--SendAddonMessage("ELOP_SHOW_OPENBIDS", tTempLoots[iCurrentLootIndex].item, "RAID")
			else
				--self:Print("iCurrentLootIndex is " .. iCurrentLootIndex .. " in LOOT_OPENED, bOverwrite == false block.")
				if bBidsActive == true then
					strStatus = "You are currently accepting bids for " .. tLoots[iCurrentLootIndex].item .. ".  To close this bidding session click 'yes' in the CloseBids window, or type /lop closebids."
				elseif bPendingAnnounce == true then
					strStatus = "You have closed bids on " .. tLoots[iCurrentLootIndex].item .. ".  The winners were:  "
					for i, winner in pairs(tWinners) do
						if winner.bidder == 0 then
							strStatus = strStatus .. "DE "
						else
							strStatus = strStatus .. winner.bidder .. " with a " .. winner.bidType .. " "
						end
					end
					
					strStatus = strStatus .. "   Click 'yes' on the Announce window, or type /lop announce to announce the winners and charge points."
				else
					strStatus = "The next item up for bids is " .. tLoots[iCurrentLootIndex].item .. "."
					--StaticPopup_Show ("BEGIN_BIDS", EasyLOP:getItemName(tLoots[iCurrentLootIndex].item))
					StaticPopup_Show ("BEGIN_BIDS", tLoots[iCurrentLootIndex].item)
				end
				
				self:Print(strStatus)
			end
		end
	else
		--self:Print("Nothing qualifies for master looter")
	end
end
--[[
function EasyLOP:LOOT_CLOSED()
	-- move all this shit to the top of LOOT_OPENED
	
	--Reset all variables
	bMLQualified = false
	iCurrentLootIndex = 0
	bBidsActive = false
	
	--reset loot table but keep copy of previous
	for i=1, numQualLoots, 1 do
		prevtLoots[i] = tLoots[i]
		tLoots[i] = nil
	end
	
	for i=1, numLoots, 1 do
		tLootList[i] = nil
	end
	
	numLoots = 0
	numQualLoots = 0
	
end
]]

function EasyLOP:Bid(a, b, c, d, e, f, g, h, i)
	itemstring = a
	
	if b ~= nil then itemstring = itemstring .. b end
	if c ~= nil then itemstring = itemstring .. c end
	if d ~= nil then itemstring = itemstring .. d end
	if e ~= nil then itemstring = itemstring .. e end
	if f ~= nil then itemstring = itemstring .. f end
	if g ~= nil then itemstring = itemstring .. g end
	if h ~= nil then itemstring = itemstring .. h end
	if i ~= nil then itemstring = itemstring .. i end
		
	--self:Print("Opening bids on " .. itemstring)
	
	if bSuspendProcess == true then
		self:Print("The looting process is currently locked by " .. addonOwner .. ".  All current loot must be assigned before a manual bidding session can be opened.  If this is an error, use /lop unlock.")
		return
	end
	
	-- you are here
	SendAddonMessage("ELOP", "ELOP_SET_SUSPEND^true " .. UnitName("player"), "RAID")
	SendAddonMessage("ELOP","ELOP_KILL_POPUPS^", "RAID")
	bBidsActive = false
	iCurrentLootIndex = 1
	SendAddonMessage("ELOP",  "ELOP_UPDATE_INDEX^" .. iCurrentLootIndex .. " " .. UnitName("player") .. " OpenBids", "RAID")				
	tLoots = {}
	SendAddonMessage("ELOP", "ELOP_CLEAR_TLOOTS^", "RAID")
	sendString = "1 1 " .. itemstring
	SendAddonMessage("ELOP", "ELOP_ADD_TLOOTS_ENTRY^".. sendString, "RAID")
	local strTexture = "|T" .. EasyLOP:getItemTexture(itemstring) .. ":32:32|t" .. itemstring
	SendAddonMessage("ELOP", "ELOP_SHOW_OPENBIDS^" .. strTexture, "RAID")
end

function EasyLOP:OpenBids()
	--Right now, this code assumes master looter
	bPendingAnnounce = false
	EasyLOP:ValidatePoints()
	tWinners = {}
	tHighBids = {}
	tBids = {}
	
	self:Print("Open Bids called!")
	strQuant = ""
	numTBD = 0
	
	if bBidsActive == true then
		--self:Print("triggered code:  OpenBids:  if bBidsActive == true")
		
		--self:Print("bBidsActive is " .. bBidsActive)
		--self:Print("iCurrentLootIndex is " .. iCurrentLootIndex)
		self:Print("An active bidding session is already open on " .. tLoots[iCurrentLootIndex] .. ".  Close the current session before starting a new one.")
		return
	end
	
	if tLoots[1] ~= nil and bMLQualified == true then
		while tLoots[iCurrentLootIndex] ~= nil and tLoots[iCurrentLootIndex].quant == 0 do
			iCurrentLootIndex = iCurrentLootIndex + 1
		end
		-- iCurrentLootIndex .. " " .. UnitName("player") .. " " .. callingFunct
		SendAddonMessage("ELOP", "ELOP_UPDATE_INDEX^" .. iCurrentLootIndex .. " " .. UnitName("player") .. " OpenBids", "RAID")
		--self:Print("numQualLoots is " .. numQualLoots)
		--self:Print("iCurrentLootIndex is " .. iCurrentLootIndex)
		
		if tLoots[iCurrentLootIndex] == nil then
			self:Print("All items have been assigned.")
		else
			if tLoots[iCurrentLootIndex].quant > 1 then
				strQuant = ".  Top " .. tLoots[iCurrentLootIndex].quant .. " bids win."
			end
			bBidsActive = true
			SendChatMessage("Send tells (Shroud/Standard) to " .. UnitName("player") .. " for " .. tLoots[iCurrentLootIndex].item .. strQuant, "RAID_WARNING")
			SendAddonMessage("ELOP", "ELOP_HIDE_OPENBIDS^", "RAID")
			StaticPopup_Hide("BEGIN_BIDS")
			StaticPopup_Show("CLOSE_BIDS", tLoots[iCurrentLootIndex].item)
		end
	else
		self:Print("Cannot open a loot session in Master Looter without a loot window open.")
	end
	
	if iCurrentLootIndex == nil or tLoots[iCurrentLootIndex] == nil then
		self:Print("All loot has been bid on already, or there has been an unexpected error.")
		return
	end
	
end

function EasyLOP:SendWinnerEntry(thisBid)

	sendString = ""
	sendString = sendString .. iCurrentLootIndex .. " " 
	sendString = sendString .. thisBid.bidder .. " " 
	sendString = sendString .. "&& " .. thisBid.bidType .. " && " 
	sendString = sendString .. thisBid.points .. " item: " 
	sendString = sendString .. thisBid.item 

	--self:Print("Sending addon msg: " .. sendString)
	SendAddonMessage("ELOP",  "ELOP_UPDATE_WINNER_ENTRY^".. sendString, "RAID")
end

function EasyLOP:CloseBids()
	bPendingAnnounce = false
	if bBidsActive == true then
		bBidsActive = false
		StaticPopup_Hide("CLOSE_BIDS")
	else
		self:Print("No active bid session to close.")
		return
	end
	
	-- This is not the most efficient way to write this code, but it is the easiest way to insert it from where I am right now.  If there is only one item,
	-- the following code works great.  Separate set of code to follow for dealing with multiple identical drops.
	if tLoots[iCurrentLootIndex].quant == 1 then 
		-- Determine what the highest bid / bids were by building a "highest bids" table - tHighBids, consisting of only the highest bids/bids.
		self:Print("-- Highest Bid(s) on " .. tLoots[iCurrentLootIndex].item .. " --")
		
		tHighBids = {}
		highestBid = 0
		bStandardFound = false
		bOnly1Shroud = false
		
		for i,bid in pairs(tBids) do
			if tBids[i].item == tLoots[iCurrentLootIndex].item then
				--self:Print( "i is: " .. i .. ", first while loop entered.")
				if tBids[i].bidType == 'save' then
					if highestBid <= 1 then
						highestBid = 1
						thisBid = { bidder = tBids[i].bidder, bidType = tBids[i].bidType, item = tBids[i].item, points = 0 }
						table.insert(tHighBids, thisBid)
						strColor = "|cff9d9d9d" --save color (grey)
					end
				elseif tBids[i].bidType == 'standard' then
					if highestBid <= 2 then
						if highestBid < 2 then
							tHighBids = {}
						end
						highestBid = 2
						thisBid = { bidder = tBids[i].bidder, bidType = tBids[i].bidType, item = tBids[i].item, points = 0 }
						table.insert(tHighBids, thisBid)
						strColor = "|cff1eff00" -- standard color (green)
					end
					bStandardFound = true
					--self:Print("Standard bid found.")
				else
					if highestBid <= 3 then
						if highestBid < 3 then
							tHighBids = {}
							bOnly1Shroud = true
						elseif highestBid == 3 then
							bOnly1Shroud = false
						end
						highestBid = 3
						thisBid = { bidder = tBids[i].bidder, bidType = tBids[i].bidType, item = tBids[i].item, points = tBids[i].points }
						table.insert(tHighBids, thisBid)
						strColor = "|cffe60000" -- shroud color (red)
					end
				end
				--self:Print(tBids[i].bidder .. ":  " .. strColor ..  tBids[i].bidType .. "|r")
			end
		end 
		
		-- Display the highest bidders to the user
		numBids = 0
		shroudString = ""
		for i,bid in pairs(tHighBids) do
			--self:Print( "i is: " .. i .. ", first while loop entered.")
			if tHighBids[i].bidType == 'save' then
				strColor = "|cff9d9d9d"
			elseif tHighBids[i].bidType == 'standard' then
				strColor = "|cff1eff00" 
			else
				strColor = "|cffe60000"
				shroudString = ", " .. tHighBids[i].points .. " points"
			end
			numBids = numBids + 1

			self:Print(tHighBids[i].bidder .. ":  " .. strColor ..  tHighBids[i].bidType .. "|r" .. shroudString)
		end
		
		if highestBid == 0 then
			self:Print("None")
		end
		
		-- If only one high bidder or no high bidder, decide the winner!  This is done by assigning the tWinners[1] variable, which is then referenced in AcceptAnnounce
		if numBids < 2 or bOnly1Shroud then
			SendChatMessage("Bidding now closed on " .. tLoots[iCurrentLootIndex].item, "RAID_WARNING")
			bPendingAnnounce = true
			
			if numBids == 0 then
				--strPopup = "No bids received.  Do you want to announce that " .. tLoots[iCurrentLootIndex] .item.. " will be DE'ed?"
				strAnnouncement = "No bids!  Grats DE/greed!"
				deBid = {bidder = 0, bidType = 0, points = 0, item = tLoots[iCurrentLootIndex].item}
				tWinners[1] = deBid
				--table.insert(tLoots[iCurrentLootIndex].winbid, tWinners[1])
				EasyLOP:SendWinnerEntry(deBid)
				--EasyLOP:LogEvent("Disenchant", "", "", UnitName("player"), "", tLoots[iCurrentLootIndex].item)
				sendString = UnitName("player") .. " && " .. tLoots[iCurrentLootIndex].item
				SendAddonMessage("ELOP", "ELOP_SYNCDELOG^" .. sendString, "RAID")
				
				if EasyLOP:IsRecipe(tLoots[iCurrentLootIndex].item) == false then
					StaticPopup_Show("NO_BIDDERS", tLoots[iCurrentLootIndex].item)
				else
					self:Print("Recipes are not eligible for automatic greed distribution or disenchanting.")
					StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item, "DE")
				end
				--self:Print("Adding DE bid to tLoots.winbid")
			elseif numBids == 1 or bOnly1Shroud == true then
				if tHighBids[1].bidType == 'shroud' and bStandardFound == false then
					tHighBids[1].bidType = 'shroud converted to standard'
				end
				--strPopup = "Do you want to announce " .. tHighBids[1].bidder .. " as the winner of the " .. tHighBids[1].item .. " on a " .. tHighBids[1].bidType .. "?"
				strAnnouncement = tHighBids[1].bidder .. " wins with a " .. tHighBids[1].bidType .. "!  Grats on your shiny new " .. tHighBids[1].item .. "!"
				tWinners[1] = {bidder = tHighBids[1].bidder, bidType = tHighBids[1].bidType, points = 0, item = tHighBids[1].item}
				--table.insert(tLoots[iCurrentLootIndex].winbid, tWinners[1])
				EasyLOP:SendWinnerEntry(tWinners[1])
				StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item, tWinners[1].bidder .. "  Announce now?")
			end
		else
			-- Call for rolls on saves / standards
			--self:Print("Now evaluating to see if highest bid is std or save.")
			if highestBid <= 2 then  -- Call for rolloff on standard / save bids
				--self:Print("Highest bid is std or save, now calling 'CallForRolls' funct.")
				--- Analyze or perform rolls, assign winner to tWinners[1] -- all done in CHAT_MSG_SYSTEM funct
				EasyLOP:CallForRolls(tHighBids[1].bidType, tHighBids, "")
			else  -- Compare points totals for Shroud bids and call winner
				--SendChatMessage( "Shroud comparisons must be done, please wait!", "RAID_WARNING")
				
				-- insert code to handle shroud ties
				
				tempWinner = {bidder = "no one", bidType = "shroud", points = 0, item = "nothing"}
				
				tWinners[1] = {bidder = "no one", bidType = "shroud", points = 0, item = "nothing"}
				
				-- Determine highest points
				for i, bid in pairs(tHighBids) do
					thesePoints = EasyLOP:GetPoints(tHighBids[i].bidder)
					if thesePoints > tempWinner.points then
						tempWinner.points = thesePoints
						tempWinner.bidder = tHighBids[i].bidder
						tempWinner.item = tHighBids[i].item
					end
				end
				
				-- Check for ties.  If there are ties, go to rolloff.  If not, announce winner.
				tTieShrouds = {}
				bShrTie = false
				shrAmt = 0
				
				for i, bid in pairs(tHighBids) do
					thesePoints = EasyLOP:GetPoints(tHighBids[i].bidder)
					--if thesePoints == tempWinner.points then - bad.
					if thesePoints == tempWinner.points and bid.bidder ~= tempWinner.bidder then
						addTie = {}
						shrAmt = thesePoints
						addTie.points = 0
						addTie.bidder = tHighBids[i].bidder
						addTie.item = tHighBids[i].item
						addTie.bidType = tHighBids[i].bidType
						table.insert (tTieShrouds, addTie)
						bShrTie = true
					end
				end
								
				if bShrTie == true then
					tempWinner.points = 0
					table.insert(tTieShrouds, tempWinner)
					
					tHighBids = {}
					for i, bid in pairs(tTieShrouds) do
						table.insert(tHighBids, bid)
					end
					
					tTieShrouds = {}
										
					EasyLOP:CallForRolls(tHighBids[1].bidType, tHighBids, "Multiple shrouders with " .. shrAmt .. " points!  ")
					return
				else
					tWinners[1].points = tempWinner.points
					tWinners[1].bidder = tempWinner.bidder
					tWinners[1].item = tempWinner.item
				end
				
				if tWinners[1].points < 100 then 
					strAnnouncement = tWinners[1].bidder .. " wins with a " .. tWinners[1].points .. "-point Shroud!  Grats on your shiny new " .. tWinners[1].item .. "!"
				elseif tWinners[1].points < 200 then
					strAnnouncement = "BOMBS AWAY!  " .. tWinners[1].bidder .. " wins with a " .. tWinners[1].points .. "-point Shroud bomb!  Grats on your shiny new " .. tWinners[1].item .. "!"
				else
					strAnnouncement = "Um...  I think " .. tWinners[1].bidder .. " wins with a " .. tWinners[1].points .. "-point Shroud.  Grats on your long-awaited " .. tWinners[1].item .. "!!"
				end
				
				EasyLOP:SendWinnerEntry(tWinners[1])
				
				SendChatMessage("Bidding now closed on " .. tLoots[iCurrentLootIndex].item, "RAID_WARNING")
				bPendingAnnounce = true
				StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item, tWinners[1].bidder .. "  Announce now?")
			end 
		end
	-- Code for multiple identical drops here
	elseif tLoots[iCurrentLootIndex].quant > 1 then
		tSaves = {}
		tStandards = {}
		tShrouds = {}
		numDE = 0
		numSaves = 0
		numStandards = 0
		numShrouds = 0
		lowShroud = 1000000
		lowIndex = 0
		numWinners = 0
		
		bIncludeStd = false
		bIncludeSave = false
		bDEs = false
		bSCS = false -- shroud converts to standard?
		
		-- Display all bids to user
		numBids = 0
		shroudString = ""
		for i,bid in pairs(tBids) do
			--self:Print( "i is: " .. i .. ", first while loop entered.")
			if tBids[i].bidType == 'save' then
				strColor = "|cff9d9d9d"
			elseif tBids[i].bidType == 'standard' then
				strColor = "|cff1eff00" 
			else
				strColor = "|cffe60000"
				shroudString = ", " .. tBids[i].points .. " points"
			end
			numBids = numBids + 1

			self:Print(tBids[i].bidder .. ":  " .. strColor ..  tBids[i].bidType .. "|r" .. shroudString )
		end
		
		if numBids == 0 then
			self:Print("None")
		end
		
		-- Split all bids into their respective tables
		for i, bid in pairs(tBids) do
			if tBids[i].bidType == 'save' then
				table.insert(tSaves, tBids[i])
				numSaves = numSaves + 1
			elseif tBids[i].bidType == 'standard' then
				table.insert(tStandards, tBids[i])
				numStandards = numStandards + 1
			else
				table.insert(tShrouds, tBids[i])
				numShrouds = numShrouds + 1
			end
		end
		
		-- If there are enough shrouds to cover all drops, determine winners immediately and assign to tWinners.
		if numShrouds >= tLoots[iCurrentLootIndex].quant then
						
			for i, bid in pairs(tShrouds) do
				thesePoints = tShrouds[i].points
				
				-- Determine the lowest current Shroud bid
				for ii, biid in pairs(tWinners) do
					if tWinners[ii].points < lowShroud then
						lowShroud = tWinners[ii].points
						lowIndex = ii
					end
				end
				
				-- If this shroud bid is higher than the lowest currently winning shroud bid, remove the low bid and replace with this one
				if numWinners < tLoots[iCurrentLootIndex].quant then
					--self:Print("Adding " .. tShrouds[i].bidder .. " to tWinners.")
					numWinners = numWinners + 1
					table.insert(tWinners, tShrouds[i])
				elseif thesePoints > lowShroud and numWinners == tLoots[iCurrentLootIndex].quant then
					--self:Print("Removing " .. tWinners[lowIndex].bidder .. "from tWinners.")
					table.remove(tWinners, lowIndex)
					--self:Print("Adding " .. tShrouds[i].bidder .. " to tWinners.")
					table.insert(tWinners, tShrouds[i])
					
					--reset the lowest current Shroud bid
					lowShroud = 1000000
					lowIndex = 0
				else
					--self:Print("Discarding " .. tShrouds[i].bidder .. "'s bid - beat out on points!")
				end
			end
						
			-- Determine whether there are any ties with the lowest shroud bid.
			-- Determine the lowest winning Shroud bid
			numWinners = 0
			for ii, biid in pairs(tWinners) do
				numWinners = numWinners + 1
				if tWinners[ii].points < lowShroud then
					lowShroud = tWinners[ii].points
					lowIndex = ii
				end
				
				-- Remove winning bids from tShroud so they don't get counted below
				RemoveI = 0
				for i, bid in pairs(tShrouds) do
					if bid.bidder == biid.bidder then
						RemoveI = i
					end
				end
				
				if RemoveI > 0 then
					table.remove(tShrouds, RemoveI)
				end
			end
									
			-- find all ties to the lowest winning shroud bid in the list of shroud bids
			shrTie = false
			shrTiePoints = 0
			tTieShrouds = {}
			
			for i, bid in pairs(tShrouds) do
				if bid.points == lowShroud then
					shrTie = true
					shrTiePoints = lowShroud
					table.insert(tTieShrouds, {bidder = bid.bidder, points = 0, bidType = bid.bidType, item = bid.item})
				end
			end
			
			-- If there are any ties, remove tied bids from the winner list and add them to a table to be rolled off.
			if shrTie == true then
				self:Print("Shroud tie found.")
				tRemoveIndices = {}
				
				for i, bid in pairs(tWinners) do
					--self:Print(tWinners[i].points .. " vs " .. shrTiePoints)
					if tWinners[i].points == shrTiePoints then
						table.insert(tTieShrouds, {bidder = bid.bidder, points = 0, bidType = bid.bidType, item = bid.item})
						table.insert(tRemoveIndices, i)
						numWinners = numWinners - 1
					end
				end
				
				for i, ind in pairs(tRemoveIndices) do
					table.remove(tWinners, ind)
				end
				
				-- Announce winner(s) if there is one, and call for rolloffs on shrouds.
				EasyLOP:HandleMultiples(tTieShrouds)
				
				return
			end
				
			
			-- If there are enough drops to cover ALL shroud and standard bids made, all shrouds convert to standards
			if tLoots[iCurrentLootIndex].quant >= numShrouds + numStandards then
				bSCS = true
				for i, winners in pairs(tWinners) do
					tWinners[i].bidType = "shroud converted to standard"
				end
			end
			
			--- SET UP THE STRANNOUNCEMENT 
			strAnnouncement = "The following Shroud bidders win a " .. tLoots[iCurrentLootIndex].item .. ": "
			for i, bid in pairs(tWinners) do
				if tWinners[i + 1] == nil then
					strAnnouncement = strAnnouncement .. "and "
				end

				--self:Print ("Adding " .. tWinners[i].bidder .. " to strAnnouncement.")
				strAnnouncement = strAnnouncement .. tWinners[i].bidder 
				
				if tWinners[i + 1] == nil then
					if bSCS == false then
						strAnnouncement = strAnnouncement .. "!"
					else
						if tLoots[iCurrentLootIndex].quant == 2 then
							strAnnouncement = strAnnouncement .. ", both converted to standard!"
						else
							strAnnouncement = strAnnouncement .. ", all converted to standard!"
						end
					end
				else
					if i == 1 and tWinners[i + 2] == nil then
						strAnnouncement = strAnnouncement .. " "
					else
						strAnnouncement = strAnnouncement .. ", "
					end
				end
			end
			
			-- Add record of winners to tLoots
			winnerList = ""
			for i, bid in pairs (tWinners) do
				--table.insert(tLoots[iCurrentLootIndex].winbid, bid)
				EasyLOP:SendWinnerEntry(bid)
				winnerList = winnerList .. bid.bidder .. " " 
			end
			
			SendChatMessage("Bidding now closed on " .. tLoots[iCurrentLootIndex].item, "RAID_WARNING")

			bPendingAnnounce = true
			StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item .. "x" .. tLoots[iCurrentLootIndex].quant, winnerList .. ".  Announce now?")
		-- Otherwise, determine how many rolls will be needed.
		else
			-- There are not enough shrouds to cover all items, so we know all shrouds win.  Add Shroud bidders to tWinners.  These are all converted down to standards.
			for i, bid in pairs(tShrouds) do
				if tLoots[iCurrentLootIndex].quant >= numShrouds + numStandards then
					tShrouds[i].bidType = "shroud converted to standard"
				end
				table.insert(tWinners, tShrouds[i])
				--self:Print("Adding " .. tShrouds[i].bidder .. " to tWinners as a shroud.")
				numWinners = numWinners + 1
			end
			
			-- If there also aren't enough standards (or exactly enough) to cover the rest of the drops, add all standards to tWinners.  
			-- If there are more standards than there are remaining drops, rolloffs will be needed.
			if numStandards + numWinners <= tLoots[iCurrentLootIndex].quant then
				for i, bid in pairs(tStandards) do
					table.insert(tWinners, tStandards[i])
					numWinners = numWinners + 1
				end
			elseif numStandards > 0 then
				-- Call for rolloff between all standard bidders and go no further
				--self:Print("Call for std rolloffs, operation terminated.")
				EasyLOP:HandleMultiples(tStandards)
				return
			end
			
			-- If there aren't enough (or are exactly enough) saves to cover the remaining drops, add all save bids to tWinners.
			-- If there are more save bids than there are remaining drops, call for rolloffs.
			if numSaves + numWinners <= tLoots[iCurrentLootIndex].quant then
				for i, bid in pairs(tSaves) do
					table.insert(tWinners, tSaves[i])
					numWinners = numWinners + 1
				end
			elseif numSaves > 0 then
				-- Call for rolloff between all save bidders and go no further
				--self:Print("Call for save rolloffs, operation terminated.")
				EasyLOP:HandleMultiples(tSaves)
				return
			end
		
			-- Everything left goes to DE
			for i = 1, tLoots[iCurrentLootIndex].quant - numShrouds - numStandards - numSaves, 1 do
				--self:Print("Added one " ..  tLoots[iCurrentLootIndex].item .. " to tWinners as DE.")
				numDE = numDE + 1
				table.insert(tWinners, {bidder = 0, bidType = 0, points = 0, item = tLoots[iCurrentLootIndex].item})
			end

			-- keep record of wins in tLoots
			for i, bid in pairs (tWinners) do
				--table.insert(tLoots[iCurrentLootIndex].winbid, bid)
				EasyLOP:SendWinnerEntry(bid)
			end
			
			-- Set up Winners announcement
			winnerList = ""
			strAnnouncement = tLoots[iCurrentLootIndex].item .. "x" .. tLoots[iCurrentLootIndex].quant .. ":  Grats to "
			if tLoots[iCurrentLootIndex].quant > numDE then
				for i, result in pairs(tWinners) do
					if tWinners[i].bidder ~= 0 then
						if tWinners[i + 1] == nil and i ~= 1 then
							strAnnouncement = strAnnouncement .. "and "
						end

						--self:Print ("Adding " .. tWinners[i].bidder .. " to strAnnouncement.")
						strAnnouncement = strAnnouncement .. tWinners[i].bidder .. " on a " .. tWinners[i].bidType
						
						if tWinners[i + 1] == nil then
							strAnnouncement = strAnnouncement .. "!"
							--self:Print("numDE is " .. numDE)
							if numDE == 1 then
								strAnnouncement = strAnnouncement .. "  The last one goes to DE."
							elseif numDE > 1 then
								strAnnouncement = strAnnouncement .. "  The other " .. numDE .. " go to DE."
							end
						elseif tWinners[i + 1].bidder ~= 0 then
							if i == 1 and tWinners[i + 2] == nil then
								strAnnouncement = strAnnouncement .. " "
							else
								strAnnouncement = strAnnouncement .. ", "
							end
						end
						winnerList = winnerList .. tWinners[i].bidder .. " "
					else
						if tWinners[i + 1] == nil then
							strAnnouncement = strAnnouncement .. "!"
							--self:Print("numDE is " .. numDE)
							if numDE == 1 then
								strAnnouncement = strAnnouncement .. "  The last one goes to DE."
							elseif numDE > 1 then
								strAnnouncement = strAnnouncement .. "  The other " .. numDE .. " go to DE."
							end
						else
							if i == 1 and tWinners[i + 2] == nil then
								strAnnouncement = strAnnouncement .. " "
							else
								strAnnouncement = strAnnouncement .. ", "
							end
						end
						--winnerList = winnerList .. "DE" .. " "
					end
				end
			else
				if numDE == 2 then 
					strAnnouncement = strAnnouncement .. "no one!  Both to DE."
				elseif numDE > 2 then
					strAnnouncement = strAnnouncement .. "the raid on a lotta of greed loot!  All " .. tLoots[iCurrentLootIndex].quant .. " to DE."
				end
			end
			SendChatMessage("Bidding now closed on " .. tLoots[iCurrentLootIndex].item, "RAID_WARNING")
			bPendingAnnounce = true
			StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item .. "x" .. tLoots[iCurrentLootIndex].quant, winnerList .. ".  Announce now?")
		end
		
		if numDE > 0 then
			winnerList = winnerList .. "DEx" .. numDE .. " "
		end
		

	end
end

function EasyLOP:AcceptAnnouncement()
	if bPendingAnnounce == false then
		self:Print("Can only announce a winner after determining one using EasyLOP.  If you determined a winner earlier but didn't use the addon to announce it, use '/lop charge <playername> <bidtype>' to manually charge them for the purchase.")
		return
	end
	
	bPendingAnnounce = false

	--Insert code for modifying points.  Generate a message to all addon users to decrement
	for i, winners in pairs(tWinners) do
		if winners.bidder ~= 0 and winners.bidder ~= "" then
			oldPts = EasyLOP:GetPoints(winners.bidder)
			
			if bOverrideSync == false then
				strOS = "FALSE"
			else
				strOS = "TRUE"
			end
			
			--self:Print("Calling Modifypoints; bOverrideSync is " .. strOS)
			charged = EasyLOP:ModifyPoints(tWinners[i].bidder, tWinners[i].bidType, tLoots[iCurrentLootIndex].item)
			--self:Print("Done in ModifyPoints; bOverrideSync is " .. strOS)
			if charged == nil then 
				charged = 0
			end
			self:Print(tWinners[i].bidder .. " has been charged " .. charged .. " for a " .. tWinners[i].bidType .. " bid.  Old points:  " .. oldPts .. "   New points:  |cffe60000" .. EasyLOP:GetPoints(winners.bidder) .. "|r" )
			-- sync all users
			bOverrideSync = true
			bSkipSyncMessage = true
			strSync = tWinners[i].bidder .. " " .. EasyLOP:GetPoints(tWinners[i].bidder) .. ".0"
			SendAddonMessage("ELOP", "ELOP_SYNCPOINTS^" .. strSync, "RAID")
		end
	end
	
	-- Auto-award loot-----
	
	if lootSystem == 'master' and tLoots[iCurrentLootIndex].quant == 1 and bAutoAward == true then -- review for automatic distribution to Winner
		
		strRecipient = tWinners[1].bidder
		
		
		--self:Print("Now cycling through raid looking for " .. strRecipient .. ".")
		
		if strRecipient ~= 0 then
			
			--self:Print("IsML is returning: " .. EasyLOP:IsML(UnitName("player")))
			
			if EasyLOP:IsML(UnitName("player")) == false then
				sendString = strRecipient .. " & " .. tLoots[iCurrentLootIndex].item   -- you are here
				self:Print("Sending message to ML...")
				SendAddonMessage("ELOP", "ELOP_SENDTOML^".. sendString, "RAID")
			else
				--self:Print("isML returned true.")
				bRecipientFound = false
				for i=1, 40 do
					self:Print( "i is " .. i )
					name = GetMasterLootCandidate(i, 1)
					if name ~= nil then
						--self:Print( "Looking at " .. string.lower(name) .. " as possible DEer/Greeder.  iteration " .. i)
						if string.lower(name) == string.lower(strRecipient) then
							bRecipientFound = true
							for ii=1, numLoots, 1 do
								if LootSlotHasItem(ii) then
									--self:Print("Looking at " .. GetLootSlotLink(ii) .. " as item to be DEed/Greeded.")
									--self:Print("The item that should be DEed/greeded is: " .. tWinners[1].item)
									if GetLootSlotLink(ii) == tWinners[1].item then
										GiveMasterLoot(ii,i)
										ii = numLoots
									end
								else
									--self:Print("Looking at money.")
								end
							end
						end
					end				
				end
				if bRecipientFound == false then
					self:Print("No player named " .. tWinners[1].bidder .. " found as eligible to receive loot currently.  The player may be too far away, or ineligible to recieve this loot.  Please hand out loot manually.")
				end
			end
		
		else
			-- merge with DE code below
			-- self:Print("DE.")
		end
	end
	
	-- If there are additional possible winners (ie, multiple drops triggered some winners and some rollers), clear out tWinners and wait for the rolls.
	if numTBD > 0 then
		tWinners = {}
		EasyLOP:CallForRolls(tHighBids[1].bidType, tHighBids, strAnnouncement)
		return
	else
		SendChatMessage( strAnnouncement, "RAID_WARNING")
	end
	
	--self:Print( "Winner is:  " .. tWinners[1].bidder)
	--self:Print( "Current DEer is:  " .. self.DEer)
	--self:Print( "Loot System is:  " .. lootSystem)
	--self:Print( "Item under review is:  " .. tWinners[1].item)
	
	-- The following code automatically assigns DE loot to the designated DEer.  It specifically excludes auto-loot assignment to DEer in the case of multiple drops
	-- with the same name, as those are likely to be tokens and will require specific handling by the raid lead.  It also will not auto-assign patterns since those can be handled oddly sometimes.
	
	
	if tWinners[1].bidder == 0 and lootSystem == 'master' and tLoots[iCurrentLootIndex].quant == 1 then -- review for automatic distribution to DE/Greed
		
		strRecipient = ""
		if bSendToGreed == false then
			if self.DEer == "" then
            
				--self:Print ("Cannot automatically give loot to DEer because no DEer is set.  Use /lop setde <characer name> to assign a DEer.")
			
            else
				strRecipient = string.lower(self.DEer)
			end
		else
			if self.Greeder == "" then
			
                --self:Print ("Cannot automatically give loot to designated Greeder because no Greeder is set.  Use /lop setgreed <characer name> to assign a Greeder.")
			
            else
				strRecipient = string.lower(self.Greeder)
			end
		end
		
		--self:Print("Now cycling through raid looking for " .. strRecipient .. ".")
		
		if strRecipient ~= "" then
			bRecipientFound = false
			for i=1, 40, 1 do
			
                --self:Print( "i is " .. i )
				
                name = GetMasterLootCandidate(i)
				--name = GetRaidRosterInfo(i)  - do not use this code, it gives loot to the wrong person
				if name ~= nil then
				
                    --self:Print( "Looking at " .. string.lower(name) .. " as possible DEer/Greeder.  iteration " .. i)
					
                    if string.lower(name) == strRecipient then
						bRecipientFound = true
						for ii=1, numLoots, 1 do
							if LootSlotHasItem(ii) then
					
                                --self:Print("Looking at " .. GetLootSlotLink(ii) .. " as item to be DEed/Greeded.")
								--self:Print("The item that should be DEed/greeded is: " .. tWinners[1].item)
								
								-- insert code to check to see if user is ML - if not, and loot system is ML, SendAddonMessage to find the ML and trigger a send of the item if they have the loot window open.
								if GetLootSlotLink(ii) == tWinners[1].item then
									GiveMasterLoot(ii,i)
									ii = numLoots
								end
							else
								--self:Print("Looking at money.")
							end
						end
					end
				end
			end
		
			if bRecipientFound == false and bSendToGreed == false then
				self:Print("No player named " .. self.DEer .. " found as eligible to receive loot currently.  The player may be too far away, or ineligible to recieve this loot.  Please hand out loot manually.")
			elseif bRecipientFound == false and bSendToGreed == true then
				self:Print("No player named " .. self.Greeder .. " found as eligible to receive loot currently.  The player may be too far away, or ineligible to recieve this loot.  Please hand out loot manually.")
			end
		end
	end
	
	-- Update quant on this item to 0 for all addons.
	tLoots[iCurrentLootIndex].quant = 0
	--for incindex, incquant, incitem in string.gmatch(msg, "(%d+) (%d+) (.+)") do
	sendString = ""
	sendString = iCurrentLootIndex .. " " .. "0" .. " " .. tLoots[iCurrentLootIndex].item
	SendAddonMessage("ELOP", "ELOP_UPDATE_QUANT^" .. sendString, "RAID")
	
	--self:Print(GetMasterLootCandidate(2))
	--GiveMasterLoot(3,1)
	
	
	-- Assign current tBids to tPrevBids; clear out tBids
	for i, bid in pairs(tBids) do
		table.insert(tPrevBids, bid)
	end
	
	tBids = {}
	tWinners = {}
	
	-- If there's more loot to assign, prompt user to call for it.
	--self:Print("Entering increment loop.  icl is " .. iCurrentLootIndex .. " and quant at that index is " .. tLoots[iCurrentLootIndex].quant .. ".")
	while tLoots[iCurrentLootIndex] ~= nil and tLoots[iCurrentLootIndex].quant == 0  do
		iCurrentLootIndex = iCurrentLootIndex + 1
		--self:Print("iCurrentLootIndex updated to " .. iCurrentLootIndex .. ".")
	end
	-- iCurrentLootIndex .. " " .. UnitName("player") .. " " .. callingFunct
	SendAddonMessage("ELOP", "ELOP_UPDATE_INDEX^" .. iCurrentLootIndex .. " " .. UnitName("player") .. " AcceptAnnouncement", "RAID")
	
	if tLoots[iCurrentLootIndex] ~= nil then
		--StaticPopup_Show ("BEGIN_BIDS", EasyLOP:getItemName(tLoots[iCurrentLootIndex].item))
		SendAddonMessage("ELOP", "ELOP_SHOW_OPENBIDS^" .. tLoots[iCurrentLootIndex].item, "RAID")
	else
		SendAddonMessage("ELOP", "ELOP_SET_SUSPEND^false " .. UnitName("player"), "RAID")
		tRollItems = {}
	end
end

function EasyLOP:IsRecipe(itemlink)
	if itemlink ~= nil then
		itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemlink)
		if itemType ~= nil and itemType == "Recipe" then
			return true
		else
			return false
		end
	end
end

function EasyLOP:HandleMultiples(tBidsTable)
	tHighBids = {}
	--self:Print("tHighBids cleared in HandleMultiples.")
	
	--self:Print("Calling HandleMultiples")
	
	for i, bid in pairs(tBidsTable) do
		table.insert(tHighBids, tBidsTable[i])
		--self:Print("Added " .. bid.bidder .. " to tHighBids in HandleMultiples.")
	end

	strAnnouncement = tLoots[iCurrentLootIndex].item .. "x" .. tLoots[iCurrentLootIndex].quant .. ":  "
	
	if tWinners[1] ~= nil then
		strAnnouncement = strAnnouncement .. "Grats to "
	end
	
	numWinners = 0
	for i, result in pairs(tWinners) do
		numWinners = numWinners + 1

		if tWinners[i + 1] == nil and i ~= 1 then
			strAnnouncement = strAnnouncement .. "and "
		end
			
		--self:Print ("Adding " .. tWinners[i].bidder .. " to strAnnouncement.")
		strAnnouncement = strAnnouncement .. tWinners[i].bidder .. " on a " .. tWinners[i].bidType
			
		if tWinners[i + 1] == nil then
			strAnnouncement = strAnnouncement .. ", AND "
		else
			if i == 1 and tWinners[i + 2] == nil then
				strAnnouncement = strAnnouncement .. " "
			else
				strAnnouncement = strAnnouncement .. ", "
			end
		end
	end

	-- keep record of wins in tLoots
	winnerList = ""
	for i, bid in pairs (tWinners) do
		--table.insert(tLoots[iCurrentLootIndex].winbid, bid)
		EasyLOP:SendWinnerEntry(bid)
		winnerList = winnerList .. bid.bidder .. " " 
	end
	
	numTBD = tLoots[iCurrentLootIndex].quant - numWinners
	bPendingAnnounce = true
	strDialog = ""
	
	if winnerList == "" then
		winnerList = "None yet"
	end
	
	StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item .. "x" .. tLoots[iCurrentLootIndex].quant, winnerList .. ".  One or more rolloffs are pending.  Click 'Announce & Charge' to call for rolls.")
end

function EasyLOP:LOOT_SLOT_CLEARED(iSlotCleared)
	if bMLQualified == true and LootSlotHasItem(iSlotCleared) then
		local sName, sLink, iRarity, iLevel, iMinLevel, sType, sSubType, iStackCount = GetItemInfo(tLootList[iSlotCleared])
		--self:Print( sLink .. " looted.")
		if iRarity > iRarityThreshold and sName ~= "Badge of Justice" then
			for i=1, numQualLoots, 1 do
				if tLoots[i].item == sLink then
					tLoots[i].quant = tLoots[i].quant - 1
					sendString = "" 
					sendString = sendString .. i .. " " .. tLoots[i].quant .. " " .. tLoots[i].item
					SendAddonMessage("ELOP", "ELOP_UPDATE_QUANT^" .. sendString, "RAID")
					--self:Print("tLoots[" .. i .. "] cleared to zero due to looting of " .. sName .. ".")
				end
			end
		end
	end
end

-- When combat ends, capture current loot system.
function EasyLOP:PLAYER_REGEN_ENABLED()
	-- capture loot system
	lootSystem, throwaway, masterLooterID = GetLootMethod()
end

function EasyLOP:PARTY_LOOT_METHOD_CHANGED()
	lootSystem, throwaway, masterLooterID = GetLootMethod()
	if lootSystem == 'master' then
		local masterLooterName = GetRaidRosterInfo(masterLooterID)
		self:Print("Captured change in loot system.  Master Looter is now " .. masterLooterName)
	else
		self:Print("Captured change in loot system.  Master Looter no longer being used.")
	end
end

function EasyLOP:VerCheck()
	--[[ Build list of current leads in raid - maybe later
	tRaidLeads = {}
	for i=1, 40, 1 do
		name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
		if rank > 0 then
			local t={}
			t.name = name
			t.version = 0
			table.insert(tRaidLeads,t)
		end
	end
	
	-- Print current raid leads
	s = ""
	for entry in pairs(tRaidLeads) do
		s = s .. entry.name .. " " 
	end
	self:Print("Raid leads are: " .. s)]]
	
	-- Ask other addons what version they have
	bWaitingOnVerCheck = true
	--[[ Start timer
	EasyLOP:ScheduleRepeatingEvent("canceltse", tse, 3, self)
	]]
	SendAddonMessage("ELOP", "ELOP_VERCHECK^", "RAID")
end

-- This event gives no info about the event itself, such as who joined the raid.  Have to find that ourselves.
function EasyLOP:RAID_ROSTER_UPDATE()
	--[[self:Print("RAID_ROSTER_UPDATE triggered.")
	tRaidMembers = {}
	
	for i=1, 40, 1 do
		iName, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
		if iName ~= nil then
			entry = {iName=i}
			table.insert(tRaidMembers, entry)
			self:Print("Adding " .. iName .. " as " .. i)
		end
	end
	
	for i, item in pairs(tRaidMembers) do
		self:Print( i .. ":  " .. tRaidMembers[i])
	end
	]]
	--self:Print("Number for Elkheart: " .. tRaidMembers["Elkheart"] .. ".")
	--self:Print("Number for Lyseira: " .. tRaidMembers["Lyseira"] .. ".")
end

function EasyLOP:COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName, spellSchool)
	--[[if spellName ~= nil then
		if string.lower(spellName) == "throw key" or string.lower(spellName) == "heavy leather ball" then
			if event == "SPELL_CAST_SUCCESS" then
				raidPos = 0
				for i=1, 40, 1 do
					iName, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
					-- A note about raidIndex:  it has NOTHING TO DO with the player's current slot location in the raid window.  Zilch.
					if iName == destName then
						raidPos = i
						--self:Print("Found " .. name .. " at raid position " .. i .. ".")
					end
				end
				
				if raidPos ~= nil then
					raidPos = "raid" .. raidPos
					SetRaidTarget(raidPos, 4)
				end	
			end
		end
	end]]  -- good code, uncomment for Vashj
	--[[
	if bVashjTest == true or GetNumRaidMembers() > 6 then
		--if timestamp ~= nil and event ~= nil and sourceGUID ~= nil and sourceName ~= nil and destGUID ~= nil and destName ~= nil then
		--self:Print("destName was " .. destName)
		if destName ~= nil then
			--self:Print("Timestamp:  " .. timestamp .. " Event: " .. event .. " sourceGUID: " .. sourceGUID .. " SourceName:  " .. sourceName .. " destGUID: " .. destGUID .. " DestName:  " .. destName)
			--self:Print("spellName was " .. spellName)
			--if spellID ~= nil and spellName ~= nil and spellSchool ~= nil then
			if spellName ~= nil then
				--self:Print("spellID:  " .. spellID .. " spellName:  " .. spellName .. " spellSchool:  " .. spellSchool)
				if string.lower(spellName) == ("throw key") or string.lower(spellName) == ("heavy leather ball") then
					raidPos = 0
					for i=1, 40, 1 do
						iName, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
						-- A note about raidIndex:  it has NOTHING TO DO with the player's current slot location in the raid window.  Zilch.
						if iName == destName then
							raidPos = i
							--self:Print("Found " .. name .. " at raid position " .. i .. ".")
						end
					end
				end
			else
				--self:Print("Spell info not provided.")
			end
		else
			--self:Print("Combat log entry had no destName!")
		end
	end]]
end

function EasyLOP:START_LOOT_ROLL( rollID, rollTime)
	--[[self:Print("rollID is: " .. rollID .. ".  rollTime is:  " .. rollTime .. ".")
	link = GetLootRollItemLink(rollID)
	self:Print("Link is " .. link .. ".")
	
	table.insert(tRollItems, link)]]
end

function EasyLOP:CHAT_MSG_LOOT(strContent)
	-- Code for Vashj Test - tainted core marking.  Change "linen cloth" to "Tainted Core" to make this functional
	if bVashjTest == true and GetNumGroupMembers() > 6 then
		--self:Print("Vashj Test initiated.")
		--[[
		for name, itemName in string.gmatch(strContent, "(%a+) receive loot: (.+)") do 
			self:Print("Name was " .. name .. ", item name was " .. itemName .. ".")
		end]]
		bMarked = false
		for name, itemName in string.gmatch(strContent, "(%a+) receives loot: (.+)") do 
			--self:Print("Captured player '" .. name .. "'  picking up item:  " .. itemName)
			if string.find(itemName, "Tainted Core") ~= nil then
				raidPos = 0
				for i=1, 40, 1 do
					iName, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
					-- A note about raidIndex:  it has NOTHING TO DO with the player's current slot location in the raid window.  Zilch.
					if iName == name then
						raidPos = i
						--self:Print("Found " .. name .. " at raid position " .. i .. ".")
					end
				end
				raidPos = "raid" .. raidPos
				SetRaidTarget(raidPos, 4)
				bMarked = true
			end
		end
		
		if bMarked == true then
			return
		end
		
		for name, itemName in string.gmatch(strContent, "(%a+) receive loot: (.+)") do 
			if name == "You" then
				name = UnitName("player")
			end
			
			--self:Print("Captured player '" .. name .. "'  picking up item:  " .. itemName)
			if string.find(itemName, "Tainted Core") ~= nil then
				SetRaidTarget("player", 4)
			end
		end
	end
	
	-- Code for filling in tLoots and prompting for a bidding session, when in group loot.
	--[[
	if tRollItems[i] ~= nil then
		if string.find(strContent, "passed on") then
			EasyLOP:GroupLoot_BuildTLoots()
		end
	end
	]]
end

function EasyLOP:CHAT_MSG_RAID(msg, author, lang)
	if bRolloffs == true and string.lower(msg) == "pass" then
		--self:Print("Pass message detected.")
		for i, bid in pairs(tHighBids) do
			--self:Print("For loop entered.  Comparing " .. tHighBids[i].bidder .. " to " .. author .. ".")
			if tHighBids[i].bidder == author  then
				self:Print("Match found - sending fake roll.")
				EasyLOP:CHAT_MSG_SYSTEM(author .. " rolls 1 (1-1)")
				return
			end
		end
	end
end

function EasyLOP:CHAT_MSG_RAID_LEADER(msg, author, lang)
	if bRolloffs == true and string.lower(msg) == "pass" then
		self:Print("Pass message detected.")
		for i, bid in pairs(tHighBids) do
			self:Print("For loop entered.  Comparing " .. tHighBids[i].bidder .. " to " .. author .. ".")
			if tHighBids[i].bidder == author  then
				self:Print("Match found - sending fake roll.")
				EasyLOP:CHAT_MSG_SYSTEM(author .. " rolls 1 (1-1)")
				return
			end
		end
	end
end

function EasyLOP:ForceEndRolls()
	if bRolloffs == false then
		return
	end
	
	-- end rolls.  Generate fake rolls for people who haven't bid yet by calling:  EasyLOP:CHAT_MSG_SYSTEM(bid.bidder .. " rolls 1 (1-1)")
	
	for i, bid in pairs(tHighBids) do
		if bid.points == 0 then
			EasyLOP:CHAT_MSG_SYSTEM(bid.bidder .. " rolls 1 (1-1)")
		end
	end
end

function EasyLOP:TrackAttendance(strContent)

		for name in string.gmatch(strContent, "(%a+) has joined the raid group.") do 
			EasyLOP:LogEvent("Player Join", "", name)
			--self:Print("Detected " .. strRed .. name .. "|r joining.")
		end
		
		for name in string.gmatch(strContent, "(%a+) joins the party.") do
			EasyLOP:LogEvent("Player Join", "", name)
			--self:Print("Detected " .. strRed .. name .. "|r joining.")
		end

		for name in string.gmatch(strContent, "(%a+) has left the raid group.") do 
			EasyLOP:LogEvent("Player Leave", "", name)
			--self:Print("Detected " .. strRed .. name .. "|r leaving.")
		end
		
		for name in string.gmatch(strContent, "(%a+) leaves the party.") do
			EasyLOP:LogEvent("Player Leave", "", name)
			--self:Print("Detected " .. strRed .. name .. "|r leaving.")
		end
		
		for name in string.gmatch(strContent, "(%a+) has gone offline.") do
			if EasyLOP:IsInRaid(name) then
				EasyLOP:LogEvent("Player Disconnect", "", name)
				--self:Print("Detected " .. strRed .. name .. "|r logging off.")
			end
		end
		--"Linarius has joined the raid group."
		--"Lyseira joins the party."
		--"Linarius has left the raid group."
		--"Lyseira leaves the party."
		--"Lyseira has gone offline."
end

function EasyLOP:IsInRaid(name)
	for i=1, GetNumGroupMembers(), 1 do
		raidname, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
		if string.lower(raidname) == string.lower(name) then
			return true
		end
	end
	return false
end 

function EasyLOP:IsML(name)
	for i=1, GetNumGroupMembers(), 1 do
		--self:Print("Getting IsML data for raid member # " .. i)
		raidname, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
		
		--self:Print("Comparing " .. raidname .. " to " .. name .. ".")
		if string.lower(raidname) == string.lower(name) then
			if isML == nil then 
				return false
			else
				return true
			end
		end
	end
	return false
end

--- RESOLUTION OF STANDARD AND SAVE ROLLOFFS
function EasyLOP:CHAT_MSG_SYSTEM(strContent)

	EasyLOP:TrackAttendance(strContent)
	
	if bRolloffs == false or string.find(strContent, 'roll') == nil then
		return
	end
	
	local name, roll, low, high, bRollsDone
	bRollsDone = true
	
	--Review rolls as they come in, capture roll amount in points variable of bid
	for name, roll, low, high in string.gmatch(strContent, "([^%s]+) rolls (%d+) %((%d+)%-(%d+)%)$") do
		--RollTracker_OnRoll(name, tonumber(roll), tonumber(low), tonumber(high))
		--self:Print(name .. ":  " .. roll)
		roll = tonumber(roll)
		--self:Print("Found roll message - evaluating.")
		for i, bid in pairs(tHighBids) do
			--self:Print(bid.bidder .. " showing " .. bid.points .. " before roll is logged.")
			--self:Print("Evaluating " .. bid.bidder .. " showing points of " .. bid.points)
			if tHighBids[i].bidder == name and roll < 101 and tHighBids[i].points == 0 then
				tHighBids[i].points = roll
				--self:Print("Added " .. bid.bidder .. "'s roll of " .. roll .. " to tHighBids.")
			end
			
			if tHighBids[i].points == nil or tHighBids[i].points == 0 then
				bRollsDone = false
			end
		end
	end
	
	-- Keep functional code if only dealing with one item.
	if tLoots[iCurrentLootIndex].quant == 1 then 
		-- When all rolls are finished, check for ties and assign tWinners
		if bRollsDone == true then
			--self:Print("All rolls done!")
			table.insert(tWinners, {bidder = "", bidType = "", points = 0, item = ""})
						
			tempBid = {}
			tTiedRolls = {}
			bTieFound = false
			
			for i, bid in pairs(tHighBids) do 
				--self:Print("Comparing " .. bid.bidder .. "'s roll of " .. bid.points .. " to " .. tWinners[1].bidder .. "'s roll of " .. tWinners[1].points)
				if tHighBids[i].points > tWinners[1].points then
					tWinners[1].points = tHighBids[i].points
					tWinners[1].bidder = tHighBids[i].bidder
					tWinners[1].bidType = tHighBids[i].bidType
					tWinners[1].item = tHighBids[i].item
					if bTieFound == true then
						bTieFound = false
					end
				elseif tHighBids[i].points == tWinners[1].points then
					tempBid.points = tHighBids[i].points
					tempBid.bidder = tHighBids[i].bidder
					tempBid.bidType = tHighBids[i].bidType
					tempBid.item = tHighBids[i].item
					
					--table.insert(tTiedRolls, tempBid)
					bTieFound = true
				end
			end
			
			if bTieFound == true then   -- Deal with ties; re-write tHighBids to include only the tied bidders, and call for new rolls.  
				for i, bid in pairs(tHighBids) do
					if tHighBids[i].points == tempBid.points then
						tHighBids[i].points = 0
						table.insert(tTiedRolls, tHighBids[i])
					end
				end
				
				tHighBids = {}
				tWinners = {}
				
				for i, bid in pairs(tTiedRolls) do
					--self:Print ( "Adding " .. tTiedRolls[i].bidder .. " to tHighBids.")
					table.insert(tHighBids, tTiedRolls[i])
				end
				
				-- Call for rolloff between the ties.
				strMessage = "Tie roll!  Reroll between: "
				--self:Print( tHighBids[1].bidder .. " shows current points of " .. tHighBids[1].points)
				--self:Print( tHighBids[2].bidder .. " shows current points of " .. tHighBids[2].points)
				
				for i, bid in pairs(tHighBids) do
					if tHighBids[i + 1] == nil then
						strMessage = strMessage .. "and "
					end
					
					strMessage = strMessage .. tHighBids[i].bidder 
					
					if tHighBids[i + 1] == nil then
						strMessage = strMessage .. "."
					else
						if i == 1 and tHighBids[i + 2] == nil then
							strMessage = strMessage .. " "
						else
							strMessage = strMessage .. ", "
						end
					end
				end
				SendChatMessage( strMessage, "RAID_WARNING")
				bRolloffs = true
			else	-- Announce winner!
				StaticPopup_Hide("END_ROLLS")
				bRolloffs = false
				self:Print("Winner is " .. tWinners[1].bidder .. " with a " .. tWinners[1].points .. ".")
				strAnnouncement = tWinners[1].bidder .. " wins with a " .. tWinners[1].bidType .. " roll of " .. tWinners[1].points .. "!  Grats on your shiny new " .. tWinners[1].item .. "!"
				
				-- keep record of wins in tLoots
				--table.insert(tLoots[iCurrentLootIndex].winbid, tWinners[1])
				EasyLOP:SendWinnerEntry(tWinners[1])
				
				bPendingAnnounce = true
				StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item, tWinners[1].bidder .. ".  Announce now?")
			end
		end
	-- Add code for dealing with multiples
	else
		-- When all rolls are finished, check for ties and assign tWinners
		if bRollsDone == true then
			--self:Print("All rolls done!")
			
			-- All ties must be determined first.
			for i, bid in pairs(tHighBids) do
				bid.bTie = false
			end
			
			for i, bid1 in pairs(tHighBids) do 
				for ii, bid2 in pairs(tHighBids) do
					if bid1.points == bid2.points and bid1.bidder ~= bid2.bidder then
						--self:Print("Updating " .. bid1.bidder .. " and " .. bid2.bidder .. "'s bids to ties.")
						--self:Print("Updating " .. bid1.bidder .. "'s bid to a tie.")
						bid1.bTie = true
						--bid2.bTie = true
					end
				end
			end

			-- Then count down from highest roll, adding bidders to tWinners until you reach a tie or you meet numTBD.  Start by sorting the high bids.
			table.sort(tHighBids, function(a, b) return a.points > b.points end)
			
			if numAssigned == nil then
				numAssigned = 0
			end
			numTies = 0
			bTieRolloff = false
			tieValue = 0
			tRemove = {}
			
			
			for i, bid in pairs(tHighBids) do 
				self:Print("Evaluating " .. bid.bidder .. "'s roll of " .. bid.points .. ".")
				if bid.bTie == false and numAssigned + numTies < numTBD then
					--self:Print("Assigning " .. bid.bidder .. "'s roll of " .. bid.points .. " to tWinners.") --; bTie = " .. tostring(bid.bTie) .. ".")
					table.insert(tWinners, bid)
					table.insert(tRemove, i)
					numAssigned = numAssigned + 1
				elseif bTieRolloff == true and bid.points ~= tieValue then
					--self:Print("Removing " .. bid.bidder .. "'s roll of " .. bid.points .. " from contention due to a pending rolloff between a pair of higher ties.")
					table.insert(tRemove, i)
				elseif bTieRolloff == true and bid.points == tieValue then
					bid.points = 0
				elseif bid.bTie == true and numAssigned < numTBD then 
					--self:Print("Entering tie logic based on " .. bid.bidder .. "'s roll of " .. bid.points .. ".")
					-- Determine number of tied rolls, call for rerolls if it will make a difference.
					numTies = 0
					for ii, tiebid in pairs(tHighBids) do
						if tiebid.bTie == true and tiebid.points == bid.points then
							numTies = numTies + 1
						end
					end
					
					--self:Print("numTies = " .. numTies)
					--self:Print("numTBD is " .. numTBD)
					--self:Print("numAssigned is " .. numAssigned)
						
					if numTies + numAssigned <= numTBD then -- all tied rolls win a loot.  No need to remove anything.
						--self:Print("Adding " .. bid.bidder .. " to remove table.")
						table.insert(tWinners, bid)
						table.insert(tRemove, i)
						numAssigned = numAssigned + 1
						numTies = numTies - 1
						bid.bTie = false
					else -- will need rolloff to determine which tied rolls get loot.  
						-- Activate tie roll off logic and discard the non-tied (lower) bids
						bTieRolloff = true
						tieValue = bid.points
						bid.points = 0
					end
				else -- numAssigned = numTBD - all winning slots taken, remaining rolls lose (are discarded)
					--self:Print("Removing " .. bid.bidder .. "'s roll of " .. bid.points .. " from contention because all winning spots have been taken.")
					table.insert(tRemove, i)
				end
			end
			
			
			-- remove all winning and non-winning rolls for next time
			for i, index in pairs(tRemove) do
				--self:Print("Removing " .. tHighBids[index].bidder .. " from tHighBids")
				table.remove(tHighBids, index)
			end
	
			
			if bTieRolloff == true then   -- Deal with ties; call for new rolls.  								
				-- Call for rolloff between the ties.
				strMessage = "Tie roll!  Reroll between: "
				for i, bid in pairs(tHighBids) do
					if tHighBids[i + 1] == nil then
						strMessage = strMessage .. "and "
					end
					
					strMessage = strMessage .. tHighBids[i].bidder 
					
					if tHighBids[i + 1] == nil then
						strMessage = strMessage .. "."
					else
						if i == 1 and tHighBids[i + 2] == nil then
							strMessage = strMessage .. " "
						else
							strMessage = strMessage .. ", "
						end
					end
				end
				SendChatMessage( strMessage, "RAID_WARNING")
				bRolloffs = true
			else	-- Determine winner!
				StaticPopup_Hide("END_ROLLS")
				bRolloffs = false
				if numTBD == 1 then 
					strAnnouncement = "Grats " .. tWinners[1].bidder .. " with a " .. tWinners[1].points .. "."
				elseif numTBD > 1 then
					strAnnouncement = "Grats to "
					for i, bid in pairs(tWinners) do
						if tWinners[i + 1] == nil then
							strAnnouncement = strAnnouncement .. "and "
						end
						
						strAnnouncement = strAnnouncement .. tWinners[i].bidder 
						
						if tWinners[i + 1] == nil then
							strAnnouncement = strAnnouncement .. " on " .. tWinners[i].bidType .. "s!"
						else
							if i == 1 and tWinners[i + 2] == nil then
								strAnnouncement = strAnnouncement .. " "
							else
								strAnnouncement = strAnnouncement .. ", "
							end
						end
					end
				end
				numTBD = 0
				numAssigned = 0
				self:Print('Annoucement will be "' .. strAnnouncement .. '"')
				
				-- keep record of wins in tLoots
				winnerList = ""
				for i, bid in pairs (tWinners) do
					--table.insert(tLoots[iCurrentLootIndex].winbid, bid)
					EasyLOP:SendWinnerEntry(bid)
					winnerList = winnerList .. bid.bidder .. " "
				end
				
				bPendingAnnounce = true
				StaticPopup_Show("CONFIRM_WINNER", tLoots[iCurrentLootIndex].item .. "x" .. tLoots[iCurrentLootIndex].quant, winnerList .. ".  Announce now?")
			end
		end
	end
end

function EasyLOP:CHAT_MSG_RAID_WARNING(msg, author, lang)
	--self:Print("CHAT_RAID_WARNING event triggered.   Index is " .. msgQIndex)
	if author == UnitName("player") and (string.find(msg, "*Loots: ") or msgQIndex > 1) then
		--self:Print("Found *Loots: - msgQIndex = " .. msgQIndex .. " and tMsgQ[msgQIndex] is " .. tMsgQ[msgQIndex])
		if tMsgQ[msgQIndex] == nil then
			--self:Print("Setting msgQIndex to 1 and exiting CHAT_MSG_RAID_WARNING event.")
			--msgQIndex = 1
			SendAddonMessage("ELOP", "ELOP_CLEAR_MSGQ^", "RAID")
			return
		else
			--self:Print("Should now be bonging:  " .. tMsgQ[msgQIndex] .. ", msgQIndex is " .. msgQIndex)
			SendChatMessage( tMsgQ[msgQIndex], "RAID_WARNING")
			tMsgQ[msgQIndex] = "" 
			msgQIndex = msgQIndex + 1
		end
	end
end

function EasyLOP:CHAT_MSG_WHISPER(text, author, lang, status)
	
	local ltext = string.lower(text)
	
	if ltext == "points" then  
		if bPointsLoaded == true then
			SendChatMessage("You have " .. EasyLOP:GetPoints(author) .. " points.", "WHISPER", nil, author)
		else
			SendChatMessage("I don't currently have points loaded.", "WHISPER", nil, author)
		end
		return
	elseif ltext == "?lop?" then
		--self:Print("lop info request received.")
		SendOPENBIDSMessage('When loot is announced, you can send a tell to the LOOT MASTAH saying "Shroud", "Standard", or "Save".', "WHISPER", nil, author)
		SendChatMessage('"Shroud" means "GIMME GIMME GIMME!"  It will cost half your points.  You must have 10 points to Shroud.  Highest Shroud bid automatically wins.', "WHISPER", nil, author)
		SendChatMessage('"Standard" means "I want it, but am willing to roll off on it."  You will roll off against everyone else who Standards, provided there are no Shrouds.  Highest roll wins.  Standard costs 10 points, or whatever you have (min 0).', "WHISPER", nil, author)
		SendChatMessage('"Save" means "Eh, I will save it from DE".  You will roll off against everyone else who saved, as long as no one bid shroud or standard.  Save costs 10 points or however much you have (min 0).', "WHISPER", nil, author)
		SendChatMessage("Shroud beats Standard, which beats Save.  You're only charged points if you win the item, and you earn points after every raid.  You can only bid Standard or Save on your first night - BUT all your first night loot is free!", "WHISPER", nil, author)		
		return
	elseif bRolloffs == true and string.lower(text) == "pass" then
		for i, bid in pairs(tHighBids) do
			if tHighBids[i].bidder == author  then
				EasyLOP:CHAT_MSG_SYSTEM(author .. " rolls 1 (1-1)")
				return
			end
		end
	elseif bBidsActive == false or bParsing == false then
		return
	end
	
	local strBidType = nil
	local bFoundBid = false
	local strConfirmMessage = nil
	local strSymbol = nil
	local bPrevBid = false
	local bReplyOK = true
	
	--  If whisper came from this user,  do not reply.
	pName = UnitName("player")
	if author == pName then
		bReplyOK = false
	end

	--Determine whether author is in raid - TBI
	
	
	--Determine whether this bidder has previously bid on this item
	prevBidIndex = 0
	for i, bid in pairs(tBids) do
		if tBids[i].bidder == author and tBids[i].item == tLoots[iCurrentLootIndex].item then
			bPrevBid = true
			prevBidIndex = i
		end
	end
	
	-- Parse whisper for bid, create confirm message
	if string.find(ltext, "save") or string.find(ltext, "saave") or string.find(ltext, "sv") then
		strBidType = "save"
		strSymbol = "{star}"
		bFoundBid = true
	end
	
	if string.find(ltext, "std") or string.find(ltext, "standard") or string.find(ltext, "stan ") or string.find(ltext, "standerd") then
		if bFoundBid == true then
			strConfirmMessage = '{cross}NO BID REGISTERED.{cross}  More than one possible bid was present in your whisper.  Please send another tell to me indicating either "shroud", "standard", or "save".'
			if bReplyOK == true then
				SendChatMessage(strConfirmMessage, "WHISPER", nil, author)
			end
			return
		end
		strBidType = "standard"
		strSymbol = "{diamond}"
		bFoundBid = true
	end
	
	if string.find(ltext, "shd") or string.find(ltext, "shroud") or string.find(ltext, "shr ") or string.find(ltext, "shrod") then
		if bFoundBid == true then
			strConfirmMessage = '{cross}NO BID REGISTERED.{cross}  More than one possible bid was present in your whisper.  Please send another tell to me indicating either "shroud", "standard", or "save".'
			if bReplyOK == true then
				SendChatMessage(strConfirmMessage, "WHISPER", nil, author)
			end
			return
		end

		strBidType = "shroud"
		strSymbol = "{circle}"
		bFoundBid = true
	end
	
	if string.find(ltext, "cancel") or string.find(ltext, "nvm") or string.find(ltext, "nm ") then
		strBidType = "cancel"
		if bPrevBid == true then
			table.remove(tBids, prevBidIndex)
			strConfirmMessage = '{skull}CANCELLED{skull} Your bid on the ' .. tLoots[iCurrentLootIndex].item .. ' has been cancelled.  You currently are not bidding on this item.'
		else
			strConfirmMessage = 'I read a cancel bid in your whisper, but you had no previous bid to cancel.  You are currently not bidding on the ' .. tLoots[iCurrentLootIndex].item .. '.  If this is incorrect, whisper your bid now.'
		end
		if bReplyOK == true then
			SendChatMessage(strConfirmMessage, "WHISPER", nil, author)
		end
		
		return
	end
	
	if bFoundBid == false then
		strConfirmMessage = '{cross}NO BID REGISTERED.{cross} No bid was found in your whisper.  Please send another tell to me indicating either "shroud", "standard", or "save" if you wish to bid on this item.  '
		
		-- Confirm current bid
		if bPrevBid == false then
			strConfirmMessage = strConfirmMessage .. 'You currently have NO bids registered on this item.'
		else
			for i, bid in pairs(tBids) do
				if tBids[i].bidder == author and tBids[i].item == tLoots[iCurrentLootIndex].item then
					strConfirmMessage = strConfirmMessage .. 'You are currently bidding ' .. tBids[i].bidType .. '.'
				end
			end		
		end

		if bReplyOK == true then		
			SendChatMessage(strConfirmMessage, "WHISPER", nil, author)
		end
		
		return
	end

	-- Check to make sure sufficient points exist for a shroud bid; if not, downgrade to standard and notify bidder.
	thisBid = { bidder = author, bidType = strBidType, item = tLoots[iCurrentLootIndex].item, points = EasyLOP:GetPoints(author) }
	if tonumber(thisBid.points) < 10 and thisBid.bidType == "shroud" then
		thisBid.bidType = "standard"
		strBidType = "standard"
		strSymbol = "{diamond}"
		if bReplyOK == true then
			SendChatMessage("You must have 10 points to make a Shroud bid.  Your current points are " .. thisBid.points .. ".  As a result, your bid has been downgraded to a standard.", "WHISPER", nil, author)
		else
			self:Print( "You only have " .. thisBid.points .. " points.  Shroud downgraded to standard.")
		end
	elseif thisBid.bidType ~= "shroud" then
		thisBid.points = 0
	end
	
	-- Update tBids table with list of the new bid, either replacing value of old bid or adding new bid altogether
	if bPrevBid == true then
		for i, bid in pairs(tBids) do
			if tBids[i].bidder == author and tBids[i].item == tLoots[iCurrentLootIndex].item then
				tBids[i].bidType = strBidType
				tBids[i].points = thisBid.points
			end
		end	
	else
		-- Add the bid to the list of current bids
		table.insert( tBids, thisBid )
	end	
	
	-- Construct the confirm message and output it.
	strConfirmMessage = strSymbol
	strConfirmMessage = strConfirmMessage .. string.upper(strBidType)
	strConfirmMessage = strConfirmMessage .. strSymbol
	strConfirmMessage = strConfirmMessage .. "This is confirmation of your " 
	strConfirmMessage = strConfirmMessage .. string.upper(strBidType) 
	strConfirmMessage = strConfirmMessage .. " bid for " 
	strConfirmMessage = strConfirmMessage .. tLoots[iCurrentLootIndex].item
	strConfirmMessage = strConfirmMessage .. ".  "  
	
	if bPrevBid == true then
		strConfirmMessage = strConfirmMessage .. "This replaces your old bid."
	end
	
	if bReplyOK == true then
		SendChatMessage(strConfirmMessage, "WHISPER", nil, author)

		strConfirmMessage = "If this is not right, whisper me the word CANCEL.  To change this bid, just whisper me your new bid."
		SendChatMessage(strConfirmMessage, "WHISPER", nil, author)
	else
		self:Print( "Your " .. strBidType .. " bid has been registered.")
	end
	
	--self:Print("tBids appears to have been updated without an error.")
end

--[[
function EasyLOP:BadgeAnnounce()
	SendChatMessage("Total Badges this run:  " .. iTotalBadges, "RAID_WARNING")
end
]]
function EasyLOP:ForceAnnounce()
	SendChatMessage(strLootList, "RAID_WARNING")
end

function EasyLOP:spitbids()
	--self:Print("spitbids called")
	if bMLQualified == false then
		return
	end
	
	-- print bids on current item
	temp = 0
	if bBidsActive == false then
		while tLoots[iCurrentLootIndex - temp].item == nil do 
			temp = temp + 1
		end
	end
		
	if tBids[1] == nil then
		self:Print("No active bids.")
		return
	end
	
	self:Print("-- Bids on " .. tLoots[iCurrentLootIndex - temp].item .. " --")
	
	for i,bid in pairs(tBids) do
		if tBids[i].item == tLoots[iCurrentLootIndex - temp].item then
			--self:Print( "i is: " .. i .. ", first while loop entered.")
			if tBids[i].bidType == 'save' then
				strColor = "|cff9d9d9d"
			elseif tBids[i].bidType == 'standard' then
				strColor = "|cff1eff00" 
			else
				strColor = "|cffe60000"
			end
			self:Print(tBids[i].bidder .. ":  " .. strColor ..  tBids[i].bidType .. "|r")
		end
	end    -- works
	
	-- print all other bids currently received
	self:Print("-- All other current bids --")
	
	for i,bid in pairs(tBids) do
		if tBids[i].item ~= tLoots[iCurrentLootIndex - temp].item then
			--self:Print( "i is: " .. i .. ", first while loop entered.")
			if tBids[i].bidType == 'save' then
				strColor = "|cff9d9d9d"
			elseif tBids[i].bidType == 'standard' then
				strColor = "|cff1eff00" 
			else
				strColor = "|cffe60000"
			end
			self:Print(tBids[i].bidder .. ":  " .. strColor ..  tBids[i].bidType .. "|r on " .. tBids[i].item)
		end
	end
	
	-- print all old bids?  Using tPrevBids if decide to
end

function EasyLOP:oldbids()
	--self:Print("spitbids called")
	
	-- print bids on current item
	
	
	-- print all other bids currently received
	self:Print("-- All bids --")
	
	for i,bid in pairs(tPrevBids) do
		--self:Print( "i is: " .. i .. ", first while loop entered.")
		if tPrevBids[i].bidType == 'save' then
			strColor = "|cff9d9d9d"
		elseif tPrevBids[i].bidType == 'standard' then
			strColor = "|cff1eff00" 
		else
			strColor = "|cffe60000"
		end
		self:Print(tPrevBids[i].bidder .. ":  " .. strColor ..  tPrevBids[i].bidType .. "|r on " .. tPrevBids[i].item)
	end
	
	-- print all old bids?  Using tPrevBids if decide to
end

function EasyLOP:CallForRolls(bidType, tBidders, strMessage)
	--self:Print("CallForRolls called.")
	local bMessagePreset = false
	if strMessage == "" then
		--self:Print("strMessage was sent blank.")
		strMessage = bidType .. " rolloff between: "
	else
		bMessagePreset = true
		strMessage = strMessage .. bidType .. " rolloff between: "
	end
	
	for i, bid in pairs(tBidders) do
		--self:Print("Building strMessage....  iteration " .. i)
		if tBidders[i + 1] == nil then
			strMessage = strMessage .. "and "
		end
		
		strMessage = strMessage .. tBidders[i].bidder 
		
		if tBidders[i + 1] == nil then
			if bMessagePreset == false then 
				strMessage = strMessage .. "."
			else
				strMessage = strMessage .. "!"
			end
		else
			if i == 1 and tBidders[i + 2] == nil then
				strMessage = strMessage .. " "
			else
				strMessage = strMessage .. ", "
			end
		end
		--self:Print("strMessage is now: '" .. strMessage .. "'.")
	end
	--self:Print("Click okay to display the following message:" .. strMessage)
	--strRollCall = strMessage
	--StaticPopup_Show("ANNOUNCE_ROLLOFF")
	
	SendChatMessage(strMessage, "RAID_WARNING")
	bRolloffs = true
	
	-- show window that will end rolls.
	StaticPopup_Show("END_ROLLS")
	
	--- Analyze or perform rolls, assign winner to tWinners[1] -- all done in CHAT_MSG_SYSTEM funct
end

function EasyLOP:AnnounceRolloff()
	SendChatMessage(strRollCall, "RAID_WARNING")
	strRollCall = "" 
end

function EasyLOP:buttontest()
	--SendChatMessage("You clicked the testbong button", "CHANNEL", "TAURAHE", "5")
	self:Print("You clicked the TestBong button!")
end

function EasyLOP:testbong()
	--EasyLOP:ValidatePoints()
	--self:Print(lastEvent.Name .. ": " .. lastEvent.Time)
	--ShowUIPanel(BidTrackerFrame)
	
	--[[if bVashjTest == false then
		bVashjTest = true
	else
		bVashjTest = false
	end]]
	
	--StaticPopup_Hide("BEGIN_BIDS")
--[[
	self:Print("Testbong received " .. itemlink)
	local found, _, itemString = string.find(itemlink, "^|c(.+)|H(.+)|h%[.+%]")
	
	self:Print("found: " .. found)
	self:Print("_: " .. _)
	self:Print(" itemString: " .. itemString)]]
	--[[
	tBids = {}
	
	tLoots[iCurrentLootIndex].item = itemlink
	tLoots[iCurrentLootIndex].quant = 3
	
	bid = {
		bidder = "Vaughn", 
		bidType = "standard",
		item = itemlink, 
		points = 0}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Conifer", 
		bidType = "shroud",
		item = itemlink, 
		points = 48}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Cieki", 
		bidType = "shroud",
		item = itemlink, 
		points = 80}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Bagels", 
		bidType = "shroud",
		item = itemlink, 
		points = 19}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Falir", 
		bidType = "shroud",
		item = itemlink, 
		points = 42}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Maegrette", 
		bidType = "shroud",
		item = itemlink, 
		points = 174.375}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Jheusse", 
		bidType = "shroud",
		item = itemlink, 
		points = 57}
	table.insert(tBids, bid)
	
	bid = {
		bidder = "Elkheart", 
		bidType = "save",
		item = itemlink, 
		points = 0}
	table.insert(tBids, bid)
	
	for i, bid in pairs(tBids) do
		self:Print("tBids position " .. i .. " has a bid belonging to " .. tBids[i].bidder .. ".")
	end]]
	--StaticPopup_Show("CAPTURE_DEORGREED")
	--[[self:Print("Points last loaded: " .. EasyLOP.db.profile.ExportTime)
	self:Print("Points loaded are for the " .. EasyLOP.db.profile.RaidType .. " pool.")
	
	strDate = date()
	for word in string.gmatch(strDate, "../../..") do 
		strDate = word
	end
	self:Print("Current date is " .. strDate)
	
	for word in string.gmatch(EasyLOP.db.profile.ExportTime, "../../..") do
		strDate = word
	end
	self:Print("Last date loaded is " .. strDate)]]
	
end

function EasyLOP:CHAT_MSG_ADDON(prefix, msg, disType, sender)
	--self:Print(prefix .. " addon message received.")
	if bDeactivated == true then
		return
	end
	
	oldprefix, msg = strsplit("^",msg,2)
	--self:Print("prefix:" .. oldprefix .. "Message:" .. msg)
	if oldprefix == "ELOP_SENDTOML" then
		if EasyLOP:IsML(UnitName("player")) and bAutoAward then
			for recip, incitem in string.gmatch(msg, "(.+) & (.+)") do
				--self:Print("The item that should be proxy ML'ed is: " .. incitem)
				--self:Print("It should be proxy ML'ed to: " .. recip)
				
				bRecipientFound = false
				for i=1, 40, 1 do
					--self:Print( "i is " .. i )
					name = GetMasterLootCandidate(i)
					if name ~= nil then
						--self:Print( "Looking at " .. string.lower(name) .. " as possible recipient.  iteration " .. i)
						if string.lower(name) == string.lower(recip) then
							bRecipientFound = true
							for ii=1, GetNumLootItems(), 1 do
								if LootSlotIsItem(ii) then
									--self:Print("Looking at " .. GetLootSlotLink(ii) .. " as item to be DEed/Greeded.")
									--self:Print("The item that should be DEed/greeded is: " .. tWinners[1].item)
									if GetLootSlotLink(ii) == incitem then
										GiveMasterLoot(ii,i)
										ii = GetNumLootItems()
									end
								else
									--self:Print("Looking at money.")
								end
							end
						end
					end				
				end
				--[[for ii=1, GetNumLootItems(), 1 do
					if LootSlotIsItem(ii) then
						self:Print("Looking at " .. GetLootSlotLink(ii) .. " as item to be proxy ML'ed.")
						if GetLootSlotLink(ii) == incitem then
							GiveMasterLoot(ii,i)
							ii = GetNumLootItems()
						end
					else
						--self:Print("Looking at money.")
					end
				end]]
			end
		end
		return
	elseif oldprefix == "ELOP_SYNCPOINTS" and bOverrideSync == false then
		--self:Print("msg is " .. msg )
		if bSkipSyncMessage == true then 
			bSkipSyncMessage = false
			return
		end
		
		for name, amt, decimals in string.gmatch(msg, "(%a+) (%d+).(%d+)") do 
			--self:Print("Analyzing string...")
			amt = amt .. "." .. decimals
			--self:Print(name .. " should be set to " .. amt)
			EasyLOP:UserSet(name, tonumber(amt), false, sender)
		end
	elseif oldprefix == "ELOP_CLEAR_TLOOTS" then
		tLoots = {}
		bMLQualified = false
		--self:Print("tLoots table cleared.")
	elseif oldprefix == "ELOP_ADD_TLOOTS_ENTRY" then
		--[[
		sendString = i .. " " 
		sendString = sendString .. loot.quant .. " " 
		sendString = sendString .. loot.item
		]]
		for inci, incquant, incitem in string.gmatch(msg, "(%d+) (%d+) (.+)") do
			addItem = { item = incitem, quant = tonumber(incquant), winbid = {}}
			--self:Print("Adding item:" .. addItem.item .. "x" .. addItem.quant)
			table.insert(tLoots,addItem)
			bMLQualified = true
		end
		
		if bBidsActive == true or bPendingAnnounce == true then
			self:Print("A new loot window has been opened.  Your pending bid session or winner announcement has been lost.  Use /lop charge to manually charge the winner, or reopen the loot window to begin a new bidding session on the loots.")
		end
	elseif oldprefix == "ELOP_SHOW_OPENBIDS" then
		beginBidsFrame = StaticPopup_Show ("BEGIN_BIDS", msg)  
	elseif oldprefix == "ELOP_HIDE_OPENBIDS" then
		StaticPopup_Hide("BEGIN_BIDS")
	elseif oldprefix == "ELOP_SET_SUSPEND" then
		for set, sendingPlayer in string.gmatch(msg, "(.+) (.+)") do
			if set == 'true' then
				bSuspendProcess = true
				addonOwner = sendingPlayer
				--self:Print("Announcement/Bidding process locked by " .. sendingPlayer ..".  Type /lop unlock if unable to complete bids for any reason.")
			else
				bSuspendProcess = false
				addonOwner = ""
				--self:Print("EasyLOP will now recognize a new loot list.")
			end
		end		
	elseif oldprefix == "ELOP_KILL_POPUPS" then
		StaticPopup_Hide("BEGIN_BIDS")
		StaticPopup_Hide("CONFIRM_WINNER")
		StaticPopup_Hide("CAPTURE_DEORGREED")
		StaticPopup_Hide("NO_BIDDERS")
		StaticPopup_Hide("CLOSE_BIDS")
	elseif oldprefix == "ELOP_UPDATE_INDEX" then
		-- iCurrentLootIndex .. " " .. UnitName("player") .. " " .. callingFunct
		for icl, sendingPlayer, callingFunct in string.gmatch(msg, "(%d+) (.+) (.+)") do
			iCurrentLootIndex = tonumber(icl)
			--[[
			if tLoots[iCurrentLootIndex] ~= nil then
				self:Print("iCurrentLootIndex updated to " .. iCurrentLootIndex .. ".  Item at that index is " .. tLoots[iCurrentLootIndex].item .. ".  Sent from " .. sendingPlayer .. " in " .. callingFunct ..  " function.")
			else
				self:Print("iCurrentLootIndex updated to " .. iCurrentLootIndex .. ", but there is no item listed at that index.  Sent from " .. sendingPlayer .. " in " .. callingFunct ..  " function.")
			end]]
		end		
	elseif oldprefix == "ELOP_UPDATE_QUANT" then
		for incindex, incquant, incitem in string.gmatch(msg, "(%d+) (%d+) (.+)") do
			incindex = tonumber(incindex)
			--self:Print("tLoots shows: " .. tLoots[tonumber(incindex)].item .. ".    incitem is:  " .. incitem)
			if tLoots[incindex].item == incitem then
				tLoots[incindex].quant = incquant
				--self:Print("tLoots quant entry for " .. tLoots[incindex].item .. " updated to " .. tLoots[incindex].quant .. ".")
			else
				self:Print("Mismatch on tLoots index in UPDATE_QUANT message; unable to update winner.")
			end
		end
	elseif oldprefix == "ELOP_UPDATE_WINNER_ENTRY" then
		-- insert code
		--[[
		sendString = ""
		sendString = sendString .. iCurrentLootIndex .. " " 
		sendString = sendString .. thisBid.bidder .. " " 
		sendString = sendString .. "&& " .. thisBid.bidType .. " && " 
		sendString = sendString .. thisBid.points .. " item: " 
		sendString = sendString .. thisBid.item
		]]
		--self:Print("'Update' addon message received.")
		for incindex, incbidder, incbidtype, incpoints, incitem in string.gmatch(msg, "(%d+) (.+) && (.+) && (.+) item: (.+)") do
			incindex = tonumber(incindex)
			--self:Print("tLoots shows: " .. tLoots[tonumber(incindex)].item .. ".    incitem is:  " .. incitem)
			if tLoots[incindex].item == incitem then
				addItem = {bidder = incbidder, bidType = incbidtype, points = incpoints, item = incitem}
				table.insert(tLoots[incindex].winbid, addItem)
				--self:Print("Added to winbid table of " .. tLoots[incindex].item .. ":  Bidder: " .. addItem.bidder .. " bidType: " .. addItem.bidType .. " Points: " .. addItem.points .. " addItem: " .. addItem.item)
				iCurrentLootIndex = incindex
			else
				self:Print("Mismatch on tLoots index in UPDATE_WINNER message; unable to update winner.")
			end
		end
	elseif oldprefix == "ELOP_CLEAR_MSGQ" then
		tMsgQ = {}
		msgQIndex = 1
		return
	elseif oldprefix == "ELOP_VERCHECK" then
		--local s = UnitName("player") .. " Ver " .. Version .. ".  Point import time stamp:  " .. EasyLOP.db.profile.ExportTime
		local strDate
		
			
		if EasyLOP.db.profile.ExportTime == nil or EasyLOP.db.profile.ExportTime == 0 then
			strDate = "00/00/00"
		else
			for word in string.gmatch(EasyLOP.db.profile.ExportTime, "../../..") do
				strDate = word
			end
		end
		
		if EasyLOP.db.profile.RaidType == nil or EasyLOP.db.profile.RaidType == "" then
			pool = "unloaded"
		else
			pool = EasyLOP.db.profile.RaidType
		end
		
		local s = UnitName("player") .. " " .. Version .. " " .. strDate .. " " .. pool
		self:Print( sender .. " performed a version query.")
		--self:Print("sending: " .. s)
		SendAddonMessage("ELOP",  "ELOP_VERREPORT^" .. s, "RAID")
	elseif oldprefix == "ELOP_SYNCDELOG" then
		--sendString = UnitName("player") .. " " .. tLoots[iCurrentLootIndex].item
		for incsender, incitem in string.gmatch(msg, "(.+) && (.+)") do
			EasyLOP:LogEvent("Disenchant", "", "", incsender, "", incitem)
		end
	elseif oldprefix == "ELOP_AUTOCHARGE" then
		--self:Print("received elop_autocharge")
		for inctype, incbidder, incsender, incbidtype, inccharged, incitem in string.gmatch(msg, "(.+) (.+) (.+) && (.+) && (.+) item: (.+)") do
			--self:Print("inside for loop")
			EasyLOP:LogEvent("Automated Charge", inccharged, incbidder, incsender, incbidtype, incitem)
			--EasyLOP:LogEvent("Automated Charge", iCharged, charName, UnitName("player"), bid, item)
		end
	elseif oldprefix == "ELOP_VERREPORT" then
		--if bWaitingOnVerCheck == false then return end -- not yet implemented - this bool will be used to display the vercheck results only to the user who initiated it, once all addon users have reported in.
		
		for name, ver, compDate, pool in string.gmatch(msg, "(.+) (.+) (.+) (.+)") do		
			--[[for entry in pairs(tRaidLeads) do
				if entry.name == name then
					entry.version = ver
				end
			end]]
			
			strOptional = ""
			strOptEnd = ""
			strOptMsg = ""
			local s = ""
									
			if tonumber(ver) < tonumber(Version) then
				strOptional = strRed
				strOptEnd = "|r"
				strOptMsg = "(OLD)"
			end

			if tonumber(ver) > tonumber(Version) then
				strOptional = strGreen
				strOptEnd = "|r"
				strOptMsg = "(More current than yours)"
			end
			
			s = strOptional .. name  .. ":  " .. strOptEnd .. "  Version " .. strOptional ..  ver .. "  "  .. strOptMsg .. strOptEnd 
			
			strDate = date()
			for word in string.gmatch(strDate, "../../..") do 
				strDate = word
			end
			currentDate = strDate
			
			if compDate == "00/00/00" then
				s = s .. strRed .. "This user has no points loaded."
			else
				if currentDate == compDate then
					s = s .. " Points loaded on: " .. compDate .. " "
				else
					s = s .. " Points loaded on: " .. strRed .. compDate .. " (OLD) " .. "|r"
				end 
				
				if EasyLOP.db.profile.RaidType ~= nil and pool == EasyLOP.db.profile.RaidType then
					s = s .. "(" .. pool .. ") "
				elseif EasyLOP.db.profile.RaidType ~= nil and pool ~= EasyLOP.db.profile.RaidType then
					s = s .. strRed .. "(" .. pool .. " - MISMATCH) "
				end
			end
			
			self:Print(s)
		end
	elseif bOverrideSync == true then
		--self:Print("bOverride sync is true; bypassing; prefix is " .. prefix)
		bOverrideSync = false
	end
end

function EasyLOP:PrintEventLog()
	if eventLog == nil or eventLog[1] == nil then		
		self:Print(strRed .. "No log entries to print.")
		return
	else
		self:Print(strRed .. "***********************************")
		self:Print(strRed .. "******** EVENT LOG REPORT *********")
		self:Print(strRed .. "***********************************")
		table.sort(eventLog, function(a,b) return a.Index < b.Index end)
		for i, evt in pairs(eventLog) do
			self:Print(EasyLOP:CreateEventString(evt))
		end
	end
end

function EasyLOP:CreateEventString(event)
	if event == nil then return "" end
	
	
	currentDate = date()
	for word in string.gmatch(currentDate, "../../..") do 
		currentDate = word
	end
	
	strPrint = strGreen .. event.Time
	if currentDate == event.Date then 
		strPrint = strPrint .. "|r:  "
	else
		strPrint = strPrint .. " (" .. event.Date .. ")|r:  "
	end
	
	bInit = true
	if event.Type == "Manual Charge" then
		strPrint = strPrint .. event.Pointholder .. " manually charged " .. event.Value .. " for a " .. event.BidType
	elseif event.Type == "User Set" then
		strPrint = strPrint .. event.Pointholder .. "'s points manually set to " .. event.Value
	elseif event.Type == "Synchronized Set" then
		strPrint = strPrint .. "Local copy of " .. event.Pointholder .. "'s points manually set to " .. event.Value
	elseif event.Type == "Points Cleared" then
		strPrint = strPrint .. "Points cleared"
	elseif event.Type == "Import" then
		strPrint = strPrint .. event.Value .. " points imported"
	elseif event.Type == "Automated Charge" then
		strPrint = strPrint .. event.Pointholder .. " automatically charged " .. event.Value .. " points for a " .. event.BidType .. " bid on " .. event.Item
		bInit = false
	elseif event.Type == "Disenchant" then
		strPrint = strPrint .. event.Item .. " received no bids.  DE/Greed."
		bInit = false
	elseif event.Type == "Player Join" then
		strPrint = strPrint .. event.Pointholder .. " joined the group."
		bInit = false
	elseif event.Type == "Player Leave" then
		strPrint = strPrint .. event.Pointholder .. " left the group."
		bInit = false
	elseif event.Type == "Player Disconnect" then
		strPrint = strPrint .. event.Pointholder .. " disconnected."
		bInit = false
	else
		strPrint = strPrint .. "Unrecognized event '" .. event.Type .. "'"
	end

	if bInit == true then 
		strPrint = strPrint .. " by " .. event.Initiator 
	end
	
	return strPrint
end

function EasyLOP:GetLastEvent()
	--sort the event table, greatest hours first.
	if eventLog == nil or eventLog[1] == nil then		
		return nil
	else
		table.sort(eventLog, function(a,b) return a.Index > b.Index end)
		return eventLog[1]
	end
end

function EasyLOP:LogEvent(etype, value, pointholder, initiator, bidType, item)
	local event = {}
	if item == nil then	item = "" end
	if bidType == nil then bidType = "" end
	if etype == nil then etype = "" end
	if value == nil then value = "" end
	if pointholder == nil then pointholder = "" end
	if initiator == nil then initiator = "" end
	
	event.Type = etype
	event.Value = value
	event.BidType = bidType
	event.Pointholder = pointholder
	event.Initiator = initiator
	event.Item = item
	
	hour, minutes = GetGameTime()
	filler = ""
	ampm = " AM"
	if minutes < 10 then
		filler = "0"
	end
	if hour > 12 then
		hour = hour - 12
		ampm = " PM"
	end
		
	event.Time = hour .. ":" .. filler .. minutes .. ampm
	
	strDate = date()
	for word in string.gmatch(strDate, "../../..") do 
		strDate = word
	end
	event.Date = strDate
	
	if eventLog == nil or eventLog[1] == nil then
		event.Index = 1
	else
		lastEvent = EasyLOP:GetLastEvent()
		event.Index = lastEvent.Index + 1
	end
	
	self:Print("Adding " .. event.Type .. " to eventLog.")
	table.insert(eventLog, event)
	EasyLOP:ELOP_FrameRefresh()
end

--[[***********************************************************************************************************************************
***********************************************************************************************************************************
                         Points Stuff
***********************************************************************************************************************************
***********************************************************************************************************************************]]


Import = {
	RaidID = 0,
	ExportTime = "",
	Points = { },
	Slotted = { },
	Standby = { }
}

LeftoversDB = {
	ExportInfo = {},
	PointsPools = {
	}
}

--[[    -- Moved code up to the Initialize event
function Points:Init()  
	EasyLOP:RegisterDB("EasyLOPDB", "EastLOPDB_Points", "Default")--, "HelloWorldDBPerCharX")
	EasyLOP:RegisterDefaults( 'profile', EasyLOP.Points.Const.defaults )
end]]

function EasyLOP:UserGet(charName)
	self:Print( charName .. " has " .. EasyLOP:GetPoints(charName) .. " points.  (" .. EasyLOP.db.profile.RaidType .. ")")
end

function EasyLOP:Unlock()
		SendAddonMessage("ELOP", "ELOP_SET_SUSPEND^false " .. UnitName("player"), "RAID")
		tRollItems = {}
end

function EasyLOP:UserClear()
	EasyLOP:Clear()
	self:Print("Points cleared.  No points information now loaded.")
end

function EasyLOP:UserImport()
	--[[if raidtype == "10" then
		raidtype = "10-man"
	elseif raidtype == "25" then
		raidtype = "25-man"
	end]]
	
	self:Print( "Imported points for " .. EasyLOP:ImportData() .. " character names.  Time stamp: " .. EasyLOP.db.profile.ExportTime .. ".")
end

function EasyLOP:UserModify( name, bidtype)
	charged = EasyLOP:ModifyPoints( name, bidtype)
	
	 EasyLOP:LogEvent("Manual Charge", charged, name, UnitName("player"), bidtype)
	self:Print(name .. " has been charged " .. charged .. " for a " .. bidtype .. " bid and now has " .. EasyLOP:GetPoints(name) .. " points.")
end

function EasyLOP:UserSet( name, amt, bSync, sender)
	oldPts = EasyLOP:GetPoints(name)
	EasyLOP:SetPoints( name, amt, bSync )
	
	self:Print( "--" .. name .. " (" .. EasyLOP.db.profile.RaidType .. ")--  Old points:  " .. oldPts .. "   New points:  |cffe60000" .. EasyLOP:GetPoints(name) .. "|r")
	
	if bSync == nil or bSync == true then
		EasyLOP:LogEvent("User Set", amt, name, UnitName("player"))
	else
		EasyLOP:LogEvent("Synchronized Set", amt, name, sender)
	end
end

function EasyLOP:ExplainLOP(name)
	SendChatMessage('When loot is announced, you can send a tell to the LOOT MASTAH saying "Shroud", "Standard", or "Save".', "WHISPER", nil, name)
	SendChatMessage('"Shroud" means "GIMME GIMME GIMME!"  It will cost half your points.  You must have 10 points to Shroud.  Highest Shroud bid automatically wins.', "WHISPER", nil, name)
	SendChatMessage('"Standard" means "I want it, but am willing to roll off on it."  You will roll off against everyone else who Standards, provided there are no Shrouds.  Highest roll wins.  Standard costs 10 points, or whatever you have (min 0).', "WHISPER", nil, name)
	SendChatMessage('"Save" means "Eh, I will save it from DE".  You will roll off against everyone else who saved, as long as no one bid shroud or standard.  Save costs 10 points or however much you have (min 0).', "WHISPER", nil, name)
	SendChatMessage("Shroud beats Standard, which beats Save.  You're only charged points if you win the item, and you earn points after every raid.  You can only bid Standard or Save on your first night - BUT all your first night loot is free!", "WHISPER", nil, name)		
end

function EasyLOP:GetPoints( charName )
	pts = EasyLOP.db.profile.charPoints[strlower(charName)]
	if( pts == nil) then
		pts = 0
	end
	if type(pts) == string then
		pts = tonumber(pts)
	end
	
	--EasyLOP:Print( charName .. " = " .. pts )
	return tonumber(pts)
end

function EasyLOP:Clear()
	EasyLOP:ResetDB("profile")
	bPointsLoaded = false
	EasyLOP:LogEvent("Points Cleared", "", "", UnitName("player"))
end

function EasyLOP:ImportData()
	-- Clear the DB
	EasyLOP:ResetDB("profile")

	-- Copy source into DB
	iCount = 0
--	for charName, charPoints in pairs(EasyLOP.Points.Import.Points) do
	for charName, charPoints in pairs(LeftoversDB.PointsPools["Mists of Pandaria"].Points) do
		-- Parse "name":[w] into pts, warn
--		pts, warn = strmatch( charPoints, "([^:]*):([^:]*)")--"%s[:]%s")
		pts = strsplit( ":", charPoints )
		EasyLOP.db.profile.charPoints[strlower(charName)] = tonumber(pts) 
		iCount = iCount + 1
	end
	
	bPointsLoaded = true
	-- Store raid info
--	EasyLOP.db.profile.RaidID     = EasyLOP.Points.Import.RaidID
--	EasyLOP.db.profile.ExportTime = EasyLOP.Points.Import.ExportTime
	EasyLOP.db.profile.ExportTime = LeftoversDB.ExportInfo.Time	
	EasyLOP.db.profile.RaidType = "Mists of Pandaria"
	
	EasyLOP:LogEvent("Import", "Mists of Pandaria", "", UnitName("player"))
	return iCount
end

function EasyLOP:ListRoster( sel )
	-- Default selection
	if sel == nil or sel == "" then
		sel = "slotted"
	end
	sel = strlower(sel)
	
	if sel == "slotted" then
		EasyLOP:Print( "Slotted:" )
		for i, char in pairs(EasyLOP.Points.Import.Raids[EasyLOP.Points.Import.RaidID].Slotted) do
			-- Parse "name"[:w] into charName, warn
			charName, warn = strsplit( ":", char )
			EasyLOP:Print( char )
		end
	elseif sel == "standby" then
		EasyLOP:Print( "Standby:" )
		for i, char in pairs(EasyLOP.Points.Import.Raids[EasyLOP.Points.Import.RaidID].Standby) do
			-- Parse "name"[:w] into charName, warn
			charName, warn = strsplit( ":", char )
			EasyLOP:Print( char )
		end
	end
end

function EasyLOP:ModifyPoints( charName, bid, item)
	-- Convert input to integer (in case of call from command-line)
	
	--[[
	if type(bid) == string then
		bid = tonumber(bid)
	end]]
	iCharged = 0
	-- Find char first, unless it was a DE.  DE info can be captured into the log at a later date.
	if charName ~= 0 then 
		pts = EasyLOP:GetPoints( charName )
	else 
		return
	end
	
	-- Determine cost based on bid
	if tonumber(pts) == 0 then
		iCharged = 0
	elseif bid == "shroud" then
		
		if tonumber(pts) / 2 < 10 then
			pts = pts - 10
			iCharged = 10
		else
			iCharged = pts / 2
			pts = pts / 2
		end
	else	-- Else: std/save both cost 10
		if tonumber(pts) >= 10 then
			pts = pts - 10
			iCharged = 10
		else
			iCharged = pts
			pts = 0
		end

	end
	
	-- Now set new points in DB
	EasyLOP.db.profile.charPoints[strlower(charName)] = pts
	
	-- Log as event if appropriate
	--self:Print("item in modifypoints is " .. item)
	if item ~= nil and item ~= "" then
		--self:Print("Calling LogEvent from inside modifypoints.")
		--EasyLOP:LogEvent("Automated Charge", iCharged, charName, UnitName("player"), bid, item)
		
		
		sendString = ""
		sendString = sendString .. "SyncAutoCharge "
		sendString = sendString .. charName .. " " 
		sendString = sendString .. UnitName("player") .. " " 
		sendString = sendString .. "&& " .. bid .. " && " 
		sendString = sendString .. iCharged .. " item: " 
		sendString = sendString .. item 
		
		--for inctype, incbidder, incsender, incbidtype, inccharged, incitem in string.gmatch(msg, "(.+) (.+) (.+) && (.+) && (.+) item: (.+)") do
		--for incindex, incbidder, incbidtype, incpoints, incitem in string.gmatch(msg, "(%d+) (.+) && (.+) && (.+) item: (.+)") do
		SendAddonMessage("ELOP", "ELOP_AUTOCHARGE^" .. sendString, "RAID") -- you were here
	end
	
	return iCharged
end

function EasyLOP:SetPoints( charName, amt, bSync )
	if bSync == nil then
		bSync = true
	end
	
	if EasyLOP.db.profile.charPoints[strlower(charName)] == nil then
		--table.insert(EasyLOP.db.profile.charPoints, {strlower(charName) = amt})
		return
	else
		EasyLOP.db.profile.charPoints[strlower(charName)] = amt
		-- sync all users if appropriate
		if bSync == true then
			strSync = charName .. " " .. amt .. ".0"
			bSkipSyncMessage = true
			SendAddonMessage("ELOP", "ELOP_SYNCPOINTS^" .. strSync, "RAID")
		end
	end
end

--[[***********************************************************************************************************************************
***********************************************************************************************************************************
                         Options Frame Stuff
***********************************************************************************************************************************
***********************************************************************************************************************************]]

function EasyLOP:CreateOptionsFrame()
	--ELOP_Frame:Show()
	--ShowUIPanel(ELOP_Frame)
	
	ELOP_Frame.name = "EasyLOP"
	ELOP_FrameVersion:SetText("v" .. Version)
	ELOP_FrameSubText1:SetText("Points pool currently loaded:  " .. strRed .. "None")
	ELOP_FrameSubText2:SetText("Points imported on:  " .. strRed .. "No Date Available")
	
	ELOP_FrameVCLabel:SetText("Check other users' ELOP version and points loaded.")
	ELOP_FrameRepLabel:SetText("View all points-related events logged this session.")
	
	ELOP_FrameCBAutoAwardLabel:SetText("Have ELOP give loot to winners (ML only)")
	
	if bAutoAward == true then
		ELOP_FrameCBAutoAward:SetChecked(1)
	else
		ELOP_FrameCBAutoAward:SetChecked(nil)
	end
	
	InterfaceOptions_AddCategory(ELOP_Frame)
end

function EasyLOP:ELOP_FrameOnShow()
	EasyLOP:ELOP_FrameRefresh()
end

function EasyLOP:ELOP_FrameRefresh()
	if EasyLOP.db == nil or EasyLOP.db.profile.RaidType == "" or EasyLOP.db.profile.RaidType == nil then
		ELOP_FrameSubText1:SetText("Points pool currently loaded:  " .. strRed .. "None")
		ELOP_FrameSubText2:SetText("Current points were downloaded on:  " .. strRed .. "n/a")
	else
		ELOP_FrameSubText1:SetText("Points pool currently loaded:  " .. strGreen .. EasyLOP.db.profile.RaidType)
		ELOP_FrameSubText2:SetText("Current points were downloaded on:  " .. strGreen .. EasyLOP.db.profile.ExportTime)
	end
	
	--[[local event = EasyLOP:GetLastEvent()
	if event == nil then
		ELOP_FrameSubText3:SetText("Last points event was:  " .. strRed .. "n/a")
	else
		--ELOP_FrameSubText3:SetText("Last points event was:  " .. strGreen .. event.Type .. "|r at " .. strGreen .. event.Time .. " (" .. event.Date .. ")")
		ELOP_FrameSubText3:SetText(EasyLOP:CreateEventString(event))
	end]]
	
	if self.DEer == "" then
		ELOP_FrameDE:SetText("Designated Disenchanter:  " .. strRed .. "Unassigned")
	elseif EasyLOP:IsInRaid(self.DEer) == false then
		ELOP_FrameDE:SetText("Designated Disenchanter:  " .. strRed .. self.DEer .. " (Not in raid)")
	else
		ELOP_FrameDE:SetText("Designated Disenchanter:  " .. strGreen .. self.DEer)
	end
end

function EasyLOP:showOptions()
	self:Print("showOptions")
	ELOP_Frame.hidden = false
	ELOP_Frame:Show()
	ELOP_FrameRefresh()
end

function EasyLOP:CBAutoAward()
	if ELOP_FrameCBAutoAward:GetChecked() then
		bAutoAward = true
	else
		bAutoAward = false
	end
	
	--if bAutoAward == true then bAutoAward = false else bAutoAward = true end
	--[[
	if bAutoAward == true then
		ELOP_FrameCBAutoAward.checked = "true"
	else
		ELOP_FrameCBAutoAward.checked = "false"
	end]]
	
	EasyLOP.db.profile.bAutoAward = bAutoAward
end










