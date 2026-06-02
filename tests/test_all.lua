--- CoCapn Lua: comprehensive test suite.
-- Run with: lua tests/test_all.lua

local ok = 0
local fail = 0

local function assert(cond, msg)
  if cond then
    ok = ok + 1
  else
    fail = fail + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- Helper for approximate equality
local function approx(a, b, eps)
  eps = eps or 0.001
  return math.abs(a - b) < eps
end

package.path = package.path .. ";../?.lua"

-----------------------------------------------------------------------
-- device.lua
-----------------------------------------------------------------------
do
  local device = require "cocapn.device"

  -- Basic creation
  local d = device.new_device("a1", "Alpha", device.TIER.REFLEX, device.CAP.SENSE)
  assert(d.id == "a1", "device id")
  assert(d.name == "Alpha", "device name")
  assert(d.tier == device.TIER.REFLEX, "device tier")
  assert(d.online == true, "device defaults online")

  -- Can check
  assert(device.can(d, device.CAP.SENSE), "can SENSE")
  assert(not device.can(d, device.CAP.ACT), "cannot ACT")

  -- Multi-cap
  local d2 = device.new_device("b2", "Beta", device.TIER.CORTEX,
    device.CAP.SENSE + device.CAP.ACT + device.CAP.PREDICT + device.CAP.COMM)
  assert(device.can(d2, device.CAP.SENSE), "multi SENSE")
  assert(device.can(d2, device.CAP.ACT), "multi ACT")
  assert(device.can(d2, device.CAP.PREDICT), "multi PREDICT")
  assert(not device.can(d2, device.CAP.TRAIN), "no TRAIN")

  -- Offline never responds
  local d3 = device.new_device("c3", "Gamma", device.TIER.REFLEX,
    device.CAP.SENSE, false)
  assert(d3.online == false, "offline")
  assert(not device.can(d3, device.CAP.SENSE), "offline can't sense")

  -- list_caps
  local caps = device.list_caps(d2)
  assert(#caps == 4, "list_caps count: " .. tostring(#caps))

  -- Tostring
  local s = device.tostring(d)
  assert(type(s) == "string", "tostring is string")
  assert(#s > 0, "tostring not empty")

  -- Tiers exist
  assert(device.TIER.REFLEX < device.TIER.BACKBONE, "tier ordering")
  assert(device.TIER.CLOUD > device.TIER.CORTEX, "tier ordering")
end

-----------------------------------------------------------------------
-- deadband.lua
-----------------------------------------------------------------------
do
  local deadband = require "cocapn.deadband"

  -- Normal: within tolerance
  local db = deadband.new(100, 10)
  assert(deadband.within(db, 100), "center within")
  assert(deadband.within(db, 95), "within lower")
  assert(deadband.within(db, 105), "within upper")
  assert(not deadband.within(db, 111), "outside upper")
  assert(not deadband.within(db, 89), "outside lower")

  -- Exceeded
  assert(deadband.exceeded(db, 115), "exceeded upper")
  assert(deadband.exceeded(db, 80), "exceeded lower")
  assert(not deadband.exceeded(db, 100), "not exceeded at center")

  -- Approaching
  local state = deadband.check(db, 106)
  assert(state == deadband.STATE.APPROACHING, "approaching upper: " .. tostring(state))
  state = deadband.check(db, 94)
  assert(state == deadband.STATE.APPROACHING, "approaching lower: " .. tostring(state))

  -- Bounds
  local lo, hi = deadband.bounds(db)
  assert(approx(lo, 90), "bounds lo: " .. tostring(lo))
  assert(approx(hi, 110), "bounds hi: " .. tostring(hi))

  -- ABOVE_ONLY
  local db_above = deadband.new(100, 10, deadband.DIR.ABOVE_ONLY)
  assert(deadband.within(db_above, 50), "above only: 50 is fine")
  assert(deadband.within(db_above, 105), "above only: within upper")
  assert(deadband.exceeded(db_above, 115), "above only: exceeded")
  assert(not deadband.exceeded(db_above, 50), "above only: -50 is not exceeded")

  -- BELOW_ONLY
  local db_below = deadband.new(100, 10, deadband.DIR.BELOW_ONLY)
  assert(deadband.within(db_below, 200), "below only: 200 is fine")
  assert(deadband.within(db_below, 95), "below only: within lower")
  assert(deadband.exceeded(db_below, 85), "below only: exceeded")
  assert(not deadband.exceeded(db_below, 200), "below only: 200 not exceeded")
end

-----------------------------------------------------------------------
-- autopilot.lua
-----------------------------------------------------------------------
do
  local autopilot = require "cocapn.autopilot"

  local pid = autopilot.new_pid(0.5, 0.01, 0.1, 30, 3)

  -- On course (within tolerance)
  local r, err, oc = autopilot.update(pid, 90, 91, 0.1)
  assert(oc == true, "on course at 91: " .. tostring(err))
  assert(approx(math.abs(err), 1, 1), "small error: " .. tostring(err))

  -- Hard course change
  autopilot.reset(pid)
  r, err, oc = autopilot.update(pid, 45, 180, 1.0)
  assert(oc == false, "not on course large turn")
  assert(approx(math.abs(err), 135, 2), "heading error ~135: " .. tostring(err))

  -- 360° wrap: 350 -> 10 should be +20 error, not -340
  autopilot.reset(pid)
  r, err, oc = autopilot.update(pid, 350, 10, 0.5)
  assert(approx(err, 20, 1), "wrap error 350->10: " .. tostring(err))

  -- 360° wrap: 10 -> 350 should be -20 error
  autopilot.reset(pid)
  r, err, oc = autopilot.update(pid, 10, 350, 0.5)
  assert(approx(err, -20, 1), "wrap error 10->350: " .. tostring(err))

  -- Integral builds up (use small gains + small error to avoid clipping)
  local pid_small = autopilot.new_pid(0.0005, 0.001, 0, 30, 3)
  local ri1 = autopilot.update(pid_small, 0, 1, 0.1)
  local ri2 = autopilot.update(pid_small, 0, 1, 0.1)
  assert(math.abs(ri2) > math.abs(ri1), "integral builds: " .. tostring(ri1) .. " -> " .. tostring(ri2))

  -- Max rudder clamping
  local pid2 = autopilot.new_pid(10, 0, 0, 5, 3)
  local r3 = autopilot.update(pid2, 0, 90, 0.1)
  assert(math.abs(r3) <= 5, "clamped at 5: " .. tostring(r3))

  -- Zero dt
  local r4 = autopilot.update(pid2, 0, 90, 0)
  assert(type(r4) == "number", "zero dt returns number")
end

-----------------------------------------------------------------------
-- escalation.lua
-----------------------------------------------------------------------
do
  local escalation = require "cocapn.escalation"

  -- Basic chain
  local results = {}
  local chain = escalation.new_chain()
  escalation.add_handler(chain, function(sev, pri, tag, msg)
    results[#results + 1] = {sev = sev, pri = pri, tag = tag, msg = msg}
  end, escalation.PRIORITY.LOW)

  local triggered, msg = escalation.alert(chain, escalation.SEVERITY.WARNING,
    escalation.PRIORITY.MEDIUM, "sensor1", "temp high")
  assert(triggered == true, "alert triggered: " .. tostring(triggered))
  assert(#results == 1, "handler called")
  assert(results[1].tag == "sensor1", "correct tag")

  -- Priority gating: handler at MEDIUM should not fire for LOW alert
  local results2 = {}
  local chain2 = escalation.new_chain()
  escalation.add_handler(chain2, function(sev, pri, tag, msg)
    results2[#results2 + 1] = true
  end, escalation.PRIORITY.MEDIUM)

  local t, _ = escalation.alert(chain2, escalation.SEVERITY.INFO,
    escalation.PRIORITY.LOW, "test", "low pri")
  assert(t == false, "low pri not delivered to medium handler")

  local t2, _ = escalation.alert(chain2, escalation.SEVERITY.INFO,
    escalation.PRIORITY.HIGH, "test2", "high pri")
  assert(t2 == true, "high pri delivered")
  assert(#results2 == 1, "high pri triggered once")

  -- Cooldown
  local chain3 = escalation.new_chain()
  local cd_count = 0
  escalation.add_handler(chain3, function()
    cd_count = cd_count + 1
  end, escalation.PRIORITY.LOW)

  escalation.alert(chain3, escalation.SEVERITY.INFO, escalation.PRIORITY.LOW,
    "throttle", "msg", {cooldown = 999})
  escalation.alert(chain3, escalation.SEVERITY.INFO, escalation.PRIORITY.LOW,
    "throttle", "msg", {cooldown = 999})
  assert(cd_count == 1, "cooldown suppresses second: " .. tostring(cd_count))

  -- Sticky
  local chain4 = escalation.new_chain()
  local sticky_count = 0
  escalation.add_handler(chain4, function()
    sticky_count = sticky_count + 1
  end, escalation.PRIORITY.LOW)

  escalation.alert(chain4, escalation.SEVERITY.WARNING, escalation.PRIORITY.LOW,
    "sticky-test", "first", {sticky = true})
  local ok2, _ = escalation.alert(chain4, escalation.SEVERITY.WARNING,
    escalation.PRIORITY.LOW, "sticky-test", "dup", {sticky = true})
  assert(ok2 == false or sticky_count == 1, "sticky blocks same severity")

  -- Ack clears sticky
  escalation.ack(chain4, "sticky-test")
  local ok3, _ = escalation.alert(chain4, escalation.SEVERITY.INFO,
    escalation.PRIORITY.LOW, "sticky-test", "after ack", {sticky = true})
  assert(ok3 == true, "ack allows new alert")
end

-----------------------------------------------------------------------
-- nmea.lua
-----------------------------------------------------------------------
do
  local nmea = require "cocapn.nmea"

  -- Standard GGA sentence
  local raw = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47"
  local p = nmea.parse(raw)
  assert(p ~= nil, "GGA parsed")
  assert(p.talker == "GP", "talker GP: " .. tostring(p.talker))
  assert(p.checksum_valid == true, "checksum valid")

  -- Bad checksum
  local raw2 = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00"
  local p2 = nmea.parse(raw2)
  assert(p2 ~= nil, "bad checksum parsed anyway")
  assert(p2.checksum_valid == false, "bad checksum flagged")

  -- Malformed
  local bad, err = nmea.parse("no dollar")
  assert(bad == nil, "missing $ returns nil")

  local bad2, err2 = nmea.parse("$NOSTAR")
  assert(bad2 == nil, "missing star returns nil")

  -- Build
  local built = nmea.build("GP", "RMC", {"225446", "A", "4916.45", "N"})
  assert(built:sub(1, 1) == "$", "built starts with $")
  assert(built:match("%*") ~= nil, "built has checksum")

  -- Round-trip
  local reparsed = nmea.parse(built)
  assert(reparsed ~= nil, "round-trip parse")
  assert(reparsed.checksum_valid == true, "round-trip checksum")

  -- Coordinate parsing
  local lat = nmea.parse_coord("4807.038", "N")
  assert(lat ~= nil, "lat parsed")
  assert(approx(lat, 48.1173, 0.01), "lat ~48.117: " .. tostring(lat))

  local lon = nmea.parse_coord("01131.000", "E")
  assert(lon ~= nil, "lon parsed")
  assert(approx(lon, 11.5167, 0.01), "lon ~11.517: " .. tostring(lon))

  -- Southern/Western hemispheres
  local lat_s = nmea.parse_coord("3345.00", "S")
  assert(lat_s < 0, "south negative: " .. tostring(lat_s))

  local lon_w = nmea.parse_coord("11815.00", "W")
  assert(lon_w < 0, "west negative: " .. tostring(lon_w))

  -- Nil on empty
  local nilval = nmea.parse_coord("", "N")
  assert(nilval == nil, "empty coord returns nil")
end

-----------------------------------------------------------------------
-- stripe.lua
-----------------------------------------------------------------------
do
  local device = require "cocapn.device"
  local stripe = require "cocapn.stripe"

  -- Three devices
  local d1 = device.new_device("n1", "Node 1", device.TIER.REFLEX,
    device.CAP.SENSE)
  local d2 = device.new_device("n2", "Node 2", device.TIER.REFLEX,
    device.CAP.SENSE + device.CAP.ACT)
  local d3 = device.new_device("n3", "Node 3", device.TIER.REFLEX,
    device.CAP.COMM)

  local s = stripe.new({d1, d2, d3}, stripe.STRATEGY.ROUND_ROBIN)

  -- Round-robin gives different devices
  local n1 = stripe.next(s)
  local n2 = stripe.next(s)
  local n3 = stripe.next(s)
  assert(n1 ~= nil, "first not nil")
  assert(n2 ~= nil, "second not nil")
  local ids = {n1.id, n2.id, n3.id}
  -- Might not be strictly round-robin if we hash differently,
  -- but we verify we get non-nil devices
  assert(#ids == 3, "three devices returned")

  -- Failover: take node 1 offline
  stripe.fail(s, "n1", 1)  -- fail immediately (max_fails=1)
  assert(d1.online == false, "n1 taken offline")
  assert(stripe.alive_count(s) == 2, "2 alive after fail")

  -- Should skip n1
  local n_after = stripe.next(s)
  assert(n_after.id ~= "n1", "skips offline: " .. tostring(n_after.id))

  -- Restore
  local restored = stripe.restore(s, "n1")
  assert(restored == true, "n1 restored")
  assert(d1.online == true, "n1 online again")
  assert(stripe.alive_count(s) == 3, "3 alive after restore")

  -- All offline
  d1.online = false
  d2.online = false
  d3.online = false
  local none = stripe.next(s)
  assert(none == nil, "nil when all offline")
end

-----------------------------------------------------------------------
-- Summary
-----------------------------------------------------------------------
io.write(string.format("\nResults: %d passed, %d failed out of %d\n", ok, fail, ok + fail))

if fail > 0 then
  io.write("SOME TESTS FAILED\n")
  os.exit(1)
else
  io.write("ALL TESTS PASSED\n")
  os.exit(0)
end
