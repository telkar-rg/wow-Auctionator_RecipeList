local addonName, addonTable = ...

local lib = LibStub:NewLibrary(addonName, "$Revision: 5$")
if not lib then
  return
end

if not DataStore then
  return
end

local LTB = LibStub("LibTextbook-2.0")
if not LTB then
	print("MISSING LibTextbook-2.0")
	return
end

if not lib.frm then
  lib.frm = CreateFrame("Frame")
end

local calledOnce
local LIST_NAME = "\124cFF20ff20Textbook:RecipeList\124r"

local addonTitle = GetAddOnMetadata(addonName, "Title")
local addonVersion = GetAddOnMetadata(addonName, "Version")
local FINISH_PREFIX = format("\124cFF30FFFF<%s (%s)>\124r", addonTitle, addonVersion)
local FINISH_MSG_UPDATE = format("\124cFFFFFF20%s:\124r %s", AtrL["New Shopping List"] or "New Shopping List", LIST_NAME)

local itemClassRecipe = select(9, GetAuctionItemClasses() )


local function checkBitInNum(numCheck, bitPos)
	local bitBin = bit.lshift(1, bitPos)
	
	-- return true or nil
	if bit.band(numCheck, bitBin) > 0 then
		return true
	end
end

local function getRecipes(tbl, profName, enClass, enRace, profSpecSpell)
	if type(tbl) ~= "table" then return end
	local db = {}
	
	local profId = LTB:getProfessionLocale2SkillId(profName)
	if not profId then return end
	local classBin = LTB:getClassBin(enClass)
	if not classBin then return end
	local raceBin = LTB:getRaceBin(enRace)
	if not raceBin then return end
	
	local suc = LTB:getDbRaw(db)
	if not suc then return end
	
	-- clear return table
	for k,_ in pairs(tbl) do
		tbl[k] = nil
	end
	
	for itemId, entry in pairs(db) do
		if (
			entry["type"] == "RECIPE" and 		-- tradeskill recipes only
			not entry["note"] and 				-- skip "fake" and "trainable"
			entry["reqSkill"] == profId and 	-- selected profession only
			entry["binding"] ~= 1 and 			-- skip BoP
			(entry["quality"] > 1 or k == 10713 or k == 10644) and 	-- skip white ones (vendored) unless they are engineer created ones
			(not entry["reqClasses"] or checkBitInNum(entry["reqClasses"], classBin) ) and 	-- check if Class Requirement
			(not entry["reqRaces"]   or checkBitInNum(entry["reqRaces"],   raceBin) ) and 	-- check if Race Requirement
			(not entry["reqSpell"]   or (entry["reqSpell"] == profSpecSpell) ) 				-- check if Known Spell Requirement
		) then
			-- add to learnable spells for this character
			tbl[entry["teachesSpell"]] = itemId
		end
	end
	
	-- clear db table links
	for k,v in pairs(db) do
		db[k] = nil
	end
	return true
end

