local addon,P=...;_G.CounterCastProbe=P
P.version='0.1.8-experimental'
local function combat()return InCombatLockdown and InCombatLockdown()end
local function plainString(v)return P:IsPlain(v)and type(v)=='string'and v or nil end
function P:Say(s)if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffffcc55CounterCast Probe:|r '..s)end end
function P:Log(event,detail)
 if not self.db then return end
 local rows=self.db.log;rows[#rows+1]={at=time(),event=event,detail=plainString(detail)or ''}
 if #rows>80 then table.remove(rows,1)end
 -- Keep meaningful results even after repeated clicks or automatic disarm.
 if self.db.lastTrial and event~='loaded'then self.db.lastTrial.last[event]=rows[#rows]end
end
local function scalar(v)
 if not P:IsPlain(v)then return 'restricted'end
 local t=type(v);if t=='string'or t=='number'or t=='boolean'then return tostring(v)end
 return 'unknown'
end
local function read(fn,...)
 if type(fn)~='function'then return 'unavailable'end
 local ok,v=pcall(fn,...);return ok and scalar(v)or 'unavailable'
end
function P:ClickSnapshot(b)
 local unit=b.mode=='MACRO'and 'target'or b.mode=='CAST'and b.boundUnit or b.mode=='MOUSEOVER'and 'mouseover'or b:GetAttribute('unit')
 local inRange=C_Spell and C_Spell.IsSpellInRange
 local usable=C_Spell and C_Spell.IsSpellUsable
 return b.row.name..' #'..b.row.id..'; '..b.mode..'; unit='..unit..
  '; exists='..read(UnitExists,unit)..'; attackable='..read(UnitCanAttack,'player',unit)..
  '; range='..read(inRange,b.row.id,unit)..'; usable='..read(usable,b.row.id)..
  '; cooldown='..scalar(self:Cooldown(b.row.id))..'; combat='..tostring(not not combat())..
  '; mouseover matches plate='..read(UnitIsUnit,'mouseover',self.active and self.active.unit or 'none')
end
function P:SelectCastMacro(unit,name)
 unit=plainString(unit);name=plainString(name)
 local slot=unit and tonumber(unit:match('^nameplate(%d+)$'))
 if not slot or slot<1 or slot>40 or not name or name==''or name:find('[\r\n;%[%]]')then return end
 -- The native secure handler executes this entire fixed sequence on one release.
 -- Clear the previous target so failed acquisition cannot cast at that old enemy.
 -- Forever's condition parser did not recognize @nameplateN in the live test.
 -- Pass the fixed token directly to /target; only the resulting target is tested.
 return '/cleartarget\n/target '..unit..'\n/cast [@target,harm,nodead] '..name..'\n/targetlasttarget'
end
local function hitPoints(plate)
 if type(plate.GetHitTestPoints)~='function'then return end
 local ok,result=pcall(function()
  local points=plate:GetHitTestPoints()
  if not P:IsPlain(points)or type(points)~='table'then return end
  local copy={}
  for i,point in ipairs(points)do
   if not P:IsPlain(point)or type(point)~='table'then return end
   copy[i]={}
   for k,v in pairs(point)do
    if not P:IsPlain(k)or not P:IsPlain(v)then return end
    copy[i][k]=v
   end
  end
  return copy
 end)
 return ok and result or nil
end
local function samePoints(a,b)
 if not a or not b or #a~=#b then return false end
 for i,p in ipairs(a)do
  for k,v in pairs(p)do if b[i][k]~=v then return false end end
  for k,v in pairs(b[i])do if p[k]~=v then return false end end
 end
 return true
end
function P:ExtendHitbox(plate)
 if combat()then return end
 local original=hitPoints(plate)
 if not original or type(plate.SetHitTestPoints)~='function'or type(plate.ClearAllHitTestPoints)~='function'then
  self:Log('hitbox','Native hit-test API unavailable; mouseover test not armed.');return false
 end
 if read(plate.CanChangeHitTestPoints,plate)~='true'then
  self:Log('hitbox','Native hit-test permission denied; mouseover test not armed.');return false
 end
 -- Native hit-test anchors, not ordinary frame insets. The action stays on the root.
 local extended={
  {point='TOPLEFT',relativeTo=plate,relativePoint='TOPLEFT',offsetX=0,offsetY=25},
  {point='BOTTOMRIGHT',relativeTo=plate,relativePoint='BOTTOMRIGHT',offsetX=44,offsetY=-5},
 }
 local ok,err=pcall(plate.SetHitTestPoints,plate,extended)
 if not ok then self:Log('hitbox','Native hit-test extension rejected: '..scalar(err));return false end
 self.hitbox={plate=plate,original=original,extended=extended}
 local applied=hitPoints(plate)
 if not applied or #applied~=2 then self:Log('hitbox','Native hit-test readback failed; disarming.');return false end
 -- Capture the client's normalized representation for ownership checks on cleanup.
 self.hitbox.extended=applied
 for i,p in ipairs(extended)do for k,v in pairs(p)do
  if applied[i][k]~=v then self:Log('hitbox','Native hit-test readback does not match requested anchors; disarming.');return false end
 end end
 self:Log('hitbox','Native SetHitTestPoints accepted; saved original anchors. Live mouseover still needs verification.')
 return true
end
function P:RestoreHitbox()
 if combat()then return end
 local h=self.hitbox;if not h then return end
 local current=hitPoints(h.plate)
 if not current then self:Log('hitbox-restore','Unable to read native anchors. /reload restores native frames.');return end
 if not samePoints(current,h.extended)then
  self.hitbox=nil;self:Log('hitbox-restore','Native anchors replaced elsewhere; preserved the newer layout.');return
 end
 if read(h.plate.CanChangeHitTestPoints,h.plate)~='true'then self:Log('hitbox-restore','Permission denied; use /reload.');return end
 local ok,err
 if #h.original==0 then ok,err=pcall(h.plate.ClearAllHitTestPoints,h.plate)
 else ok,err=pcall(h.plate.SetHitTestPoints,h.plate,h.original)end
 if ok and samePoints(hitPoints(h.plate),h.original)then self.hitbox=nil;self:Log('hitbox-restore','Original native anchors restored and verified.')
 elseif ok then self:Log('hitbox-restore','Restore readback did not match; use /reload.')
 else self:Log('hitbox-restore','Restore rejected: '..scalar(err)..'; use /reload.')end
end
function P:TargetPlate()
 if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
 for i=1,40 do
  local unit='nameplate'..i
  local ok,same=pcall(UnitIsUnit,unit,'target')
  if ok and self:IsPlain(same)and same then
   local good,plate=pcall(C_NamePlate.GetNamePlateForUnit,unit)
   if good and plate and (not plate.IsForbidden or not plate:IsForbidden())then return plate,unit end
  end
 end
end
function P:Inspect()
 if combat()then self:Say('Inspect and arm outside combat.');return end
 local plate,unit=self:TargetPlate()
 if not plate then self:Say('Target a visible enemy with its nameplate enabled first.');return end
 local protected=plate:IsProtected()
 self:Say('Target uses '..unit..'; root '..(plate:GetName()or '(unnamed)')..'; protected '..tostring(protected)..'.')
 self:Log('inspect',unit..'; protected='..tostring(protected))
end
function P:Disarm()
 if combat()then
  self.pendingClear=true;self:Say('Disarm queued until combat ends. Existing buttons retain their fixed actions.');return
 end
 self.active=nil;self.pendingClear=nil;self.lastClickAt=nil;self.frame:SetScript('OnUpdate',nil)
 for _,b in ipairs(self.buttons or {})do
  b:Hide();b:SetAttribute('type',nil);b:SetAttribute('spell',nil);b:SetAttribute('unit',nil);b:SetAttribute('macrotext',nil);b:SetAttribute('macro',nil)
  b:ClearAllPoints();b:SetParent(UIParent)
 end
 self:RestoreHitbox()
 self:Log('disarm','Detached action buttons')
end
function P:OverlayOffset(plate)
 -- Read geometry once, but keep the actual anchor on the native root.
 -- Health-bar position is a likely point inside the existing native hit area.
 local ok,x,y=pcall(function()
  local uf=plate.UnitFrame
  local region=uf and ((uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)or uf.healthBar)
  if not region then return end
  local _,hy=region:GetCenter();local _,py=plate:GetCenter()
  local hx,px=region:GetRight(),plate:GetRight()
  local hs,ps=region:GetEffectiveScale(),plate:GetEffectiveScale()
  for _,v in ipairs({hx,hy,px,py,hs,ps})do if not self:IsPlain(v)or type(v)~='number'or v~=v or v==math.huge or v==-math.huge then return end end
  if not hx or not hy or not px or not py or not hs or not ps or ps<=0 or hs<=0 then return end
  -- Keep the icon just inside the right edge and slightly below the bar center.
  return (hx*hs-px*ps)/ps-2,(hy*hs-py*ps)/ps-3
 end)
 if ok and x and y then return x,y,'bar right edge measured; root RIGHT anchor, 2 inset / 3 down'end
 return -2,-3,'root-right fallback, 2 inset / 3 down; check hover recognition'
end
function P:Arm(id,compare,mouseover,selectCast,targetMacro,nativeSelect,overlay)
 if overlay then mouseover=true end
 if combat()then self:Say('Arm outside combat, while targeting the enemy you want to test.');return false end
 local plate,unit=self:TargetPlate()
 if not plate then self:Say('Target a visible enemy with its nameplate enabled first.');return false end
 local ok,hostile=pcall(UnitCanAttack,'player',unit)
 if not ok or not self:IsPlain(hostile)or not hostile then self:Say('Choose an attackable enemy.');return false end
 local rows
 if id then
  if not self:Known(id,false)and not self:Known(id,true)then self:Say('That spell is not currently learned.');return false end
  local name,icon=self:Spell(id);if not name then self:Say('Spell information unavailable.');return false end
  rows={{id=id,name=name,icon=icon,kind='Selected spell'}}
 else local _,class=UnitClass('player');rows=self:Candidates(class)end
 if nativeSelect then rows={{id=0,name='Select this enemy',kind='Native targeting diagnostic',icon=132212}}end
 if #rows==0 then self:Say('No learned interrupt/control candidates found. Use /ccprobe arm SPELL_ID to test another learned ability.');return false end
 if compare then rows={rows[1],rows[1]}end
 if mouseover or targetMacro then rows={rows[1]}end
 self:Disarm();self.buttons=self.buttons or {}
 if self.hitbox then self:Say('Previous hitbox could not be restored. /reload before another test.');return false end
 self.db.lastTrial={version=self.version,clicks=0,hoverMatches=0,hoverMissing=0,otherCasts=0,last={},config=(overlay and 'Mouseover overlay in existing plate area'or nativeSelect and 'Native select only; no casting'or targetMacro and 'Saved macro on current target'or selectCast and 'Saved macro: select + cast + return'or mouseover and 'Mouseover macro + native hit-test area'or compare and 'Comparison'or 'Plate')..'; '..unit..'; left release'}
 local before=plate:IsProtected()
 local success,err=pcall(function()
  for i,row in ipairs(rows)do
   local b=self.buttons[i]
   if not b then
    b=CreateFrame('Button','CounterCastProbeButton'..i,UIParent,'SecureActionButtonTemplate');self.buttons[i]=b
    b:SetSize(30,30);b:SetFrameStrata('HIGH');b:RegisterForClicks('LeftButtonDown','LeftButtonUp')
    b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetAllPoints()
    b:SetNormalTexture('Interface\\Buttons\\UI-Quickslot2')
    b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
    b.status=b:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');b.status:SetPoint('BOTTOM',b,'TOP',0,3)
    b.mark=b:CreateFontString(nil,'OVERLAY','GameFontNormal');b.mark:SetPoint('TOP',b,'BOTTOM',0,-2)
    b.label=b:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');b.label:SetPoint('TOP',b,'BOTTOM',0,-16)
    -- Observe only. Never replace or call the inherited secure OnClick handler.
    b:HookScript('PreClick',function(s,button,down)
     if button~='LeftButton'or down then return end
     local trial=P.db.lastTrial;trial.clicks=trial.clicks+1
     P.lastClickAt=GetTime()
     if s.mode=='SELECT'then
      P:Log('select-before','target exists='..read(UnitExists,'target')..'; target matches plate='..read(UnitIsUnit,'target',s.boundUnit)..'; effective unit='..read(SecureButton_GetModifiedUnit,s,button))
      return
     end
     if s.mode=='MOUSEOVER'then
      if P.hitbox then P:Log('native-hit-test',samePoints(hitPoints(P.hitbox.plate),P.hitbox.extended)and 'Extended native anchors still present at click.'or 'Native anchors changed or unreadable at click.')end
      local exists=read(UnitExists,'mouseover');local same=read(UnitIsUnit,'mouseover',P.active and P.active.unit or 'none')
      if same=='true'then trial.hoverMatches=trial.hoverMatches+1 end
      if exists=='false'then
       trial.hoverMissing=trial.hoverMissing+1
       if trial.hoverMissing==1 then P:Say('No mouseover enemy at this click. The macro has no target; /ccprobe report retains the result.')end
      end
     end
     P:Log('attempt-'..s.mode,P:ClickSnapshot(s))
     if s.mode=='CAST'then P:Log('macro-conditions',P:MacroConditionSnapshot(s.boundUnit))end
    end)
    b:HookScript('PostClick',function(s,button,down)
     if button~='LeftButton'or down then return end
     P:Log('click',s.mode..'; release received; targeting cursor='..read(SpellIsTargeting))
     if s.mode=='SELECT'then
      local match=read(UnitIsUnit,'target',s.boundUnit)
      P:Log('select-after','target exists='..read(UnitExists,'target')..'; target matches plate='..match)
      P:Say('SELECT result: target matches attached enemy='..match..'. This test does not cast.');return
     end
     if s.mode=='CAST'then
      P:Log('selected-after-click','click #'..P.db.lastTrial.clicks..'; after targetlasttarget: target exists='..read(UnitExists,'target')..'; target matches plate='..read(UnitIsUnit,'target',s.boundUnit)..'; final selection only, not cast confirmation')
     end
    end)
    b:SetScript('OnEnter',function(s)
     if not GameTooltip then return end
     GameTooltip:SetOwner(s,'ANCHOR_RIGHT');GameTooltip:SetText(s.row.name)
     if s.mode=='SELECT'then GameTooltip:AddLine('Clear your target, then click once. Tests native selection only; no spell is cast.',1,.8,.35,true);GameTooltip:Show();return end
     GameTooltip:AddLine(s.row.kind..' - experimental nameplate action',1,.8,.35)
     GameTooltip:AddLine('Casting unit: '..(s.mode=='MACRO'and 'target'or s.mode=='CAST'and s.boundUnit or s.mode=='MOUSEOVER'and 'mouseover'or s:GetAttribute('unit')),1,1,1)
     if s.mode=='MACRO'then GameTooltip:AddLine('Diagnostic: saved macro casts at your selected enemy, without switching targets.',1,.8,.35,true)end
     if s.mode=='CAST'then GameTooltip:AddLine('One click selects this enemy, casts, then uses targetlasttarget to switch back.',1,.8,.35,true)end
     if s.mode=='TARGET'then GameTooltip:AddLine('Comparison only: casts at your SELECTED target. Keep this enemy selected.',1,.5,.2,true)end
     if s.mode=='MOUSEOVER'then GameTooltip:AddLine('Mouseover-only macro. No selected-target fallback. Check that hovering this icon identifies this enemy.',1,.5,.2,true)end
     GameTooltip:AddLine('Left-click and release. READY checks cooldown only.',1,1,1,true)
     GameTooltip:AddLine('Control effects may fail on immune enemies.',1,.8,.35,true);GameTooltip:Show()
    end)
    b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
   end
   b.row=row;b.boundUnit=unit;b.mode=nativeSelect and 'SELECT'or targetMacro and 'MACRO'or selectCast and 'CAST'or mouseover and 'MOUSEOVER'or compare and i==2 and 'TARGET'or 'PLATE';b.label:SetText(overlay and 'OVERLAY'or nativeSelect and 'SELECT'or targetMacro and 'MACRO'or selectCast and 'CAST'or mouseover and 'MOUSE'or compare and b.mode or '')
   b.icon:SetTexture(row.icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
   -- One-time native-root anchor. No parent, point or action changes in combat.
   b:SetParent(plate);b:ClearAllPoints();b:SetSize(overlay and 20 or 30,overlay and 20 or 30)
   if overlay then
    local x,y,reason=self:OverlayOffset(plate);b:SetPoint('RIGHT',plate,'RIGHT',x,y)
    self:Log('overlay-layout',reason..'; offset='..scalar(x)..','..scalar(y)..'; native hit area unchanged')
   else b:SetPoint('LEFT',plate,'RIGHT',10+(i-1)*(compare and 65 or 35),10)end
   b:SetAttribute('type','spell');b:SetAttribute('spell',row.id);b:SetAttribute('unit',b.mode=='TARGET'and 'target'or unit)
   if nativeSelect then b:SetAttribute('type','target');b:SetAttribute('spell',nil)end
   if mouseover then
    b:SetAttribute('type','macro');b:SetAttribute('spell',nil);b:SetAttribute('unit',nil)
    b:SetAttribute('macrotext','/cast [@mouseover,harm,nodead] '..row.name)
   end
   if selectCast or targetMacro or overlay then
    local macro=self:SelectCastMacro(unit,row.name);if not macro then error('Invalid unit or spell for select-and-cast macro')end
    if targetMacro then macro='/cast [@target,harm,nodead] '..row.name end
    if overlay then macro='/cast [@mouseover,harm,nodead] '..row.name end
    local name,reason=self:EnsureCastMacro(i,macro,row.icon);if not name then error(reason)end
    b:SetAttribute('type','macro');b:SetAttribute('spell',nil);b:SetAttribute('unit',nil);b:SetAttribute('macrotext',nil);b:SetAttribute('macro',name)
    self:Log('macro-path','Saved character macro '..name..'; bytes='..#macro..'; native RunMacro='..tostring(type(RunMacro)=='function')..'; inline C_Macro.RunMacroText='..tostring(C_Macro and type(C_Macro.RunMacroText)=='function'or false))
   end
   -- Keep the secure click handler but let native hit testing receive mouse motion.
   -- Motion propagation alone did not preserve mouseover in the user's 0.1.1 test.
   if mouseover and (type(b.SetMouseMotionEnabled)~='function'or type(b.SetMouseClickEnabled)~='function')then error('Separate mouse-motion/click APIs unavailable')end
   if type(b.SetMouseMotionEnabled)=='function'then b:SetMouseMotionEnabled(not mouseover)end
   if type(b.SetMouseClickEnabled)=='function'then b:SetMouseClickEnabled(true)end
   if type(b.SetPropagateMouseMotion)=='function'then b:SetPropagateMouseMotion(overlay==true)end
   if overlay and type(b.SetPropagateMouseClicks)=='function'then b:SetPropagateMouseClicks(false)end
   if mouseover then self:Log('mouseover-setup','Icon mouse motion disabled; secure clicks enabled. Hover passes to native hit-test area.')end
   b:SetAttribute('checkselfcast',false);b:SetAttribute('checkfocuscast',false)
   b:SetAttribute('useOnKeyDown',false);b:Show()
   self:Log('button-'..i,b.mode..(nativeSelect and '; action=target; unit='..unit or '; spell='..row.id)..'; secure='..read(b.IsProtected,b)..
    '; native handler='..tostring(b:GetScript('OnClick')==SecureActionButton_OnClick and type(SecureActionButton_OnClick)=='function'))
  end
 end)
 if not success then
  self:Log('anchor-rejected',plainString(err));self:Disarm()
  self:Say('Button setup failed: '..scalar(err)..'. /ccprobe report retains the diagnostic.');return false
 end
 if mouseover and not overlay and not self:ExtendHitbox(plate)then
  self:Disarm();self:Say('Native hit-test setup failed. /ccprobe report shows why.');return false
 end
 self.active={plate=plate,unit=unit,rows=rows,compare=compare,mouseover=mouseover,selectCast=selectCast,nativeSelect=nativeSelect,overlay=overlay};self.db.lastUnit=unit
 self:Log('armed',unit..'; rootProtectedBefore='..tostring(before)..'; after='..tostring(plate:IsProtected()))
 self:Say('Experimental bar armed beside '..unit..(nativeSelect and '. Selection test only.'or '. Fixed spells; > marks a ready cooldown.')..' /ccprobe off detaches after combat.')
 if compare then self:Say('PLATE and TARGET use the same spell. Keep this enemy selected; try PLATE first, then TARGET only if PLATE does nothing.')end
 if selectCast then self:Say('Click CAST to select this enemy, cast, then targetlasttarget in one release. With no initial target, the game may restore an older target. /ccprobe report retains the result.')end
 if targetMacro then self:Say('Diagnostic MACRO casts only at your current target. Keep this enemy selected; one release tests the saved-macro execution path.')end
 if nativeSelect then self:Say('Clear your target, then click SELECT once. This uses the native target action, not a macro, and does not cast or return to the old target.')end
 if overlay then self:Say('Hover the CENTER of OVERLAY. Click once only with HOVER OK, ready spell and range. This casts at mouseover without changing your selected target. /ccprobe report retains the result.')
 elseif mouseover then self:Say('Hover MOUSE and look for HOVER OK. Native hit-test extension is temporary. /ccprobe report retains the result.')end
 local elapsed=0;self.frame:SetScript('OnUpdate',function(_,dt)
  elapsed=elapsed+dt;if elapsed<.2 then return end;elapsed=0;P:UpdateVisuals()
 end)
 self:UpdateVisuals();return true
end
function P:UpdateVisuals()
 local a=self.active;if not a then return end
 local matched,plate=pcall(C_NamePlate.GetNamePlateForUnit,a.unit)
 if not matched or plate~=a.plate then
  if not combat()then self:Disarm()else
   for i in ipairs(a.rows)do self.buttons[i].status:SetText('CHECK');self.buttons[i].mark:SetText('!')end
  end
  return
 end
 local chosen
 if a.nativeSelect then self.buttons[1].status:SetText('SELECT ONLY');self.buttons[1].mark:SetText('');return end
 for i,row in ipairs(a.rows)do
  local b=self.buttons[i];local remaining=self:Cooldown(row.id)
  if remaining==0 and not chosen then chosen=i end
  b.icon:SetDesaturated(remaining==nil or remaining>0)
  b.status:SetText(remaining==nil and '?'or remaining==0 and 'READY'or tostring(math.ceil(remaining))..'s')
 end
 for i in ipairs(a.rows)do
  local mark=not a.compare and i==chosen and '>'or ''
  if a.mouseover then
   local exists=read(UnitExists,'mouseover');local same=read(UnitIsUnit,'mouseover',a.unit)
   mark=exists=='false'and 'NO UNIT'or same=='true'and 'HOVER OK'or same=='false'and 'OTHER UNIT'or 'HOVER ?'
  end
  self.buttons[i].mark:SetText(mark)
 end
end
function P:Report()
 self:Say('Probe '..self.version..'; '..(self.active and ('armed on '..self.active.unit)or 'not armed')..'.')
 local t=self.db.lastTrial
 if not t then self:Say('No test recorded. Target an enemy outside combat and use /ccprobe compare.');return end
 self:Say('Last test '..t.version..': '..t.config..'; clicks='..t.clicks)
 if t.hoverMatches then self:Say('Clicks with matching mouseover='..t.hoverMatches..'; missing mouseover='..t.hoverMissing..'; unrelated casts excluded='..t.otherCasts)end
 for _,key in ipairs({'button-1','button-2','macro-path','overlay-layout','mouseover-setup','hitbox','armed','native-hit-test','select-before','select-after','attempt-PLATE','attempt-TARGET','attempt-MOUSEOVER','attempt-CAST','attempt-MACRO','macro-conditions','click','selected-after-click','tested-spell-success','tested-spell-failed','error-after-click','ADDON_ACTION_BLOCKED','ADDON_ACTION_FORBIDDEN','anchor-rejected','hitbox-restore'})do
  local r=t.last[key];if r then self:Say(r.event..': '..r.detail)end
 end
 if t.last['select-before']then self:Say('Selection-only test; no cast expected.')elseif not t.last['tested-spell-success']then self:Say('No tested-spell success recorded. Other spells do not count.')end
end
local f=CreateFrame('Frame');P.frame=f
for _,e in ipairs({'ADDON_LOADED','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UI_ERROR_MESSAGE','ADDON_ACTION_BLOCKED','ADDON_ACTION_FORBIDDEN'})do f:RegisterEvent(e)end
f:SetScript('OnEvent',function(_,e,...)
 if e=='ADDON_LOADED'then
  if ...~=addon then return end
  CounterCastProbeDB=type(CounterCastProbeDB)=='table'and CounterCastProbeDB or {}
  CounterCastProbeCharacterDB=type(CounterCastProbeCharacterDB)=='table'and CounterCastProbeCharacterDB or {};P.characterDB=CounterCastProbeCharacterDB
  P.db=CounterCastProbeDB;P.db.log=type(P.db.log)=='table'and P.db.log or {};P:Log('loaded','Dormant until /ccprobe arm');return
 end
 if not P.db then return end
 if e=='PLAYER_REGEN_ENABLED'then
  if P.active then P:Log('combat-end','Anchor test completed')end
  -- Always disarm after one fight: recycled nameplate assignments are not proven safe.
  if P.active or P.pendingClear then P:Disarm()end
 elseif e=='PLAYER_REGEN_DISABLED'and P.active then P:Log('combat-start',P.active.unit)
 elseif (e=='UNIT_SPELLCAST_SUCCEEDED'or e=='UNIT_SPELLCAST_FAILED')and P.active and not P.active.nativeSelect then
  local unit,_,id=...;if plainString(unit)=='player'or plainString(unit)=='pet'then
   -- Match the tested spell family; unrelated casts cannot overwrite its result.
   if P:IsPlain(id)and type(id)=='number'then
    local name=P:Spell(id);local matches=false
    for _,row in ipairs(P.active.rows)do if id==row.id or (name and name==row.name)then matches=true;break end end
    if matches then P:Log(e=='UNIT_SPELLCAST_SUCCEEDED'and 'tested-spell-success'or 'tested-spell-failed',(name or 'Spell')..' #'..id..'; caster='..unit..'; observed event, button origin not proven')
    else P.db.lastTrial.otherCasts=P.db.lastTrial.otherCasts+1 end
   end
  end
 elseif e=='UI_ERROR_MESSAGE'and P.active then
  local code,message=...;message=plainString(message)or plainString(code)
  if message and P.lastClickAt and GetTime()-P.lastClickAt<=1 then P:Log('error-after-click',message..'; within 1s of click, cause not proven')end
 elseif e=='ADDON_ACTION_BLOCKED'or e=='ADDON_ACTION_FORBIDDEN'then
  local owner,action=...;if P.active or plainString(owner)==addon then P:Log(e,scalar(owner)..'; '..scalar(action))end
 end
end)
SLASH_COUNTERCASTPROBE1='/ccprobe'
SlashCmdList.COUNTERCASTPROBE=function(msg)
 if not P.db then return end
 msg=(msg or ''):lower():match('^%s*(.-)%s*$')
 local command,arg=msg:match('^(%S+)%s*(.-)$')
 if command=='select'then P:Arm(nil,false,false,false,false,true)
 elseif command=='arm'or command=='compare'or command=='mouseover'or command=='cast'or command=='macro'or command=='overlay'then
  if arg~=''and not arg:match('^%d+$')then P:Say('Use /ccprobe '..command..' or /ccprobe '..command..' SPELL_ID.');return end
  P:Arm(arg~=''and tonumber(arg)or nil,command=='compare',command=='mouseover',command=='cast',command=='macro',false,command=='overlay')
 elseif command=='off'then P:Disarm()
 elseif command=='report'then P:Report()
 elseif command=='inspect'then P:Inspect()
 else P:Say('/ccprobe overlay [SPELL_ID] (mouseover inside plate) | select | cast [SPELL_ID] | macro [SPELL_ID] | inspect | arm [SPELL_ID] | compare [SPELL_ID] | mouseover [SPELL_ID] | off | report. Arm outside combat; one-fight test.')end
end
