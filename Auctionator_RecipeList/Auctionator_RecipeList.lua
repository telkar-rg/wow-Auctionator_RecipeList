local lib = LibStub:NewLibrary("MyLibrary-1.0", "$Revision: 5$")

if not lib then
  return
end

if not DataStore then
  return
end

if not lib.frm then
  lib.frm = CreateFrame("Frame")
end

local run_once
local LIST_NAME = "\124cFF20ffffTextbook:Recipes\124r"
local itemClassRecipe = select(9, GetAuctionItemClasses() )

local function GetID(s,t) 	-- this is a SLOW lookup - avoid if possible!
	local id
	for k,v in pairs(t) do
		if v==s then
			id = k
		end
	end
	return id
end

lib.frm:RegisterEvent("AUCTION_HOUSE_SHOW")
lib.frm:SetScript("OnEvent", function()
	-- run only once per session due to weird behaviour of DataStore
	-- if run_once then return end
	-- run_once = true
	
	local CurrentRealm = GetRealmName()
	local CurrentAccount = "Default"
	local CurrentFaction = UnitFactionGroup("player")
	
	local neededRecipes = {}
	
	-- local CharNameList = DataStore:GetCharacters(CurrentRealm, CurrentAccount) 	-- get chars on this realm, default account only
	local charName, charKey
	for charName, charKey in pairs(DataStore:GetCharacters(CurrentRealm, CurrentAccount)) do
		local professions
		
		-- must be same faction for sending mail
		if DataStore:GetCharacterFaction(charKey) == CurrentFaction then
			
			professions = DataStore:GetProfessions(charKey)
			if professions then     -- char must have stored professions
				
				local _, charEnglishClass = DataStore:GetCharacterClass(charKey)
				local _, charEnglishRace =  DataStore:GetCharacterRace(charKey)
				local charClassID = LibTextbookReference["englishClass_inv"][charEnglishClass] or 0
				local charRaceID =  LibTextbookReference["englishRace_inv"][charEnglishRace] or 0
				
				-- get bit representation for class/race requirements
				local charClassIdBinary = bit.lshift(1, charClassID)
				local charRaceIdBinary =  bit.lshift(1, charRaceID)
				
				local profName, profData
				for profName, profData in pairs(professions) do
					local tsRecipes = {}
					
					-- check if profName is a localized profession-skill name
					local profID = LibTextbookReference["skill_profession_inv"][profName]
					if profID and profData and profData["NumCrafts"] and profData["NumCrafts"] > 0 then
						
						-- get table of all learnable recipes
						local k, entry
						for k, entry in pairs(LibTextbookDB) do
							if (
								not entry["note"] and 				-- skip "fake" and "trainable"
								entry["type"] == "RECIPE" and 		-- tradeskill recipes only
								entry["reqSkill"] == profID and 	-- selected profession only
								entry["binding"] ~= 1 and 			-- skip BoP
								(entry["quality"] > 1 or k == 10713 or k == 10644) and 	-- skip white ones (vendored) unless they are engineer created ones
								(not entry["reqClasses"] or (bit.band(entry["reqClasses"], charClassIdBinary) > 0) ) and 	-- check if Class Requirement
								(not entry["reqRaces"]   or (bit.band(entry["reqRaces"],   charRaceIdBinary) > 0) ) and 	-- check if Race Requirement
								(not entry["reqSpell"]   or DataStore:IsSpellKnown(charKey, entry["reqSpell"]) ) 					-- check if Known Spell Requirement
							) then
								-- check if this character alredy knows it
								if not DataStore:IsCraftKnown( profData, entry["teachesSpell"]) then
									-- add to learnable spells for this character
									tsRecipes[entry["teachesSpell"]] = k
								end
							end
						end -- END LOOP learnable recipes ****
						
						-- ignore owned recipes of THIS character (bags/bank/mail)
						local spellId, itemId
						for spellId, itemId in pairs(tsRecipes) do
							local bagCount, bankCount = DataStore:GetContainerItemCount(charKey, itemId)
							local mailCount = DataStore:GetMailItemCount(charKey, itemId)
							
							if bagCount>0 or bankCount>0 or mailCount>0 then
								tsRecipes[spellId] = nil     -- remove if character owns the recipe
							end -- END IF count > 0 ####
						end -- END LOOP ignore owned recipes ****
						
						-- add to global list
						for spellId, itemId in pairs(tsRecipes) do
							neededRecipes[itemId] = (neededRecipes[itemId] or 0) + 1
						end -- END LOOP add to global list ****
						
						wipe(tsRecipes)     -- clean table
						
					end -- END IF profID ####
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
	
	-- if true then return end
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
	local item, count
	for item, count in pairs(neededRecipes) do
		local itemName = LibTextbookDB[item]["itemName"]
		
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
	
	print("-- Fresh slist created")
end)
