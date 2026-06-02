# CoCapn Lua

**The glue between layers.**

CoCapn in Lua — the universal lightweight embedding language. Lua runs inside ESP32 firmware, inside OpenCPN's plugin system, inside game engines. It's the language that speaks to every other language.

- **200KB** — tiny footprint, massive reach
- **LuaJIT** — faster than V8 for many workloads
- **Embeddable** — in Redis, Nginx, Neovim, Roblox, embedded devices
- **Pure Lua 5.1+** — no native dependencies

## Modules

| Module           | Description                                      |
|------------------|--------------------------------------------------|
| `cocapn/device`  | Capability-based device descriptors & tiering    |
| `cocapn/deadband`| Hysteresis zones with approaching-state alerts   |
| `cocapn/autopilot`| PID heading controller with 360° wrap           |
| `cocapn/escalation`| Multi-tier alert routing & priority escalation |
| `cocapn/nmea`    | NMEA 0183 sentence parser & coordinate converter |
| `cocapn/stripe`  | Device striping with round-robin/hash/failover   |

## Usage

```lua
local device = require "cocapn.device"
local deadband = require "cocapn.deadband"
local autopilot = require "cocapn.autopilot"
local escalation = require "cocapn.escalation"
local nmea = require "cocapn.nmea"
local stripe = require "cocapn.stripe"

-- Create a compass sensor
local compass = device.new_device("compass-01", "HMC5883L", device.TIER.REFLEX,
  device.CAP.SENSE + device.CAP.COMM)

assert(device.can(compass, device.CAP.SENSE))

-- Deadband: heading within 5° of 180°
local db = deadband.new(180, 5)
assert(deadband.within(db, 178))
assert(deadband.exceeded(db, 190))

-- PID autopilot
local pid = autopilot.new_pid(0.5, 0.01, 0.1, 30, 3)
local rudder, err, on_course = autopilot.update(pid, 78, 90, 0.1)
print(string.format("Rudder: %.2f, Error: %.2f, On course: %s", rudder, err, tostring(on_course)))

-- NMEA parsing
local parsed = nmea.parse("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47")
if parsed then
  local lat = nmea.parse_coord(parsed.fields[3], parsed.fields[4])
  local lon = nmea.parse_coord(parsed.fields[5], parsed.fields[6])
  print(string.format("Position: %.4f, %.4f", lat, lon))
end
```

## Running Tests

```bash
lua tests/test_all.lua
```

## License

MIT
