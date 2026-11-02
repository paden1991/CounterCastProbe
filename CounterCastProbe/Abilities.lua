local _,P=...
-- Candidate spell families only. Never grants an ability: the client must confirm
-- a learned rank. Controls are labeled separately and may fail on immune enemies.
P.abilities={
 WARRIOR={{kind='Interrupt',ids={6554,6552}},{kind='Interrupt',ids={1672,1671,72}},{kind='Stun',ids={12809}}},
 ROGUE={{kind='Interrupt',ids={1769,1768,1767,1766}},{kind='Stun',ids={8643,408}},{kind='Incapacitate',ids={11286,11285,8629,1777,1776}}},
 MAGE={{kind='Interrupt',ids={2139}}},
 SHAMAN={{kind='Interrupt',ids={10414,10413,10412,8046,8045,8044,8042}}},
 DRUID={{kind='Interrupt / charge',ids={16979}},{kind='Stun',ids={8983,6798,5211}}},
 HUNTER={{kind='Incapacitate',ids={19503}},{kind='Pet stun',ids={19577}}},
 PALADIN={{kind='Stun',ids={10308,5589,5588,853}}},
 PRIEST={{kind='Silence',ids={15487}},{kind='Fear',ids={10890,10888,8124,8122}}},
 WARLOCK={{kind='Pet interrupt',pet=true,ids={19647,19244}},{kind='Horror',ids={17926,17925,6789}}},
}
P.racial={kind='Stun',ids={20549}}
function P:IsPlain(v)
 if issecretvalue and issecretvalue(v) then return false end
 return true
end
function P:Known(id,pet)
 local ok,v
 if IsSpellKnown then ok,v=pcall(IsSpellKnown,id,pet==true)
 elseif C_SpellBook and C_SpellBook.IsSpellKnown then
  local bank=Enum and Enum.SpellBookSpellBank
  if pet and not bank then return false end
  ok,v=pcall(C_SpellBook.IsSpellKnown,id,bank and (pet and bank.Pet or bank.Player))
 elseif not pet and IsPlayerSpell then ok,v=pcall(IsPlayerSpell,id)end
 return ok and self:IsPlain(v) and v==true
end
function P:Spell(id)
 if C_Spell and C_Spell.GetSpellInfo then
  local ok,info=pcall(C_Spell.GetSpellInfo,id)
  if ok and info and self:IsPlain(info.name)then return info.name,info.iconID end
 elseif GetSpellInfo then
  local ok,name,_,icon=pcall(GetSpellInfo,id)
  if ok and self:IsPlain(name)then return name,icon end
 end
end
function P:Candidates(class)
 local out={};local families={}
 for _,row in ipairs(self.abilities[class]or {})do families[#families+1]=row end
 families[#families+1]=self.racial
 for _,row in ipairs(families)do
  for _,id in ipairs(row.ids)do if self:Known(id,row.pet)then
   local name,icon=self:Spell(id)
   if name then out[#out+1]={id=id,name=name,icon=icon,kind=row.kind,pet=row.pet}end
   break
  end end
 end
 return out
end
function P:Cooldown(id)
 local start,duration,enabled,onGCD
 if C_Spell and C_Spell.GetSpellCooldown then
  local ok,info=pcall(C_Spell.GetSpellCooldown,id)
  if not ok or not info then return end
  start,duration,enabled,onGCD=info.startTime,info.duration,info.isEnabled,info.isOnGCD
 elseif GetSpellCooldown then
  local ok;ok,start,duration,enabled=pcall(GetSpellCooldown,id);if not ok then return end
 end
 if not self:IsPlain(start)or not self:IsPlain(duration)or not self:IsPlain(enabled)then return end
 if type(start)~='number'or type(duration)~='number'then return end
 if enabled==false or enabled==0 then return end
 if self:IsPlain(onGCD)and onGCD==true then return 0 end
 return math.max(0,start+duration-GetTime())
end
