--[[
Musescore 4 to Cinematic Studio Strings, Solo Strings, Brass and Woodwinds libraries Reaper compatible converter
Works by detecting articulation from REAticulate, sets basic dynamics, detects rebow, repairs legato timings, sets velocity for short articulation based on dynamics
Needs to be used with accompanying REAticulate template and Project template!
Musescore_CS_converter.lua
Copyright © 2023 3YY3, MIT License
Not affiliated with MuseScore and/or Cinematic Studio Series in any way.
]]--

-- DEFAULT VALUES
local DEBUG = false
local DELETE_CC1_EVTS = false -- Delete all CC1 events prior to running the conversion
local DELETE_SUSTAIN_PEDAL_EVTS = false -- Delete all CC64 events prior to running the conversion
local dynEventIterationCount = 9999 -- For loop iterating midi events runs this long (to evade bad count which is done by MIDI_CountEvts function)

local css_slow = { --Expressive legato
    273, --333 ms minus 60 ms
    190, --250 ms minus 60 ms
    40 --100 ms minus 60 ms
}
local css_fast = { --Low-latency legato
    173, --233 ms minus 60 ms
    125, --185 ms minus 60 ms
    96 --156 ms minus 60 ms
}
local csssolo_slow = { --Advanced legato
    273, --333 ms minus 60 ms
    190, --250 ms minus 60 ms
    40 --100 ms minus 60 ms
}
local csssolo_fast = { --Standart legato
    190, --250 ms minus 60 ms
    40, --100 ms minus 60 ms
    40 --100 ms minus 60 ms
}
local csw_slow = { --Expressive legato
    160, --220 ms minus 60 ms
    70, --130 ms minus 60 ms
    30 --90 ms minus 60 ms
}
local csw_fast = { --Low-latency legato
    30, --90 ms minus 60 ms
    10, --70 ms minus 60 ms
    10 --70 ms minus 60 ms
}
local csb_trumpet = { --Legato: trumpet
    120, --180 ms minus 60 ms
    40, --100 ms minus 60 ms
    40 --100 ms minus 60 ms
}
local csb_other = { --Legato: trombones, horns and tuba
    170, --230 ms minus 60 ms
    40, --100 ms minus 60 ms
    40 --100 ms minus 60 ms
}

local legatofastvalues = { 
    0, --CSS
    19, --CSB
    34, --CSW
    47 --CSSS
}
local legatoslowvalues = { 
    1, --CSS
    35, --CSW
    48 --CSSS
}
local shortvalues = { 
    2, 3, 4, 5, 6, 7, 8, 12, --CSS
    20, 21, 22, 23, 24, 25, --CSB
    36, 37, 38, 39, 42, --CSW
    49, 50, 51, 52, 53, 54, 55, 59 --CSSS
}
local longvalues = { 
    9, 10, 11, 13, 14, --CSS
    26, 27, 28, 29, 30, 31, --CSB
    40, 41, 43, 44, --CSW
    56, 57, 58, 60, 61 --CSSS
}


-- Get the package path to MIDIUtils 
 package.path = reaper.GetResourcePath() .. '/Scripts/sockmonkey72 Scripts/MIDI/?.lua'
local mu = require 'MIDIUtils'


-- Define the CC1 values for dynamics
local dynamics = {
    ["ppppp"] = 1,
    ["pppp"] = 1,
    ["ppp"] = 2,
    ["pp"] = 10,
    ["p"] = 20,
    ["mp"] = 40,
    ["mf"] = 60,
    ["f"] = 80,
    ["ff"] = 110,
    ["fff"] = 126,
    ["ffff"] = 127,
    ["fffff"] = 127
}


--Scythe GUI initialization
local libPath = reaper.GetExtState("Scythe v3", "libPath")
if not libPath or libPath == "" then
    reaper.MB("Couldn't load the Scythe library. Please install 'Scythe library v3' from ReaPack, then run 'Script: Scythe_Set v3 library path.lua' in your Action List.", "Whoops!", 0)
    return
end
loadfile(libPath .. "scythe.lua")()
local Image = require("public.image")


--Error messages and checks
function takeError()
    reaper.ShowMessageBox("Please, open some MIDI take in editor first.", "Error", 0)
end


function takeCheck(check)
    local check = true
    local _, notecnt = reaper.MIDI_CountEvts(take)
    if notecnt == 0 then
        reaper.ShowMessageBox("No notes exist in active take!", "Error", 0)
        check = false
    end
    return check