lib.frm:RegisterEvent("AUCTION_HOUSE_SHOW")
lib.frm:SetScript("OnEvent", function()
	-- for now: call only once per session
	if calledOnce then return end
	
	local CurrentRealm = GetRealmName()
	local CurrentAccount = "Default"
	local CurrentFaction = UnitFactionGroup("player")
	
	local neededRecipes = {}
	
	local charName, charKey
	-- get chars on this realm, default account only
	for charName, charKey in pairs(DataStore:GetCharacters(CurrentRealm, CurrentAccount)) do
		local professions
		
		-- must be same faction for sending mail
		if DataStore:GetCharacterFaction(charKey) == CurrentFaction then
			
			professions = DataStore:GetProfessions(charKey)
			if professions then     -- char must have stored professions
				
				local _, charEnglishClass = DataStore:GetCharacterClass(charKey)
				local _, charEnglishRace =  DataStore:GetCharacterRace(charKey)
				
				local profName, profData
				for profName, profData in pairs(professions) do
					local tsRecipes = {}
					
					if profData and profData["NumCrafts"] and profData["NumCrafts"] > 0 then
						local spellId, itemId, suc
						
						-- get table of all learnable recipes
						suc = getRecipes(tsRecipes, profName, charEnglishClass, charEnglishRace, nil)
						assert(suc, "Function 'getRecipes' failed.")
						
						-- remove if recipe kown by this character
						for spellId, itemId in pairs(tsRecipes) do
							if DataStore:IsCraftKnown(profData, spellId) then
								tsRecipes[spellId] = nil 	-- remove if known
							end
						end
						
						-- remove if THIS character owns recipe (bags/bank/mail)
						for spellId, itemId in pairs(tsRecipes) do
							local bagCount, bankCount = DataStore:GetContainerItemCount(charKey, itemId)
							local mailCount = DataStore:GetMailItemCount(charKey, itemId)
							
							if bagCount>0 or bankCount>0 or mailCount>0 then
								tsRecipes[spellId] = nil     -- remove if character owns the recipe
							end
						end
						
						-- add to global list
						for spellId, itemId in pairs(tsRecipes) do
							neededRecipes[itemId] = (neededRecipes[itemId] or 0) + 1
						end -- END LOOP add to global list ****
						
						wipe(tsRecipes)     -- clean table
						
					end -- END IF valid DS profData ####
				end -- END LOOP professions ****
				
			end -- END IF professions ####
		end -- END IF same faction ####
	end -- END LOOP CharNameList ****
	
	-- ****************************************************************
	
	-- delete all previous ShoppingLists with that name
	local done = false
	while not done do --delete all existing lists
		local p = 0
		local i
		for i=1,#AUCTIONATOR_SHOPPING_LISTS do
			if AUCTIONATOR_SHOPPING_LISTS[i]["name"]==LIST_NAME then
				p = i
				break;
			end
		end
		if p > 0 then
			-- wipe( AUCTIONATOR_SHOPPING_LISTS[p]["items"] )
			table.remove(AUCTIONATOR_SHOPPING_LISTS,p)
		else
			done = true
		end
	end
	
	-- make a fresh list and fill it
	local slist = Atr_SList.create(LIST_NAME.."1")
	local i
	for i=1,#AUCTIONATOR_SHOPPING_LISTS do
		if AUCTIONATOR_SHOPPING_LISTS[i]["name"]==LIST_NAME.."1" then
			AUCTIONATOR_SHOPPING_LISTS[i]["name"] = LIST_NAME
			-- wipe(AUCTIONATOR_SHOPPING_LISTS[i]["items"])
			break;
		end
	end
	
	local tItemsUsed = {}
	local itemId, count
	for itemId, count in pairs(neededRecipes) do
		local itemName = LTB:getItemName(itemId)
		
		if not tItemsUsed[itemName] then 	-- avoid possible duplicates
			tItemsUsed[itemName] = 1
			if count and count > 0 then
				slist:AddItem( format("%s/%s", itemClassRecipe, itemName) )
			end
		end
	end
	UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, 1);
	UIDropDownMenu_SetText (Atr_DropDownSL, AUCTIONATOR_SHOPPING_LISTS[1].name);
	-- Atr_SetUINeedsUpdate();
	
	-- for n = 1,#AUCTIONATOR_SHOPPING_LISTS do
		-- if (AUCTIONATOR_SHOPPING_LISTS[n] == slist) then
			-- UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, n);
			-- UIDropDownMenu_SetText (Atr_DropDownSL, text);	-- needed to fix bug in UIDropDownMenu
			-- slist:DisplayX();
			-- Atr_SetUINeedsUpdate();
			-- break;
		-- end
	-- end
	
	-- clean tables
	if neededRecipes then wipe(neededRecipes) end
	if tItemsUsed then wipe(tItemsUsed) end
	
	if not calledOnce then
		calledOnce = true
		print(FINISH_PREFIX)
	end
	print(FINISH_MSG_UPDATE)
end)
