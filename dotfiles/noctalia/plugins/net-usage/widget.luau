--!nonstrict
-- Network Usage -- [[widget]] entry (bar).
--
-- Collapsed: just the up/down glyph. Hovered: slides open, in the bar, with
-- the download and upload rates of the connected physical interfaces, the
-- busiest first, at most max_interfaces of them; the rest are added up into
-- one "+N" entry:
--   ⇅  enp5s0 ↓45M ↑2.1M │ wlan0 ↓1.2M ↑233K │ +2 ↓12K ↑3K
-- Which interfaces show, and in what order, is fixed when the hover starts,
-- so nothing jumps around while it is open; only the rates update.
-- The tooltip lists every physical interface, connected or not.
--
-- Rates come from Noctalia's own system monitor (systemStats().net), so this
-- samples nothing itself.

local SYS = "/sys/class/net/"
local ZERO = { rxBytesPerSec = 0, txBytesPerSec = 0 }

local hovered = false
local order = nil -- interface names, frozen for the current hover

local function readTrim(path)
  local s = noctalia.readFile(path)
  return s and (s:gsub("%s+$", "")) or nil
end

-- Physical interfaces (backed by a device), sorted by name.
local function physical()
  local out = {}
  for _, name in ipairs(noctalia.listDir(SYS) or {}) do
    if noctalia.fileExists(SYS .. name .. "/device") then
      table.insert(out, name)
    end
  end
  table.sort(out)
  return out
end

local function isUp(name)
  return readTrim(SYS .. name .. "/operstate") == "up"
end

local function interfaces()
  local stats = noctalia.systemStats()
  return (stats and stats.net and stats.net.interfaces) or {}
end

local function traffic(ifaces, name)
  local t = ifaces[name] or ZERO
  return t.rxBytesPerSec + t.txBytesPerSec
end

-- Connected interfaces, busiest first (name breaks ties).
local function connectedByTraffic(ifaces)
  local out = {}
  for _, name in ipairs(physical()) do
    if isUp(name) then
      table.insert(out, name)
    end
  end
  table.sort(out, function(a, b)
    local ta, tb = traffic(ifaces, a), traffic(ifaces, b)
    if ta ~= tb then
      return ta > tb
    end
    return a < b
  end)
  return out
end

-- Compact decimal units, like Noctalia's network_speed_compact.
local function rate(bytes)
  for _, u in ipairs({ { 1e9, "G" }, { 1e6, "M" }, { 1e3, "K" } }) do
    if bytes >= u[1] then
      local v = bytes / u[1]
      return string.format(v < 100 and "%.1f%s" or "%d%s", v, u[2])
    end
  end
  return string.format("%dB", math.floor(bytes))
end

local function entry(children, label, rx, tx)
  if #children > 1 then
    table.insert(children, ui.label({ text = "│", color = "on_surface_variant" }))
  end
  table.insert(children, ui.label({ text = label, color = "on_surface_variant" }))
  table.insert(children, ui.label({ text = "↓" .. rate(rx) }))
  table.insert(children, ui.label({ text = "↑" .. rate(tx) }))
end

local function setTooltip(ifaces)
  local rows = {}
  for _, name in ipairs(physical()) do
    local value = "offline"
    if isUp(name) then
      local t = ifaces[name] or ZERO
      -- Monospace column: pad the numbers so they right-align.
      value = string.format("↓%7s  ↑%7s", rate(t.rxBytesPerSec), rate(t.txBytesPerSec))
    end
    table.insert(rows, { key = name, value = value })
  end
  barWidget.setTooltip(#rows > 0 and rows or nil)
end

local function render()
  local ifaces = interfaces()
  local children = { ui.glyph({ name = "arrows-down-up" }) }

  if hovered then
    order = order or connectedByTraffic(ifaces)
    local max = noctalia.getConfig("max_interfaces") or 3
    local restN, restRx, restTx = 0, 0, 0
    for i, name in ipairs(order) do
      local t = ifaces[name] or ZERO
      if i <= max then
        entry(children, name, t.rxBytesPerSec, t.txBytesPerSec)
      else
        restN += 1
        restRx += t.rxBytesPerSec
        restTx += t.txBytesPerSec
      end
    end
    if restN > 0 then
      entry(children, "+" .. restN, restRx, restTx)
    end
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, children))
  setTooltip(ifaces)
end

-- Called by the host on pointer enter/leave over the whole widget. (An
-- onHover on the ui tree would make its own hover target and hide the
-- tooltip, which lives on the widget.)
function onHover(state)
  local now = state == true or state == "true"
  if now ~= hovered then
    hovered = now
    order = nil -- picked again on the next hover
    render()
  end
end

function update()
  render()
end

noctalia.setUpdateInterval(2000)
render()