end


-- Function for converting dynamics - process the imported .mxl MIDI events
function convertDynamics()
    local eventTable = {}
    local lastDynamic = 0
    local firstRun = 0 -- Check if the first run through midi events is already happening
    
    -- Main loop
    for i = 0, dynEventIterationCount, 1 do
        local _, _, _, ppqpos, msg = reaper.MIDI_GetEvt(take, i, true, true, 0, "")
        if firstRun > 1 and ppqpos == 0 then -- This indicated 1+n iteration through desired midi events and exits the for loop
            break
        elseif msg:find("dynamic ") and not (msg:find("dynamic crescendo") or msg:find("dynamic diminuendo")) then
            local dynamic = msg:match("dynamic ([%a]+)")    
            if dynamics[dynamic] then
                -- Populate table
                table.insert(eventTable, {ppqpos = ppqpos, dynamic = dynamics[dynamic], gradual=false})
                lastDynamic = dynamics[dynamic]
                firstRun = firstRun + 1 -- First run through midi event is obviously succesfully happening
            end
        elseif msg:find("dynamic crescendo") or msg:find("dynamic diminuendo") then
            -- Populate table
            table.insert(eventTable, {ppqpos = ppqpos, dynamic = lastDynamic, gradual=true})
            firstRun = firstRun + 1 -- First run through midi event is obviously succesfully happening
        end
    end
    
    -- Insert CC events using eventTable
    for _, eventInfo in ipairs(eventTable) do
        local ppqpos = eventInfo.ppqpos
        local dynamic = eventInfo.dynamic
        local gradual = eventInfo.gradual
        -- Insert CC1 event with the desired value
        reaper.MIDI_InsertCC(take, false, false, ppqpos, 0xB0, 0, 1, dynamic)
        -- Set the desired CC shape to bezier (only for crescendo and diminuendo)
        if gradual == true then
            local _, _, cccnt = reaper.MIDI_CountEvts(take)
            for i = 0, cccnt, 1 do
                local _, _, _, ccppqpos = reaper.MIDI_GetCC(take, i)
                if ccppqpos == ppqpos then
                    reaper.MIDI_SetCCShape(take, i, 5, 0)
                end
            end
        end
    end
end


-- Functions for moving CC1 and articulation events according to legato offset
-- moveDynamicEvt IS PROBABLY NOT NEEDED AS THE LOOSE TIMING ADDS TO REALISTIC FEEL (this function is also unfinished)
--[[function moveDynamicEvt(startppqpos, newppqpos)
    local _, _, cceventcount = reaper.MIDI_CountEvts(take)
    local ccEvtFound = false
    for i = cceventcount, 0, -1 do
        local _, _, _, ccppqpos, chanmsg, _, ccnum = reaper.MIDI_GetCC(take, i)
        if chanmsg == 0xB0 and ccnum = 1 and ccppqpos == startppqpos then -- Event is CC1 and it is located at the same position as the note, so we move it to new position
             reaper.MIDI_SetCC(take, i, NULL, NULL, newppqpos, NULL, NULL, NULL, NULL, NULL)
             ccEvtFound = true
        end
    end
    if ccEvtFound == false then -- CC1 event at the specified position was not found so we create a new one
        XYZ -- read the effective value at the old position and set this value to the new position (acquire also the shape?)
    end
end--]]
function moveArticulationEvt(startppqpos, newppqpos)
    local _, _, eventcount = reaper.MIDI_CountEvts(take)
    for i = eventcount, 0, -1 do
        local _, _, _, evtppqpos, chanmsg = reaper.MIDI_GetCC(take, i)
        if chanmsg == 0xC0 and evtppqpos == startppqpos then -- Event is program change and it is located at the same position as the note
             reaper.MIDI_SetCC(take, i, NULL, NULL, newppqpos, NULL, NULL, NULL, NULL, NULL)
        end
    end
end


-- Functions for retrieving main articulation types
function articulationOnNote(evtppqpos, ppqpos) -- If the program change position is the same as the note position - set this value
    if evtppqpos == ppqpos then
        return true
    else
        return false
    end
