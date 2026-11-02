local _,P=...
-- Only our recorded, unchanged character macros may be edited. Never delete macros:
-- deletion renumbers unrelated slots and can invalidate other action buttons.
function P:EnsureCastMacro(slot,body,icon)
 if InCombatLockdown and InCombatLockdown()then return nil,'Cannot prepare macros in combat'end
 if type(body)~='string'or #body>255 then return nil,'Macro exceeds the 255-byte limit'end
 if type(GetMacroInfo)~='function'or type(GetNumMacros)~='function'or type(CreateMacro)~='function'then return nil,'Saved macro APIs unavailable'end
 local constants=Constants and Constants.MacroConsts or {}
 local accountMax=constants.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS or 120
 local characterMax=constants.MAX_CHARACTER_MACROS or MAX_CHARACTER_MACROS or 18
 local records={};local names={}
 for index=1,accountMax+characterMax do
  local ok,name,_,text=pcall(GetMacroInfo,index)
  if not ok then return nil,'Cannot read macro slots'end
  if name then records[index]={name=name,body=text};names[name]=(names[name]or 0)+1 end
 end
 self.characterDB.ownedMacros=type(self.characterDB.ownedMacros)=='table'and self.characterDB.ownedMacros or {}
 local owned=self.characterDB.ownedMacros[slot];local chosen
 if type(owned)=='table'and names[owned.name]==1 then
  for index,row in pairs(records)do
   if index>accountMax and row.name==owned.name and row.body==owned.body then chosen=index;break end
  end
 end
 local name
 if chosen then
  name=owned.name
  if owned.body~=body then
   if type(EditMacro)~='function'then return nil,'Macro editing unavailable'end
   local ok=pcall(EditMacro,chosen,name,icon or 134400,body)
   if not ok then return nil,'Client rejected macro update'end
  end
 else
  local ok,_,count=pcall(GetNumMacros)
  if not ok or type(count)~='number'then return nil,'Cannot count character macros'end
  if count>=characterMax then return nil,'Character macro slots are full. Free a slot, then /ccprobe cast again.'end
  for suffix=1,999 do local candidate='CCP Cast '..suffix;if not names[candidate]then name=candidate;break end end
  if not name then return nil,'No unused CounterCast macro name'end
  local ok,index=pcall(CreateMacro,name,icon or 134400,body,true)
  if not ok or type(index)~='number'or index<=accountMax then return nil,'Client rejected character macro creation'end
  chosen=index
 end
 -- Macro lists may sort after an edit. Resolve by unique name and verify exact text.
 local found
 for index=accountMax+1,accountMax+characterMax do
  local ok,n,_,text=pcall(GetMacroInfo,index)
  if not ok then return nil,'Macro readback failed'end
  if n==name then
   if found or text~=body then return nil,'Macro readback mismatch; not arming'end
   found=index
  end
 end
 if not found then return nil,'Saved macro missing after write'end
 self.characterDB.ownedMacros[slot]={name=name,body=body}
 -- Bind by unique name so creating another slot cannot shift a prior binding.
 return name
end

function P:MacroConditionSnapshot(unit)
 if type(SecureCmdOptionParse)~='function'then return 'Macro condition parser unavailable'end
 local function parse(text)
  local ok,action,target=pcall(SecureCmdOptionParse,text)
  if not ok then return 'error','unknown'end
  if not P:IsPlain(action)or not P:IsPlain(target)then return 'restricted','restricted'end
  return action~=nil and 'allowed'or 'not matched',type(target)=='string'and target or 'none'
 end
 local direct,target=parse(unit)
 return 'direct /target '..unit..': '..direct..'; parser target='..target..'; no nameplate conditions or stopmacro; cast checks selected target after acquisition'
end
