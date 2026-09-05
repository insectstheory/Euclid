-- Euclid
-- 4-track euclidean sequencer
--
-- K2 tap  : next track
-- K2 hold : mute/unmute track
-- K3      : randomize pulses + offset
-- ENC1    : steps (1-32)
-- ENC2    : pulses
-- ENC3    : rotation offset
-- PARAMS  : root, scale, note T1, harmony degree T2-T4,
--           velocity, midi ch per track, bpm, clock div

--─────────────────────────────────────────
--scale definitions (intervalli in semitoni dalla root)
--─────────────────────────────────────────
local SCALES = {
  { name = "chromatic",         intervals = {0,1,2,3,4,5,6,7,8,9,10,11} },
  { name = "pentatonic maj",    intervals = {0,2,4,7,9} },
  { name = "major",             intervals = {0,2,4,5,7,9,11} },
  { name = "minor",             intervals = {0,2,3,5,7,8,10} },
  { name = "phrygian dom",      intervals = {0,1,4,5,7,8,10} },
  { name = "lydian",            intervals = {0,2,4,6,7,9,11} },
}

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

--degree offset (quante note della scala saltare)
local HARMONY_DEGREES = {
  { name = "unison",   degree = 0 },
  { name = "third",    degree = 2 },
  { name = "fifth",    degree = 4 },
  { name = "seventh",  degree = 6 },
}

--─────────────────────────────────────────
--harmony helpers
--─────────────────────────────────────────

--dato un numero midi, trova il grado più vicino nella scala
--restituisce l'indice (1-based) nell'array degli intervalli della scala
local function midi_to_scale_degree(midi_note, root_midi, scale_intervals)
  local len = #scale_intervals
  --normalizza rispetto alla root
  local semis = midi_note - root_midi
  --ottava e posizione cromatica
  local octave = math.floor(semis / 12)
  local chroma = semis % 12
  --cerca l'intervallo più vicino
  local best_idx = 1
  local best_dist = 999
  for i, iv in ipairs(scale_intervals) do
    local dist = math.abs(chroma - iv)
    if dist < best_dist then
      best_dist = dist
      best_idx = i
    end
  end
  --grado assoluto (con ottava)
  return best_idx + octave * len
end