end
function getArticulationType(ppqpos)
    local _, _, cceventcount = reaper.MIDI_CountEvts(take)
    for i = cceventcount, 0, -1 do
        local _, _, _, evtppqpos, chanmsg, chan, pcvalue = reaper.MIDI_GetCC(take, i)
        local articulationonnote = false
        if chanmsg == 0xC0 and evtppqpos <= ppqpos then -- Event is program change and it iterates just before the note which called this (last program change)

            -- Iterate through REAticulate defined program change values for articulations
            for j = 1, #legatoslowvalues do
                if pcvalue == legatoslowvalues[j] then
                    articulationonnote = articulationOnNote(evtppqpos, ppqpos)
                    return "legatoslow", articulationonnote
                end
            end
            for k = 1, #legatofastvalues do
                if pcvalue == legatofastvalues[k] then
                    articulationonnote = articulationOnNote(evtppqpos, ppqpos)
                    return "legatofast", articulationonnote
                end
            end
            for l = 1, #shortvalues do
                if pcvalue == shortvalues[l] then
                    articulationonnote = articulationOnNote(evtppqpos, ppqpos)
                    return "short", articulationonnote
                end
            end
            for m = 1, #longvalues do
                if pcvalue == longvalues[m] then
                    articulationonnote = articulationOnNote(evtppqpos, ppqpos)
                    return "long", articulationonnote
                end
            end
        end
    end
end


-- Note table and creation function
local NoteTable = {}
function createNoteTable()
    local _, notecnt = reaper.MIDI_CountEvts(take)
    local lastnoteend = -1

    for i = 0, notecnt - 1, 1 do -- MIDI_CountEvts returns empty weird note with zero values at it's end, so it has to be subtracted by 1
        local _, _, _, startppqpos, endppqpos, _, pitch, vel = reaper.MIDI_GetNote(take, i)
        local passage = "MIDDLE" -- Valid values for 'passage' are: BEGIN - start of passage, MIDDLE - note in passage, END - end of passage, BEGIN-END - note is passage on it's own

        -- Set the articulation type and indicator whether program change event is present at this note position
        local articulationtype, articulationonnote = getArticulationType(startppqpos)

        -- Set passage starts/ends
        if startppqpos > lastnoteend then
            passage = "BEGIN"
            if i > 0 and NoteTable[i].passage ~= "BEGIN" then -- There is no note before first one ;) | Using 'i' value because it is just one number lower than table index (for starts at 0, while table at 1)
                NoteTable[i].passage = "END" -- Unless the last note is "alone" (passage on it's own) set it to END
            elseif i > 0 and NoteTable[i].passage == "BEGIN" then
                NoteTable[i].passage = "BEGIN-END" -- If the last note is "alone"
            end
        end
        if i == (notecnt - 1) then -- Set END for the last note in take
            passage = "END"
        end

        -- Input everything into the table
        table.insert(NoteTable, {id = i, startppqpos = startppqpos, endppqpos = endppqpos, pitch = pitch, vel = vel, articulationonnote = articulationonnote, articulationtype = articulationtype, passage = passage})

        -- Set note end ppq position and pitch for rebow detection
        lastnoteend = endppqpos
    end
end


-- Legato offset function
function setLegatoOffset(library_type, legato_type, id, startppqpos, endppqpos, vel, passage, articulationonnote)
    local bpm = reaper.TimeMap_GetDividedBpmAtTime(reaper.MIDI_GetProjTimeFromPPQPos(take, startppqpos)) --Retrieves exact bpm at the note's position
    local ticktime = 60000 / (bpm * ppq)
    local legatotimesarray = {}
    local legatotime = 0
    
    -- Get local array from pre-defined arrays with legato timings stated in the beginning of a script
    if library_type == "CSS" and legato_type == "slow" then
        legatotimesarray = css_slow
    elseif library_type == "CSS" and legato_type == "fast" then
        legatotimesarray = css_fast
    elseif library_type == "CSSSolo" and legato_type == "slow" then
        legatotimesarray = csssolo_slow
    elseif library_type == "CSSSolo" and legato_type == "fast" then
        legatotimesarray = css_fast
    elseif library_type == "CSW" and legato_type == "slow" then
        legatotimesarray = csw_slow
    elseif library_type == "CSW" and legato_type == "fast" then
        legatotimesarray = csw_fast
    elseif library_type == "CSBTrumpet" then
        legatotimesarray = csb_trumpet
    elseif library_type == "CSBOther" then
        legatotimesarray = csb_other
    end

    -- Decide which speed of legato is applied based on velocity
    if vel >= 0 and vel <= 64 then
        legatotime = legatotimesarray[1]
    elseif vel >= 65 and vel <= 100 then
        legatotime = legatotimesarray[2]
    elseif vel >= 101 and vel <= 127 then
        legatotime = legatotimesarray[3]
    end

    -- Count the ppqpos difference and apply to the note, also move the CC1 value and articulation change if present (only if its already in the passage, not at the beginning or isolated)
    local noteppqoffset = math.floor(legatotime / ticktime)
    local newppqpos = startppqpos - noteppqoffset
    if passage == "MIDDLE" or passage == "END" then
        reaper.MIDI_SetNote(take, id, NULL, NULL, newppqpos)
        --moveDynamicEvt(startppqpos, newppqpos) -- moveDynamicEvt IS PROBABLY NOT NEEDED AS THE LOOSE TIMING ADDS TO REALISTIC FEEL
        if articulationonnote == true then
            moveArticulationEvt(startppqpos, newppqpos)
        end
    end

    -- Set the passage with correct timing after performing legato correction
    setPassage(id, newppqpos, endppqpos, passage)
end


-- Rebow/retongue function (is called within setLegatoOffset function for legato and straight from processNoteTable function for long articulations like marcato etc.)
function setPassage(id, startppqpos, endppqpos, passage)
    local sustainppqoffset = 32 -- Needed to adjust to accomodate CC interpolation value in Reaper (might be adjusted)

    -- Set the CC64 values (sustain)
    if passage == "BEGIN" then
        reaper.MIDI_InsertCC(take, false, false, startppqpos, 0xB0, 0, 64, 0)
        reaper.MIDI_InsertCC(take, false, false, startppqpos + 32, 0xB0, 0, 64, 127)
    elseif passage == "END" then
        reaper.MIDI_InsertCC(take, false, false, endppqpos - 32, 0xB0, 0, 64, 127)
        reaper.MIDI_InsertCC(take, false, false, endppqpos, 0xB0, 0, 64, 0)
    end
end


-- Function to convert CC1 value to Velocity
function setShortVelocity(id, startppqpos)
    local _, _, cccnt = reaper.MIDI_CountEvts(take)
    local ccEventFound = false

    for i = 0, cccnt, 1 do
        _, _, _, ccppqpos, chanmsg, chan, ccnumber, ccval = reaper.MIDI_GetCC(take, i)      
        if chanmsg == 0xB0 and ccnumber == 1 then
            if ccppqpos == startppqpos then                    
                --DO CC ALTER CODE
                reaper.MIDI_SetNote(take, id, NULL, NULL, NULL, NULL, NULL, NULL, ccval)
                ccEventFound = true
            end
        end
    end
    if ccEventFound == false then
        --DO CC CREATION CODE
        local nTime = reaper.MIDI_GetProjTimeFromPPQPos(take, startppqpos)
        local _, ccValue = mu.MIDI_GetCCValueAtTime(take, 0xB0, 0, 1, nTime)
        ccValue = math.floor(ccValue)
        reaper.MIDI_SetNote(take, id, NULL, NULL, NULL, NULL, NULL, NULL, ccValue)
    end
end


function processNoteTable(library_type) -- This function reads through the NoteTable and decides an action for each Note
    for _, NoteInfo in ipairs(NoteTable) do
        local id = NoteInfo.id
        local startppqpos = NoteInfo.startppqpos
        local endppqpos = NoteInfo.endppqpos
        local pitch = NoteInfo.pitch
        local vel = NoteInfo.vel
        local articulationtype = NoteInfo.articulationtype
        local passage = NoteInfo.passage
        local articulationonnote = NoteInfo.articulationonnote

        if articulationtype == "legatoslow" then
            setLegatoOffset(library_type, "slow", id, startppqpos, endppqpos, vel, passage, articulationonnote)
        elseif articulationtype == "legatofast" then
            setLegatoOffset(library_type, "fast", id, startppqpos, endppqpos, vel, passage, articulationonnote)
        elseif articulationtype == "short" then
            setShortVelocity(id, startppqpos)
        elseif articulationtype == "long" then
            setPassage(id, startppqpos, endppqpos, passage)
        end
    end
end


--Button click functions
function cssButton() processActiveTake("CSS") end
function cssSoloButton() processActiveTake("CSSSolo") end
function cswButton() processActiveTake("CSW") end
function csbTrumpetButton() processActiveTake("CSBTrumpet") end
function csbOtherButton() processActiveTake("CSBOther") end
function processActiveTake(library_type) 
    convertDynamics()
    createNoteTable()

    if DEBUG == true then
        showNoteTable()
        reaper.ShowConsoleMsg("Library type: " .. library_type)
    end

    processNoteTable(library_type)

    window:close()
end


-- Function to write table contents to the console
function showNoteTable()
    local linenumber = 1
    for _, NoteInfo in ipairs(NoteTable) do
        local id = NoteInfo.id
        local startppqpos = NoteInfo.startppqpos
        local endppqpos = NoteInfo.endppqpos
        local pitch = NoteInfo.pitch
        local vel = NoteInfo.vel
        local articulationtype = NoteInfo.articulationtype
        local passage = NoteInfo.passage
        local articulationonnote = NoteInfo.articulationonnote

        reaper.ShowConsoleMsg(linenumber .. ") " .. "id: " .. tostring(id) .. " | ".. "startppqpos: " .. tostring(startppqpos) .. " | ".. "endppqpos: " .. tostring(endppqpos) .. " | ".. "pitch: " .. tostring(pitch) .. " | ".. "vel: " .. tostring(vel) .. " | ".. "articulationonnote: " .. tostring(articulationonnote) .. " | ".. "articulationtype: " .. tostring(articulationtype) .. " | ".. "passage: " .. tostring(passage) .. "\n")
        
        -- Console trims messages in means of FIFO, this will help to see the beginning
        --[[if linenumber > 100 then
            break
        end]]--

        linenumber = linenumber + 1

    end
end


function Main()
    take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
    item = reaper.GetMediaItemTake_Item(take)

    -- Count ppq item/take ticks per quarter note value for legato timings
    local position = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local offset = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
    local qn = reaper.TimeMap2_timeToQN(nil, position - offset)
    ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn + 1)
    
    if take then
        local check = takeCheck(check)
        if check == true then
    --GUI layout----------------------------------------------------------------
            GUI = require("gui.core")

            window = GUI.createWindow({
                name = "Musescore 4 - Cinematic Series instruments conversion tool",
                w = 480,
                h = 480,
            })

            layer = GUI.createLayer({
                name = "MainLayer"
            })
            layer:addElements( GUI.createElements(
                {
                name = "CSSbutton",
                type = "Button",
                x = 156,
                y = 32,
                w = 176,
                h = 48,
                fillColor = {0.07, 0.07, 0.196},
                textColor = {0.8, 0.8, 0.8},
                font = {"arial", 18},
                caption = "Strings (CSS)",
                func = cssButton
                },
                {
                name = "CSSSOLObutton",
                type = "Button",
                x = 156,
                y = 112,
                w = 176,
                h = 48,
                fillColor = {0, 0.13, 0.18},
                textColor = {0.8, 0.8, 0.8},
                font = {"arial", 18},
                caption = "Solo Strings (CSSS)",
                func = cssSoloButton
                },
                {
                name = "CSWbutton",
                type = "Button",
                x = 156,
                y = 192,
                w = 176,
                h = 48,
                fillColor = {0.024, 0.145, 0.075},
                textColor = {0.8, 0.8, 0.8},
                font = {"arial", 18},
                caption = "Woodwinds (CSW)",
                func = cswButton
                },
                {
                name = "CSBTRUMPETbutton",
                type = "Button",
                x = 156,
                y = 272,
                w = 176,
                h = 48,
                fillColor = {0.28, 0.098, 0.02},
                textColor = {0.8, 0.8, 0.8},
                font = {"arial", 18},
                caption = "Brass trumpet (CSB)",
                func = csbTrumpetButton
                },
                {
                name = "CSSOTHERbutton",
                type = "Button",
                x = 156,
                y = 352,
                w = 176,
                h = 48,
                fillColor = {0.28, 0.098, 0.02},
                textColor = {0.8, 0.8, 0.8},
                font = {"arial", 18},
                caption = "Brass other (CSB)",
                func = csbOtherButton
                }
            ))

            window:addLayers(layer)
            
            window:open()
            GUI.Main()
    --End-----------------------------------------------------------------------
            reaper.UpdateArrange()
        end
    else 
        takeError()
    end
end

Main()