--dato un grado assoluto (può essere < 1 o > #scale), restituisce il midi
local function scale_degree_to_midi(degree, root_midi, scale_intervals)
  local len = #scale_intervals
  --wrap degree in [1, len] con offset ottava
  local octave = math.floor((degree - 1) / len)
  local idx    = ((degree - 1) % len) + 1
  return root_midi + octave * 12 + scale_intervals[idx]
end

--applica un offset di degree (diatonico) a una nota midi
local function harmonize(midi_note, degree_offset, root_midi, scale_intervals)
  local base_degree = midi_to_scale_degree(midi_note, root_midi, scale_intervals)
  local new_degree  = base_degree + degree_offset
  return scale_degree_to_midi(new_degree, root_midi, scale_intervals)
end

--─────────────────────────────────────────
--euclidean algorithm (Bjorklund)
--─────────────────────────────────────────
local function euclid(steps, pulses, offset)
  if steps == 0 then return {} end
  pulses = math.min(pulses, steps)
  local pattern = {}
  local bucket  = 0
  for i = 1, steps do
    bucket = bucket + pulses
    if bucket >= steps then
      bucket = bucket - steps
      table.insert(pattern, 1)
    else
      table.insert(pattern, 0)
    end
  end
  offset = offset % steps
  local rotated = {}
  for i = 1, steps do
    rotated[i] = pattern[((i - 1 + offset) % steps) + 1]
  end
  return rotated
end

--─────────────────────────────────────────
--state
--─────────────────────────────────────────
local NUM_TRACKS = 4
local MAX_STEPS  = 32
local HOLD_TIME  = 0.4

local SCRIPT_NAME  = "EUCLID"
local splash_done  = false

--sensibilità encoder: quanti "tick" grezzi servono per un cambio di 1 unità.
--più alto = movimento più fine/graduale, meno "a scatti" quando si gira veloce.
local ENC_SENSITIVITY = 4
local enc_accum = { [1]=0, [2]=0, [3]=0 }

local tracks    = {}
local positions = {}
local patterns  = {}
local active_track = 1

local k2_down_time  = nil
local k2_hold_fired = false
local k2_hold_clock = nil

local midi_out

local function get_root_midi()
  --root: 0-11 (C=0..B=11), octava 4 → midi 60 = C4
  local root_note = params:get("root_note") - 1   --params 1-based → 0-based
  local root_oct  = params:get("root_oct")         --es. 4 → ottava 4 (C4=60)
  return (root_oct + 1) * 12 + root_note
end

local function get_scale_intervals()
  local idx = params:get("scale")
  return SCALES[idx].intervals
end

local function build_pattern(t)
  patterns[t] = euclid(tracks[t].steps, tracks[t].pulses, tracks[t].offset)
end

local function init_tracks()
  local defaults = {
    { steps=16, pulses=4, offset=0, note=60, vel=100, ch=1, on=true },
    { steps=16, pulses=3, offset=2, note=60, vel=100, ch=1, on=true },
    { steps=16, pulses=7, offset=0, note=60, vel=80,  ch=1, on=true },
    { steps=16, pulses=2, offset=4, note=60, vel=70,  ch=1, on=true },
  }
  for t = 1, NUM_TRACKS do
    tracks[t]    = defaults[t]
    positions[t] = 1
    build_pattern(t)
  end
end

--─────────────────────────────────────────
--nota effettiva per la traccia t al trigger
--T1 : note fissa da params
--T2-T4 : harmonize rispetto a T1
--─────────────────────────────────────────
local function get_midi_note(t)
  local base_note = params:get("note_1")   --nota T1 sempre come base armonica

  if t == 1 then
    return base_note
  else
    local root_midi       = get_root_midi()
    local scale_intervals = get_scale_intervals()
    local harm_idx    = params:get("harmony_" .. t)
    local deg_offset  = HARMONY_DEGREES[harm_idx].degree
    return harmonize(base_note, deg_offset, root_midi, scale_intervals)
  end
end

--─────────────────────────────────────────
--circular display
--─────────────────────────────────────────
local CX     = 56
local CY     = 32
local RADII  = { 28, 21, 14, 7 }
local TWO_PI = math.pi * 2

local function draw_ring(t)
  local tr  = tracks[t]
  local pat = patterns[t]
  local pos = positions[t]
  local r   = RADII[t]
  local is_active = (t == active_track)

  --outline: punti discreti invece di circle/stroke
  local outline_steps = r * 8   --densita' proporzionale al raggio
  screen.level(tr.on and 3 or 1)
  for i = 0, outline_steps - 1 do
    local angle = TWO_PI * i / outline_steps
    local x = math.floor(CX + r * math.cos(angle) + 0.5)
    local y = math.floor(CY + r * math.sin(angle) + 0.5)
    screen.pixel(x, y)
    screen.fill()
  end

  for i = 1, tr.steps do
    local angle = TWO_PI * (i - 1) / tr.steps - math.pi / 2
    local x = math.floor(CX + r * math.cos(angle) + 0.5)
    local y = math.floor(CY + r * math.sin(angle) + 0.5)
    local is_pulse   = pat[i] == 1
    local is_current = (i == pos)

    if is_current then
      --posizione corrente: 3x3 filled rect
      screen.level(15)
      screen.rect(x - 1, y - 1, 3, 3)
      screen.fill()
    elseif is_pulse then
      --pulse: 2x2 pixel
      screen.level(tr.on and (is_active and 12 or 7) or 2)
      screen.rect(x, y, 2, 2)
      screen.fill()
    else
      --rest: pixel singolo
      screen.level(tr.on and (is_active and 3 or 2) or 1)
      screen.pixel(x, y)
      screen.fill()
    end
  end
end

local function redraw()
  screen.clear()
  screen.aa(0)

  for t = 1, NUM_TRACKS do
    draw_ring(t)
  end

  --numero traccia attiva al centro
  screen.level(15)
  screen.move(CX, CY + 3)
  screen.text_center(active_track)

  --info traccia attiva (destra)
  local tr = tracks[active_track]
  screen.level(tr.on and 10 or 4)
  screen.move(96, 10)
  screen.text("T" .. active_track .. (tr.on and "" or " x"))

  screen.level(5)
  screen.move(96, 19)
  screen.text("S " .. tr.steps)
  screen.move(96, 27)
  screen.text("P " .. tr.pulses)
  screen.move(96, 35)
  screen.text("O " .. tr.offset)

  --root + scala (in basso a destra)
  local root_idx = params:get("root_note")
  local scale_idx = params:get("scale")
  screen.level(4)
  screen.move(96, 44)
  screen.text(NOTE_NAMES[root_idx])
  screen.move(96, 52)
  --scala abbreviata (max 6 char)
  local sname = SCALES[scale_idx].name
  screen.text(string.sub(sname, 1, 6))

  --harm degree (solo T2-T4)
  if active_track > 1 then
    local hidx = params:get("harmony_" .. active_track)
    screen.level(7)
    screen.move(96, 60)
    screen.text(HARMONY_DEGREES[hidx].name)
  end

  --indicatori traccia (basso sinistra)
  for t = 1, NUM_TRACKS do
    local x = 2 + (t - 1) * 6
    if t == active_track then
      screen.level(15)
      screen.rect(x, 61, 4, 3)
      screen.fill()
    else
      screen.level(tracks[t].on and 4 or 1)
      screen.rect(x, 61, 4, 3)
      screen.stroke()
    end
  end

  --feedback visivo hold in corso
  if k2_down_time ~= nil and not k2_hold_fired then
    local elapsed  = util.time() - k2_down_time
    local progress = math.min(elapsed / HOLD_TIME, 1)
    screen.level(6)
    screen.rect(0, 0, math.floor(progress * 128), 1)
    screen.fill()
  end

  screen.update()
end

--─────────────────────────────────────────
--splash screen d'avvio
--anelli che si espandono dal centro fino al raggio finale,
--poi appare il nome dello script
--─────────────────────────────────────────
local function draw_splash()
  local frames = 200

  --centro "vero" dello schermo, usato solo per lo splash
  --(diverso da CX/CY, che sono spostati per lasciare spazio al pannello laterale della UI principale)
  local splash_cx = 64
  local splash_cy = 32

  for f = 1, frames do
    screen.clear()
    screen.aa(0)
    local prog = f / frames   --0 → 1

    for i, r in ipairs(RADII) do
      local rr    = r * prog
      local dots  = math.max(8, math.floor(rr * 4))
      screen.level(3 + i * 2)
      for d = 0, dots - 1 do
        local angle = TWO_PI * d / dots
        local x = math.floor(splash_cx + rr * math.cos(angle) + 0.5)
        local y = math.floor(splash_cy + rr * math.sin(angle) + 0.5)
        screen.pixel(x, y)
        screen.fill()
      end
    end

    --il nome compare a metà animazione, centrato esattamente sullo stesso punto degli anelli
    if f > frames * 0.5 then
      screen.level(15)
      screen.move(splash_cx, splash_cy + 3)   --+3 per compensare l'altezza del font (baseline)
      screen.text_center(SCRIPT_NAME)
    end

    screen.update()
    clock.sleep(1 / 30)
  end

  --breve pausa a schermo pieno prima di passare alla UI normale
  clock.sleep(0.4)
end

--─────────────────────────────────────────
--norns callbacks
--─────────────────────────────────────────
function init()
  init_tracks()
  midi_out = midi.connect(1)

  --── globali ──────────────────────────────
  params:add_separator("Scale / Root")

  params:add{
    type="option", id="root_note", name="root note",
    options=NOTE_NAMES, default=1,   --C
  }
  params:add{
    type="number", id="root_oct", name="root octave",
    min=0, max=8, default=4,
  }
  params:add{
    type="option", id="scale", name="scale",
    options=(function()
      local t = {}
      for _, s in ipairs(SCALES) do table.insert(t, s.name) end
      return t
    end)(),
    default=3,   --major
  }

--  ── per traccia ──────────────────────────
  for t = 1, NUM_TRACKS do
    params:add_separator("Track " .. t)

    if t == 1 then
      --T1: nota fissa (come prima)
      params:add{
        type="number", id="note_1", name="T1 note (midi)",
        min=0, max=127, default=60,
        action=function(v) tracks[1].note = v end
      }
    else
      --T2-T4: grado armonico
      params:add{
        type="option", id="harmony_"..t, name="T"..t.." harmony",
        options=(function()
          local o = {}
          for _, h in ipairs(HARMONY_DEGREES) do table.insert(o, h.name) end
          return o
        end)(),
        default=t,   --T2=third(2), T3=fifth(3), T4=seventh(4)
      }
    end

    params:add{
      type="number", id="vel_"..t, name="T"..t.." velocity",
      min=1, max=127, default=tracks[t].vel,
      action=function(v) tracks[t].vel = v end
    }
    params:add{
      type="number", id="ch_"..t, name="T"..t.." midi ch",
      min=1, max=16, default=tracks[t].ch,
      action=function(v) tracks[t].ch = v end
    }
  end

  params:add_separator("Clock")
  params:add{
    type="number", id="bpm", name="bpm",
    min=20, max=300, default=math.floor(clock.get_tempo()),
    action=function(v) params:set("clock_tempo", v) end
  }
  params:add{
    type="number", id="clock_div", name="clock div",
    min=1, max=16, default=4,
  }

  params:bang()

  --clock musicale: solo MIDI, niente display
  clock.run(function()
    while true do
      clock.sync(1 / params:get("clock_div"))

      --durata di uno step, usata per scalare il gate
      local step_sec = clock.get_beat_sec() / params:get("clock_div")

      for t = 1, NUM_TRACKS do
        local tr  = tracks[t]
        local pat = patterns[t]
        local p   = positions[t]

        if tr.on and pat[p] == 1 then
          local midi_note = get_midi_note(t)
          midi_note = math.max(0, math.min(127, midi_note))
          local vel = params:get("vel_" .. t)
          local ch  = params:get("ch_"  .. t)

          --salva l'ultima nota realmente inviata, serve a cleanup()
          tracks[t].note = midi_note

          midi_out:note_on(midi_note, vel, ch)

          local note_copy = midi_note
          local ch_copy   = ch
          clock.run(function()
            --gate proporzionale alla durata dello step corrente,
            --cosi' non dipende piu' da clock_div
            clock.sleep(step_sec * 0.5)
            midi_out:note_off(note_copy, 0, ch_copy)
          end)
        end

        positions[t] = (p % tr.steps) + 1
      end
    end
  end)

  --clock display separato: ~15 fps, non blocca il MIDI
  clock.run(function()
    while true do
      clock.sleep(1 / 15)
      if splash_done and not norns.menu.status() then
        redraw()
      end
    end
  end)

  --splash d'avvio: gira una volta sola, poi lascia il posto alla UI normale
  clock.run(function()
    draw_splash()
    splash_done = true
  end)
end

--─────────────────────────────────────────
--encoder: movimento fine + niente wrap-around
--
--ENC_SENSITIVITY controlla quanti "tick" grezzi dell'encoder
--servono per ottenere un cambio di 1 unità sul parametro.
--Alzalo (es. 6-8) per rendere il giro ancora più fine/morbido,
--abbassalo (es. 2) per renderlo più reattivo.
--
--tutti e tre i parametri (steps, pulses, offset) sono ora
--clampati con util.clamp: arrivati al minimo o al massimo
--l'encoder si "ferma" li', non ricomincia dall'altro capo.
--─────────────────────────────────────────
function enc(n, d)
  enc_accum[n] = enc_accum[n] + d

  local step = 0
  if enc_accum[n] >= ENC_SENSITIVITY then
    step = 1
    enc_accum[n] = 0
  elseif enc_accum[n] <= -ENC_SENSITIVITY then
    step = -1
    enc_accum[n] = 0
  else
    --non abbastanza movimento accumulato: ignora questo tick
    return
  end

  local tr = tracks[active_track]
  if n == 1 then
    tr.steps  = util.clamp(tr.steps + step, 1, MAX_STEPS)
    tr.pulses = math.min(tr.pulses, tr.steps)
    tr.offset = math.min(tr.offset, tr.steps - 1)
  elseif n == 2 then
    tr.pulses = util.clamp(tr.pulses + step, 0, tr.steps)
  elseif n == 3 then
    tr.offset = util.clamp(tr.offset + step, 0, tr.steps - 1)
  end
  build_pattern(active_track)
  redraw()
end

function key(n, z)
  if n == 1 then return end  --K1 riservato al sistema (menu / home)
  if n == 2 then
    if z == 1 then
      k2_down_time  = util.time()
      k2_hold_fired = false

      if k2_hold_clock then
        clock.cancel(k2_hold_clock)
      end

      k2_hold_clock = clock.run(function()
        clock.sleep(HOLD_TIME)
        k2_hold_fired = true
        tracks[active_track].on = not tracks[active_track].on
        redraw()
      end)

    else
      if k2_hold_clock then
        clock.cancel(k2_hold_clock)
        k2_hold_clock = nil
      end

      if not k2_hold_fired then
        active_track = (active_track % NUM_TRACKS) + 1
      end

      k2_down_time  = nil
      k2_hold_fired = false
      redraw()
    end

  elseif n == 3 and z == 1 then
    local tr = tracks[active_track]
    tr.pulses = math.random(0, tr.steps)
    tr.offset = math.random(0, tr.steps - 1)
    build_pattern(active_track)
    redraw()
  end
end

function cleanup()
  for t = 1, NUM_TRACKS do
    local tr = tracks[t]
    local ch = params:get("ch_" .. t)
    midi_out:note_off(tr.note, 0, ch)
  end
end
