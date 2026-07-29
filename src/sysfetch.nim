import std/[json, os, osproc, sequtils, strformat, strutils, times, unicode]
import ./logo_data

type
  MachineInfo = object
    username: string
    hostname: string
    os: string
    host: string
    kernel: string
    uptime: string
    packages: string
    shell: string
    resolution: string
    desktopEnvironment: string
    windowManager: string
    windowManagerTheme: string
    theme: string
    icons: string
    terminal: string
    terminalFont: string
    cpu: string
    gpu: string
    gpuDriver: string
    memory: string
    disk: string
    cpuDetails: string
    gpuDetails: string
    memoryDetails: string
    diskDetails: string
    externalDevices: string
    battery: string
    localIp: string
    publicIp: string
    users: string
    locale: string
    font: string
    song: string

const unavailable = "<unknown>"
const neofetchJsonVersion = "7.1.0"

proc run(command: string): string =
  let (output, exitCode) = execCmdEx(command)
  if exitCode == 0:
    output.strip()
  else:
    ""

proc runRaw(command: string): string =
  let (output, exitCode) = execCmdEx(command)
  if exitCode == 0: output else: ""

proc runOutput(command: string): string =
  let (output, _) = execCmdEx(command)
  output

proc firstNonEmpty(values: varargs[string]): string =
  for value in values:
    if value.len > 0:
      return value
  unavailable

proc field(output, fieldName: string): string =
  for line in output.splitLines:
    let trimmed = line.strip
    if trimmed.startsWith(fieldName):
      return trimmed[fieldName.len .. ^1].strip
  ""

proc numberAfterColon(line: string): int64 =
  let colon = line.find(':')
  if colon < 0:
    return 0
  let digits = line[colon + 1 .. ^1].strip(chars = {'.', ' ', '\t'})
  try: parseBiggestInt(digits)
  except ValueError: 0

proc getOs(): string =
  let system = run("uname -s")
  if system == "Darwin":
    let name = firstNonEmpty(run("sw_vers -productName"), "macOS")
    let version = run("sw_vers -productVersion")
    let build = run("sw_vers -buildVersion")
    return (&"{name} {version} {build} {run(\"uname -m\")}").strip
  if system in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]:
    return (&"{system} {run(\"uname -r\")} {run(\"uname -m\")}").strip
  firstNonEmpty(run(". /etc/os-release 2>/dev/null; printf %s \"$PRETTY_NAME\""), system)

proc getHost(): string =
  let system = run("uname -s")
  if system == "Darwin":
    return firstNonEmpty(run("sysctl -n hw.model 2>/dev/null"), run("hostname"), unavailable)
  if system in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]:
    return firstNonEmpty(run("sysctl -n hw.product 2>/dev/null"),
      run("sysctl -n hw.model 2>/dev/null"), run("hostname"), unavailable)
  for path in ["/sys/devices/virtual/dmi/id/board_vendor", "/sys/devices/virtual/dmi/id/board_name"]:
    if fileExists(path):
      let vendor = if fileExists("/sys/devices/virtual/dmi/id/board_vendor"): readFile("/sys/devices/virtual/dmi/id/board_vendor").strip else: ""
      let board = if fileExists("/sys/devices/virtual/dmi/id/board_name"): readFile("/sys/devices/virtual/dmi/id/board_name").strip else: ""
      if vendor.len > 0 or board.len > 0: return (vendor & " " & board).strip
  firstNonEmpty(run("hostname"), unavailable)

proc getUptime(): string =
  let system = run("uname -s")
  var seconds: int64
  if system == "Darwin":
    let boot = run("sysctl -n kern.boottime | awk -F'[ =,]' '{print $5}'")
    try: seconds = epochTime().int64 - parseBiggestInt(boot)
    except ValueError: discard
  elif fileExists("/proc/uptime"):
    try: seconds = parseFloat(strutils.splitWhitespace(readFile("/proc/uptime"))[0]).int64
    except CatchableError: discard
  elif system in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]:
    let boot = run("sysctl -n kern.boottime 2>/dev/null | sed -E 's/[^0-9]*([0-9]+).*/\\1/'")
    try: seconds = epochTime().int64 - parseBiggestInt(boot)
    except ValueError: discard
  if seconds <= 0:
    return unavailable
  let days = seconds div 86400
  let hours = (seconds mod 86400) div 3600
  let minutes = (seconds mod 3600) div 60
  let dayText = if days == 1: "day" else: "days"
  let hourText = if hours == 1: "hour" else: "hours"
  let minuteText = if minutes == 1: "min" else: "mins"
  if days > 0:
    result = &"{days} {dayText}"
    if hours > 0: result &= &", {hours} {hourText}"
    if minutes > 0: result &= &", {minutes} {minuteText}"
  elif hours > 0:
    result = &"{hours} {hourText}"
    if minutes > 0: result &= &", {minutes} {minuteText}"
  else:
    result = &"{minutes} {minuteText}"

proc packageCount(command: string): int =
  try: parseInt(run(command))
  except ValueError: 0

proc getPackages(): string =
  if run("uname -s") == "Darwin":
    let formula = packageCount("brew list --formula 2>/dev/null | wc -l")
    let cask = packageCount("brew list --cask 2>/dev/null | wc -l")
    if formula + cask > 0: return &"{formula + cask} (brew)"
  elif fileExists("/usr/bin/dpkg"):
    let count = packageCount("dpkg-query -f '.\\n' -W 2>/dev/null | wc -l")
    if count > 0: return &"{count} (dpkg)"
  elif fileExists("/usr/bin/rpm"):
    let count = packageCount("rpm -qa 2>/dev/null | wc -l")
    if count > 0: return &"{count} (rpm)"
  elif fileExists("/usr/local/sbin/pkg") or fileExists("/usr/sbin/pkg_info"):
    let count = if fileExists("/usr/local/sbin/pkg"):
      packageCount("pkg info 2>/dev/null | wc -l")
    else:
      packageCount("pkg_info 2>/dev/null | wc -l")
    if count > 0: return &"{count} (pkg)"
  unavailable

proc getShell(): string =
  let shellPath = getEnv("SHELL", "")
  if shellPath.len == 0: return unavailable
  let name = shellPath.splitPath.tail
  var version: string
  if name == "bash":
    version = run(&"{shellPath} -c 'printf %s \"$BASH_VERSION\"'")
  elif name == "zsh":
    version = run(&"{shellPath} -c 'printf %s \"$ZSH_VERSION\"'")
  else:
    let versionLines = run(&"{shellPath} --version 2>/dev/null").splitLines
    version = if versionLines.len > 0: versionLines[0] else: ""
    let versionParts = strutils.splitWhitespace(version)
    if versionParts.len > 1 and versionParts[0] == name:
      version = versionParts[1]
  version = version.split('-')[0]
  version = version.split('(')[0]
  if version.len > 0: &"{name} {version}" else: name

proc getResolution(): string =
  let system = run("uname -s")
  let output = if system == "Darwin": run("system_profiler SPDisplaysDataType 2>/dev/null") else: run("xrandr --query 2>/dev/null")
  var displays: seq[string]
  for line in output.splitLines:
    if system == "Darwin":
      let value = field(line, "Resolution:")
      if value.len == 0: continue
      let parts = strutils.splitWhitespace(value)
      if parts.len >= 3:
        let resolution = &"{parts[0]}x{parts[2]}"
        if resolution notin displays: displays.add(resolution)
    elif line.contains(" connected"):
      let parts = strutils.splitWhitespace(line)
      for part in parts:
        if part.contains("x") and part[0].isDigit:
          let resolution = part.split('+')[0]
          if resolution notin displays: displays.add(resolution)
          break
  if displays.len > 1: &"{displays.join(\" , \" )} @ UHDHz"
  elif displays.len == 1: displays[0]
  else: unavailable

proc getTerminalFont(): string =
  if run("uname -s") == "Darwin":
    let value = run("defaults read com.googlecode.iterm2.plist 2>/dev/null | awk -F' = ' '/Normal Font/{gsub(/[\\\";]/,\"\",$2); print $2; exit}'")
    if value.len > 0: return value
  let value = firstNonEmpty(getEnv("TERMINAL_FONT", ""), getEnv("TERM_FONT", ""))
  if value.len > 0: return value
  unavailable

proc getFont(): string = firstNonEmpty(getEnv("FONT", ""), unavailable)

proc getSong(): string =
  let value = if run("uname -s") == "Darwin":
    run("osascript -e 'tell application \"Music\" to if player state is playing then return (artist of current track as string) & \"\\n\" & (album of current track as string) & \"\\n\" & (name of current track as string)' 2>/dev/null")
    else: run("playerctl metadata --format '{{artist}}\\n{{album}}\\n{{title}}' 2>/dev/null")
  let parts = value.splitLines
  if parts.len >= 3 and parts[0].len > 0:
    &"{parts[0]} - {parts[1]} - {parts[2]}"
  else:
    unavailable

proc getWindowManager(): string =
  let processes = run("ps -e -o comm=")
  for candidate in ["chunkwm", "kwm", "yabai", "Amethyst", "Spectacle", "Rectangle", "Hyprland", "sway", "i3", "kwin_wayland", "mutter", "openbox"]:
    if processes.contains(candidate):
      return if candidate == "kwm": "Kwm" else: candidate
  if run("uname -s") == "Darwin": "Quartz Compositor"
  else: firstNonEmpty(getEnv("XDG_CURRENT_DESKTOP", ""), getEnv("XDG_SESSION_DESKTOP", ""), unavailable)

proc getCpu(): string =
  let system = run("uname -s")
  let brand = firstNonEmpty(
    run("sysctl -n machdep.cpu.brand_string 2>/dev/null"),
    run("sysctl -n hw.model 2>/dev/null"),
    run("lscpu 2>/dev/null | awk -F: '/Model name/ {print $2; exit}'"),
    if system in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]: run("sysctl -n hw.machine 2>/dev/null") else: "")
  if brand == unavailable: unavailable else: brand

proc getGpu(): string =
  let system = run("uname -s")
  let output = if system == "Darwin": run("system_profiler SPDisplaysDataType 2>/dev/null")
    elif system in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]: run("pciconf -lv 2>/dev/null | grep -B3 -Ei 'display|vga|3d'")
    else: run("lspci 2>/dev/null | grep -Ei 'VGA|3D|Display'")
  var gpus: seq[string]
  if system == "Darwin":
    for line in output.splitLines:
      let value = field(line, "Chipset Model:")
      if value.len > 0 and value notin gpus: gpus.add(value)
  else:
    for line in output.splitLines:
      let value = if line.contains(": "): line.split(": ", 1)[1] else: line
      if value.len > 0 and value notin gpus: gpus.add(value)
  if gpus.len > 0: gpus.join(", ") else: unavailable

proc getGpuDriver(): string =
  let system = run("uname -s")
  if system == "Darwin": "macOS Default Graphics Driver"
  elif system == "Linux": firstNonEmpty(run("lspci -k 2>/dev/null | awk -F': ' '/Kernel driver in use/{print $2; exit}'"), unavailable)
  else: unavailable

proc getCpuDetails(): string =
  let system = run("uname -s")
  if system == "Darwin":
    let brand = firstNonEmpty(run("sysctl -n machdep.cpu.brand_string 2>/dev/null"), run("sysctl -n hw.model 2>/dev/null"))
    let logical = firstNonEmpty(run("sysctl -n hw.ncpu 2>/dev/null"), "")
    let physical = firstNonEmpty(run("sysctl -n hw.physicalcpu 2>/dev/null"), "")
    let performance = run("sysctl -n hw.perflevel0.logicalcpu 2>/dev/null")
    let efficiency = run("sysctl -n hw.perflevel1.logicalcpu 2>/dev/null")
    var parts: seq[string]
    if brand != unavailable: parts.add(brand)
    if logical.len > 0: parts.add(&"{logical} logical cores")
    if physical.len > 0 and physical != logical: parts.add(&"{physical} physical cores")
    if performance.len > 0 and efficiency.len > 0: parts.add(&"{performance} performance + {efficiency} efficiency")
    return if parts.len > 0: parts.join(", ") else: unavailable
  if system == "Linux":
    let output = run("lscpu 2>/dev/null")
    let model = field(output, "Model name:")
    let sockets = field(output, "Socket(s):")
    let cores = field(output, "Core(s) per socket:")
    let threads = field(output, "Thread(s) per core:")
    let mhz = field(output, "CPU max MHz:")
    let cache = field(output, "L3 cache:")
    var parts: seq[string]
    if model.len > 0: parts.add(model)
    if sockets.len > 0: parts.add(&"{sockets} socket(s)")
    if cores.len > 0: parts.add(&"{cores} cores/socket")
    if threads.len > 0: parts.add(&"{threads} threads/core")
    if mhz.len > 0: parts.add(&"max {mhz} MHz")
    if cache.len > 0: parts.add(&"L3 {cache}")
    return if parts.len > 0: parts.join(", ") else: unavailable
  firstNonEmpty(run("sysctl -n hw.model 2>/dev/null"), run("sysctl -n hw.machine 2>/dev/null"), unavailable)

proc getGpuDetails(): string =
  let system = run("uname -s")
  if system == "Darwin":
    let output = run("system_profiler SPDisplaysDataType 2>/dev/null")
    var parts: seq[string]
    for label in ["Chipset Model:", "Total Number of Cores:", "VRAM:", "Metal Support:"]:
      let value = field(output, label)
      if value.len > 0: parts.add(&"{label[0 ..< label.len - 1]} {value}")
    return if parts.len > 0: parts.join(", ") else: unavailable
  if system == "Linux":
    let output = run("lspci -vmm 2>/dev/null")
    var parts: seq[string]
    for label in ["Vendor:", "Device:", "Rev:", "Kernel driver in use:"]:
      let value = field(output, label)
      if value.len > 0: parts.add(&"{label[0 ..< label.len - 1]} {value}")
    let driver = run("lspci -k 2>/dev/null | awk -F': ' '/Kernel modules:/{print $2; exit}'")
    if driver.len > 0: parts.add("Kernel modules " & driver)
    return if parts.len > 0: parts.join(", ") else: unavailable
  firstNonEmpty(run("pciconf -lv 2>/dev/null | grep -m1 -E 'vendor|device'"), unavailable)

proc getMemoryDetails(): string =
  let system = run("uname -s")
  if system == "Darwin":
    let output = run("system_profiler SPMemoryDataType 2>/dev/null")
    var parts: seq[string]
    for label in ["Type:", "Speed:", "Manufacturer:", "Part Number:"]:
      let value = field(output, label)
      if value.len > 0 and value notin parts: parts.add(&"{label[0 ..< label.len - 1]} {value}")
    if parts.len == 0:
      let total = packageCount("sysctl -n hw.memsize 2>/dev/null") div (1024 * 1024 * 1024)
      if total > 0: parts.add(&"{total} GiB installed")
    return if parts.len > 0: parts.join(", ") else: unavailable
  if system == "Linux":
    let output = run("sudo -n dmidecode -t memory 2>/dev/null || dmidecode -t memory 2>/dev/null")
    var parts: seq[string]
    for label in ["Type:", "Speed:", "Manufacturer:", "Part Number:"]:
      let value = field(output, label)
      if value.len > 0 and value notin parts: parts.add(&"{label[0 ..< label.len - 1]} {value}")
    return if parts.len > 0: parts.join(", ") else: unavailable
  unavailable

proc getDiskDetails(): string =
  let system = run("uname -s")
  if system == "Darwin":
    let output = run("diskutil info / 2>/dev/null")
    var parts: seq[string]
    for label in ["Device / Media Name:", "Protocol:", "Solid State:", "Disk Size:"]:
      let value = field(output, label)
      if value.len > 0: parts.add(&"{label[0 ..< label.len - 1]} {value}")
    return if parts.len > 0: parts.join(", ") else: unavailable
  if system == "Linux":
    let output = run("lsblk -dn -o MODEL,TRAN,ROTA,SIZE 2>/dev/null | head -1")
    return if output.len > 0: output else: unavailable
  firstNonEmpty(run("geom disk list 2>/dev/null | awk -F': ' '/descr:/{print $2; exit}'"), unavailable)

proc getExternalDevices(): string =
  let system = run("uname -s")
  if system == "Darwin":
    let output = run("system_profiler SPUSBDataType SPThunderboltDataType SPBluetoothDataType 2>/dev/null")
    var previous = ""
    var devices: seq[string]
    for line in output.splitLines:
      let trimmed = line.strip
      if trimmed.len == 0: continue
      if trimmed.startsWith("Manufacturer:") or trimmed.startsWith("Vendor:"):
        let vendor = trimmed.split(":", 1)[1].strip
        if previous.len > 0 and vendor.len > 0:
          let entry = &"{previous} ({vendor})"
          if entry notin devices: devices.add(entry)
      elif trimmed.startsWith("Model:") or trimmed.startsWith("Product:") or trimmed.startsWith("Device Name:"):
        let model = trimmed.split(":", 1)[1].strip
        if model.len > 0 and model notin devices: devices.add(model)
      elif not trimmed.contains(":") and not trimmed.endsWith("Bus:"):
        previous = trimmed
    # Bluetooth reports connected devices as indented names followed by a
    # numeric vendor ID rather than a Manufacturer field.
    var connected = false
    var bluetoothName = ""
    for line in output.splitLines:
      let trimmed = line.strip
      let indent = line.len - line.strip(leading = true, trailing = false).len
      if trimmed == "Connected:":
        connected = true
        continue
      if trimmed == "Not Connected:":
        connected = false
        bluetoothName = ""
        continue
      if connected and indent >= 10 and trimmed.endsWith(":") and not trimmed.contains(" "):
        bluetoothName = trimmed[0 ..< trimmed.len - 1]
      elif connected and indent >= 10 and trimmed.endsWith(":") and
           not (trimmed.startsWith("Address") or trimmed.startsWith("Vendor ID") or
                trimmed.startsWith("Product ID")):
        bluetoothName = trimmed[0 ..< trimmed.len - 1]
      elif connected and bluetoothName.len > 0 and trimmed.startsWith("Vendor ID:"):
        let vendorId = trimmed.split(":", 1)[1].strip
        let vendor = case vendorId.toUpperAscii
          of "0X046D": "Logitech"
          of "0X1A2C": "LANGTU"
          of "0X004C": "Apple"
          else: "vendor " & vendorId
        let entry = &"{bluetoothName} ({vendor})"
        if entry notin devices: devices.add(entry)
        bluetoothName = ""
    devices = devices.filterIt(not it.contains("MacBook Air"))
    return if devices.len > 0: devices.join(", ") else: unavailable
  if system == "Linux":
    var devices: seq[string]
    for line in run("lsusb 2>/dev/null").splitLines:
      let marker = line.find(" ID ")
      if marker >= 0:
        let value = line[marker + 4 .. ^1]
        if value.len > 0: devices.add(value)
    for line in run("bluetoothctl devices 2>/dev/null").splitLines:
      let trimmed = line.strip
      if trimmed.startsWith("Device "):
        let parts = strutils.splitWhitespace(trimmed)
        if parts.len >= 3: devices.add(parts[2 .. ^1].join(" ") & " (Bluetooth)")
    return if devices.len > 0: devices.join(", ") else: unavailable
  let usb = run("usbconfig list 2>/dev/null")
  if usb.len > 0: return usb.replace("ugen", "USB ").replace(" at ", " (") & ")"
  firstNonEmpty(run("usbdevs 2>/dev/null | sed -n 's/.*addr [0-9]*: //p'"), unavailable)

proc diskAt(path: string): string =
  let command = "df -h " & quoteShell(path) & " 2>/dev/null | awk 'NR==2 {print $3 \" / \" $2 \" (\" $5 \")\"}'"
  let value = run(command)
  if value.len > 0: value.replace("Gi", "G").replace("Mi", "M") else: unavailable

proc getDisk(): string = diskAt("/")

proc getBattery(): string =
  if run("uname -s") == "Darwin":
    let value = run("pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1")
    if value.len > 0: return value
  elif fileExists("/sys/class/power_supply/BAT0/capacity"):
    let value = readFile("/sys/class/power_supply/BAT0/capacity").strip
    if value.len > 0: return value & "%"
  elif run("uname -s") in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]:
    let value = run("acpiconf -i 0 2>/dev/null | awk -F': ' '/Remaining capacity/{print $2; exit}'")
    if value.len > 0: return value
  unavailable

proc getLocalIp(): string =
  if run("uname -s") == "Darwin":
    let netInterface = run("route get default 2>/dev/null | awk '/interface:/{print $2; exit}'")
    let value = if netInterface.len > 0: run(&"ipconfig getifaddr {netInterface} 2>/dev/null") else: ""
    if value.len > 0: return value
  else:
    let value = if run("uname -s") == "Linux": run("hostname -I 2>/dev/null | awk '{print $1}'")
      else: run("route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' | xargs -I{} ifconfig {} 2>/dev/null | awk '/inet /{print $2; exit}'")
    if value.len > 0: return value
  unavailable

proc getPublicIp(host = "", timeout = 5): string =
  if host.len == 0: return unavailable
  let value = run(&"curl -L --max-time {timeout} -fsS {host} 2>/dev/null")
  if value.len > 0: value else: unavailable

proc getUsers(): string =
  let value = run("who 2>/dev/null | awk '!seen[$1]++ {printf \"%s, \", $1}' | sed 's/, $//'")
  if value.len > 0: value else: unavailable

proc getLocale(): string = firstNonEmpty(getEnv("LANG", ""), getEnv("LC_ALL", ""), unavailable)

proc getMemory(): string =
  if run("uname -s") == "Darwin":
    let total = packageCount("sysctl -n hw.memsize 2>/dev/null") div (1024 * 1024)
    let pageSize = packageCount("sysctl -n hw.pagesize 2>/dev/null")
    let pageable = packageCount("sysctl -n vm.page_pageable_internal_count 2>/dev/null")
    let purgeable = packageCount("sysctl -n vm.page_purgeable_count 2>/dev/null")
    let wired = numberAfterColon(run("vm_stat 2>/dev/null | grep 'Pages wired down'"))
    let compressed = numberAfterColon(run("vm_stat 2>/dev/null | grep 'occupied by compressor'"))
    let used = ((pageable.int64 - purgeable.int64 + wired + compressed) * pageSize.int64) div (1024 * 1024)
    if total > 0: return &"{used}MiB / {total}MiB"
  elif fileExists("/proc/meminfo"):
    let memTotal = numberAfterColon(run("awk '/^MemTotal:/{print $0}' /proc/meminfo"))
    let memAvailable = numberAfterColon(run("awk '/^MemAvailable:/{print $0}' /proc/meminfo"))
    if memTotal > 0: return &"{(memTotal - memAvailable) div 1024}MiB / {memTotal div 1024}MiB"
  elif run("uname -s") in ["FreeBSD", "OpenBSD", "NetBSD", "DragonFly"]:
    let total = packageCount("sysctl -n hw.physmem 2>/dev/null") div (1024 * 1024)
    let free = packageCount("sysctl -n hw.pagesize 2>/dev/null") * packageCount("vmstat -s 2>/dev/null | awk '/pages free/{print $1; exit}'") div (1024 * 1024)
    if total > 0: return &"{max(0, total - free)}MiB / {total}MiB"
  unavailable

proc collect(): MachineInfo =
  result.username = getEnv("USER", getEnv("USERNAME", unavailable))
  result.hostname = firstNonEmpty(run("hostname"), unavailable)
  result.os = getOs()
  result.host = getHost()
  result.kernel = firstNonEmpty(run("uname -r"), unavailable)
  result.uptime = getUptime()
  result.packages = getPackages()
  result.shell = getShell()
  result.resolution = getResolution()
  result.desktopEnvironment = if run("uname -s") == "Darwin": "Aqua" else: firstNonEmpty(getEnv("XDG_CURRENT_DESKTOP", ""), unavailable)
  result.windowManager = getWindowManager()
  result.windowManagerTheme = unavailable
  result.theme = unavailable
  result.icons = unavailable
  result.terminal = firstNonEmpty(getEnv("TERM_PROGRAM", ""), getEnv("TERM", ""), unavailable)
  if result.terminal == "iTerm.app": result.terminal = "iTerm2"
  result.terminalFont = getTerminalFont()
  result.cpu = getCpu()
  result.gpu = getGpu()
  result.gpuDriver = getGpuDriver()
  result.memory = getMemory()
  result.disk = getDisk()
  result.cpuDetails = getCpuDetails()
  result.gpuDetails = getGpuDetails()
  result.memoryDetails = getMemoryDetails()
  result.diskDetails = getDiskDetails()
  result.externalDevices = getExternalDevices()
  result.battery = getBattery()
  result.localIp = getLocalIp()
  result.publicIp = getPublicIp()
  result.users = getUsers()
  result.locale = getLocale()
  result.font = getFont()
  result.song = getSong()

proc toJson(info: MachineInfo, includeExtended = false, includeHardware = false): JsonNode =
  result = newJObject()
  result["OS"] = %info.os
  result["Host"] = %info.host
  result["Kernel"] = %info.kernel
  result["Uptime"] = %info.uptime
  result["Packages"] = %info.packages
  result["Shell"] = %info.shell
  result["Resolution"] = %info.resolution
  result["DE"] = %info.desktopEnvironment
  result["WM"] = %info.windowManager
  result["Terminal"] = %info.terminal
  result["CPU"] = %info.cpu
  result["GPU"] = %info.gpu
  result["Memory"] = %info.memory
  if info.terminalFont != unavailable: result["Terminal Font"] = %info.terminalFont
  if includeExtended:
    for item in [("GPU Driver", info.gpuDriver), ("Disk", info.disk),
                 ("Battery", info.battery), ("Font", info.font),
                 ("Song", info.song), ("Local IP", info.localIp),
                 ("Public IP", info.publicIp), ("Users", info.users),
                 ("Locale", info.locale)]:
      if item[1] != unavailable: result[item[0]] = %item[1]
  if includeHardware:
    for item in [("CPU Details", info.cpuDetails), ("GPU Details", info.gpuDetails),
                 ("Memory Details", info.memoryDetails), ("Disk Details", info.diskDetails),
                 ("External Devices", info.externalDevices)]:
      if item[1] != unavailable: result[item[0]] = %item[1]
  result["Version"] = %neofetchJsonVersion

proc stripAnsi(value: string): string =
  var state = 0
  var index = 0
  while index < value.len:
    let ch = value[index]
    case state
    of 0:
      if ch == '\e': state = 3
      else: result.add(ch)
    of 1:
      if ch >= '@' and ch <= '~': state = 0
    of 2:
      if ch == '\a': state = 0
      elif ch == '\e' and index + 1 < value.len and value[index + 1] == '\\':
        inc index
        state = 0
    else:
      if ch == '[': state = 1
      elif ch == ']': state = 2
      else: state = 0
    inc index

proc stripNonColorControls(value: string): string =
  var index = 0
  while index < value.len:
    if value[index] != '\e':
      result.add(value[index])
      inc index
      continue
    if index + 1 >= value.len:
      break
    if value[index + 1] == '[':
      var finish = index + 2
      while finish < value.len and not (value[finish] >= '@' and value[finish] <= '~'):
        inc finish
      if finish < value.len:
        if value[finish] == 'm':
          result.add(value[index .. finish])
        index = finish + 1
      else:
        break
    elif value[index + 1] == ']':
      while index < value.len:
        if value[index] == '\a':
          inc index
          break
        if value[index] == '\e' and index + 1 < value.len and value[index + 1] == '\\':
          index += 2
          break
        inc index
    else:
      index += 2

proc logoCacheFile(name: string): string =
  var safeName = ""
  for ch in name.toLowerAscii:
    if ch in {'a'..'z', '0'..'9', '_', '-'}: safeName.add(ch)
    else: safeName.add('_')
  let cacheRoot = getEnv("XDG_CACHE_HOME", getHomeDir() / ".cache") / "sysfetch"
  createDir(cacheRoot)
  cacheRoot / (safeName & ".logo")

proc displayWidth(value: string): int =
  var joinedEmoji = false
  for rune in stripAnsi(value).toRunes:
    let code = rune.int
    if code == 0x200d:
      joinedEmoji = true
    elif code == 0x00ad or code == 0x200b or code == 0x200c or
       (code >= 0x0300 and code <= 0x036f) or
       (code >= 0x1ab0 and code <= 0x1aff) or
       (code >= 0x1dc0 and code <= 0x1dff) or
       (code >= 0x20d0 and code <= 0x20ff) or
       (code >= 0xfe00 and code <= 0xfe0f) or
       (code >= 0xfe20 and code <= 0xfe2f) or
       (code >= 0x1f3fb and code <= 0x1f3ff):
      discard
    elif (code >= 0x1f300 and code <= 0x1faff) or
       (code >= 0x1100 and code <= 0x115f) or
       (code >= 0x2e80 and code <= 0xa4cf) or
       (code >= 0xac00 and code <= 0xd7a3) or
       (code >= 0xf900 and code <= 0xfaff) or
       (code >= 0xfe10 and code <= 0xfe6f) or
       (code >= 0xff01 and code <= 0xff60):
      if joinedEmoji: joinedEmoji = false
      else: inc result, 2
    else:
      joinedEmoji = false
      inc result

type
  CliOptions = object
    json: bool
    plain: bool
    help: bool
    version: bool
    separator: string
    disabled: seq[string]
    selected: seq[string]
    colorBlocks: bool
    blockWidth: int
    blockHeight: int
    blockStart: int
    blockEnd: int
    blockOffset: int
    logo: string
    backend: string
    noConfig: bool
    configPath: string
    printConfig: bool
    travis: bool
    logoOnly: bool
    titleFqdn: bool
    osArch: bool
    shellPath: bool
    shellVersion: bool
    memoryPercent: bool
    memoryUnit: string
    diskPercent: bool
    diskShow: string
    ipHost: string
    ipTimeout: int
    ipInterface: string
    packageManagers: string
    uptimeShorthand: string
    clean: bool
    genMan: bool
    distroShorthand: string
    kernelShorthand: string
    memoryDisplay: string
    diskDisplay: string
    batteryDisplay: string
    barLength: int
    barElapsed: string
    barTotal: string
    barBorder: bool
    barColorElapsed: string
    barColorTotal: string
    titleColor: string
    atColor: string
    underlineColor: string
    subtitleColor: string
    colonColor: string
    infoColor: string
    bold: bool
    underline: bool
    underlineChar: string
    asciiBold: bool
    asciiColors: seq[string]
    gap: int
    diskSubtitle: string
    imageSize: string
    catimgSize: string
    cropMode: string
    cropOffset: string
    xOffset: int
    yOffset: int
    backgroundColor: string
    hardwareDetails: bool

const defaultFields = [
  ("OS", "distro"), ("Host", "model"), ("Kernel", "kernel"), ("Uptime", "uptime"),
  ("Packages", "packages"), ("Shell", "shell"), ("Resolution", "resolution"),
  ("DE", "de"), ("WM", "wm"), ("WM Theme", "wm_theme"), ("Theme", "theme"),
  ("Icons", "icons"), ("Terminal", "term"), ("Terminal Font", "term_font"),
  ("CPU", "cpu"), ("GPU", "gpu"), ("Memory", "memory")]

const extendedFields = [
  ("GPU Driver", "gpu_driver"), ("Disk", "disk"), ("Battery", "battery"),
  ("Font", "font"), ("Song", "song"), ("Local IP", "local_ip"),
  ("Public IP", "public_ip"), ("Users", "users")]

proc valueFor(info: MachineInfo, key: string): string =
  case key
  of "os": info.os.split(' ', 1)[0]
  of "distro": info.os
  of "host", "model": info.host
  of "kernel": info.kernel
  of "uptime": info.uptime
  of "packages": info.packages
  of "shell": info.shell
  of "resolution": info.resolution
  of "de": info.desktopEnvironment
  of "wm": info.windowManager
  of "wm_theme": info.windowManagerTheme
  of "theme": info.theme
  of "icons": info.icons
  of "term", "terminal": info.terminal
  of "term_font": info.terminalFont
  of "cpu": info.cpu
  of "gpu": info.gpu
  of "gpu_driver": info.gpuDriver
  of "memory": info.memory
  of "disk": info.disk
  of "cpu_details": info.cpuDetails
  of "gpu_details": info.gpuDetails
  of "memory_details": info.memoryDetails
  of "disk_details": info.diskDetails
  of "external_devices": info.externalDevices
  of "battery": info.battery
  of "local_ip": info.localIp
  of "public_ip": info.publicIp
  of "users": info.users
  of "locale": info.locale
  of "font": info.font
  of "song": info.song
  else: unavailable

proc toConfiguredJson(info: MachineInfo, fields: seq[(string, string)]): JsonNode =
  result = newJObject()
  for item in fields:
    let value = valueFor(info, item[1])
    if value != unavailable and item[1] notin ["title", "underline", "cols"]:
      result[item[0]] = %value
  result["Version"] = %neofetchJsonVersion

proc addConfiguredField(fields: var seq[(string, string)], label, key: string) =
  if key.len > 0: fields.add((label, key))

proc loadConfig(path: string, fields: var seq[(string, string)], options: var CliOptions) =
  if path.len == 0 or not fileExists(path): return
  for rawLine in readFile(path).splitLines:
    let line = rawLine.strip
    if line.startsWith("#") or line.len == 0: continue
    if line.startsWith("title_fqdn") and line.contains("="):
      options.titleFqdn = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("os_arch") and line.contains("="):
      options.osArch = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("distro_shorthand") and line.contains("="):
      options.distroShorthand = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("kernel_shorthand") and line.contains("="):
      options.kernelShorthand = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("shell_path") and line.contains("="):
      options.shellPath = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("shell_version") and line.contains("="):
      options.shellVersion = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("memory_percent") and line.contains("="):
      options.memoryPercent = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("memory_unit") and line.contains("="):
      options.memoryUnit = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("disk_percent") and line.contains("="):
      options.diskPercent = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("package_managers") and line.contains("="):
      options.packageManagers = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("uptime_shorthand") and line.contains("="):
      options.uptimeShorthand = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("memory_display") and line.contains("="):
      options.memoryDisplay = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("disk_display") and line.contains("="):
      options.diskDisplay = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("battery_display") and line.contains("="):
      options.batteryDisplay = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("bar_length") and line.contains("="):
      try: options.barLength = parseInt(line.split("=", 1)[1].strip)
      except ValueError: discard
    elif line.startsWith("bar_char_elapsed") and line.contains("="):
      options.barElapsed = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.startsWith("bar_char_total") and line.contains("="):
      options.barTotal = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.startsWith("bar_border") and line.contains("="):
      options.barBorder = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("bar_color_elapsed") and line.contains("="):
      options.barColorElapsed = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.startsWith("bar_color_total") and line.contains("="):
      options.barColorTotal = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.startsWith("colors") and line.contains("="):
      let raw = line.split("=", 1)[1].replace("(", "").replace(")", "").replace("\"", "")
      let colors = strutils.splitWhitespace(raw)
      if colors.len >= 6:
        options.titleColor = colors[0]
        options.atColor = colors[1]
        options.underlineColor = colors[2]
        options.subtitleColor = colors[3]
        options.colonColor = colors[4]
        options.infoColor = colors[5]
    elif line.startsWith("bold") and line.contains("="):
      options.bold = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("underline_enabled") and line.contains("="):
      options.underline = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("underline_char") and line.contains("="):
      options.underlineChar = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.startsWith("ascii_bold") and line.contains("="):
      options.asciiBold = line.split("=", 1)[1].strip.contains("on")
    elif line.startsWith("ascii_colors") and line.contains("="):
      let raw = line.split("=", 1)[1].replace("(", "").replace(")", "").replace("\"", "")
      options.asciiColors = strutils.splitWhitespace(raw)
    elif line.startsWith("gap") and line.contains("="):
      try: options.gap = parseInt(line.split("=", 1)[1].strip)
      except ValueError: discard
    elif line.startsWith("disk_subtitle") and line.contains("="):
      options.diskSubtitle = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''}).toLowerAscii
    elif line.startsWith("ip_host") and line.contains("="):
      options.ipHost = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.startsWith("ip_timeout") and line.contains("="):
      try: options.ipTimeout = parseInt(line.split("=", 1)[1].strip)
      except ValueError: discard
    elif line.startsWith("ip_interface") and line.contains("="):
      options.ipInterface = line.split("=", 1)[1].strip(chars = {' ', '\t', '"', '\''})
    elif line.contains("separator") and line.contains("="):
      let value = line.split("=", 1)[1].strip(chars = {' ', '\t', '\"', '\''})
      if value.len > 0: options.separator = value
    elif line.contains("color_blocks") and line.contains("="):
      options.colorBlocks = line.split("=", 1)[1].strip.contains("on")
    elif line.contains("block_width") and line.contains("="):
      try: options.blockWidth = parseInt(line.split("=", 1)[1].strip)
      except ValueError: discard
    elif line.contains("block_height") and line.contains("="):
      try: options.blockHeight = parseInt(line.split("=", 1)[1].strip)
      except ValueError: discard
    elif line.contains("block_range") and line.contains("="):
      let values = strutils.splitWhitespace(line.split("=", 1)[1].replace("(", "").replace(")", ""))
      if values.len >= 2:
        try:
          options.blockStart = parseInt(values[0])
          options.blockEnd = parseInt(values[1])
        except ValueError: discard
    elif line.contains("col_offset") and line.contains("="):
      let raw = line.split("=", 1)[1].strip
      if raw != "auto":
        try: options.blockOffset = parseInt(raw)
        except ValueError: discard
    elif line.startsWith("ascii_distro") and line.contains("="):
      options.logo = line.split("=", 1)[1].strip(chars = {' ', '\t', '\"', '\''})
    elif line.startsWith("info "):
      let quoted = line[4 .. ^1].strip
      let parts = quoted.split('"')
      if parts.len >= 4:
        let label = parts[1]
        let key = parts[3]
        addConfiguredField(fields, label, key)
  let captureCommand = "bash -c 'info(){ printf \"%s\\t%s\\n\" \"$1\" \"${2:-}\"; }; prin(){ :; }; source \"$1\" >/dev/null 2>&1; print_info' -- " & quoteShell(path)
  let captured = run(captureCommand)
  var capturedFields: seq[(string, string)]
  for capturedLine in captured.splitLines:
    let parts = capturedLine.split('\t', 1)
    if parts.len == 2: capturedFields.add((parts[0], parts[1]))
  if capturedFields.len > 0: fields = capturedFields

proc parseOptions(): CliOptions =
  result.separator = ":"
  result.colorBlocks = true
  result.blockWidth = 3
  result.blockHeight = 1
  result.blockStart = 0
  result.blockEnd = 15
  result.blockOffset = 0
  result.titleFqdn = true
  result.osArch = true
  result.shellVersion = true
  result.memoryUnit = "mib"
  result.memoryPercent = false
  result.diskPercent = true
  result.ipTimeout = 5
  result.packageManagers = "on"
  result.uptimeShorthand = "on"
  result.distroShorthand = "off"
  result.kernelShorthand = "on"
  result.memoryDisplay = "off"
  result.diskDisplay = "off"
  result.batteryDisplay = "off"
  result.barLength = 15
  result.barElapsed = "-"
  result.barTotal = "="
  result.barBorder = true
  result.barColorElapsed = "7"
  result.barColorTotal = "7"
  result.titleColor = "2"
  result.atColor = "2"
  result.underlineColor = "reset"
  result.subtitleColor = "3"
  result.colonColor = "reset"
  result.infoColor = "reset"
  result.bold = true
  result.underline = true
  result.underlineChar = "-"
  result.asciiBold = true
  result.gap = 3
  result.diskSubtitle = "mount"
  result.imageSize = "auto"
  result.catimgSize = ""
  result.cropMode = "normal"
  result.hardwareDetails = true
  let args = commandLineParams()
  var preConfig = ""
  var preNoConfig = false
  for index in 0 ..< args.len:
    if args[index] == "--no_config": preNoConfig = true
    elif args[index] == "--config" and index + 1 < args.len: preConfig = args[index + 1]
  if preConfig.len == 0 and not preNoConfig:
    let configRoot = getEnv("XDG_CONFIG_HOME", getHomeDir() / ".config")
    for candidate in [configRoot / "neofetch" / "config.conf",
                      configRoot / "sysfetch" / "config.conf",
                      getHomeDir() / ".neofetch" / "config.conf"]:
      if fileExists(candidate):
        preConfig = candidate
        break
  if preConfig.len > 0 and not preNoConfig:
    var ignoredFields: seq[(string, string)]
    loadConfig(preConfig, ignoredFields, result)
    result.configPath = preConfig
  var index = 0
  while index < args.len:
    let argument = args[index]
    case argument
    of "--json": result.json = true
    of "--hardware", "--details", "--hardware_details": result.hardwareDetails = true
    of "--no_hardware": result.hardwareDetails = false
    of "--stdout": result.plain = true
    of "--help", "-h": result.help = true
    of "--version": result.version = true
    of "--clean": result.clean = true
    of "--gen-man": result.genMan = true
    of "--travis": result.travis = true
    of "--no_config": result.noConfig = true
    of "--print_config": result.printConfig = true
    of "--config":
      inc index
      if index >= args.len: quit("--config requires a path", 2)
      result.configPath = args[index]
    of "--source":
      inc index
      if index >= args.len: quit(&"{argument} requires a value", 2)
      result.logo = args[index]
    of "--backend":
      inc index
      if index >= args.len: quit("--backend requires a value", 2)
      result.backend = args[index].toLowerAscii
    of "--logo":
      if index + 1 < args.len and not args[index + 1].startsWith("-"):
        inc index
        result.logo = args[index]
      else:
        result.logoOnly = true
    of "-L": result.logoOnly = true
    of "--ascii":
      result.logo = "ascii"
      if index + 1 < args.len and not args[index + 1].startsWith("-"):
        inc index
        result.logo = args[index]
    of "--caca", "--catimg", "--chafa", "--iterm2", "--jp2a", "--kitty", "--pixterm", "--pot", "--sixel", "--termpix", "--tycat", "--ueberzug", "--viu", "--w3m":
      result.backend = argument[2 .. ^1]
      if index + 1 < args.len and not args[index + 1].startsWith("-"):
        inc index
        result.logo = args[index]
    of "--separator":
      inc index
      if index >= args.len: quit("--separator requires a value", 2)
      result.separator = args[index]
    of "--disable":
      inc index
      while index < args.len and not args[index].startsWith("-"):
        result.disabled.add(args[index].toLowerAscii)
        inc index
      dec index
    of "--color_blocks":
      inc index
      if index >= args.len: quit("--color_blocks requires on/off", 2)
      result.colorBlocks = args[index] != "off"
    of "--block_width":
      inc index
      if index < args.len:
        try: result.blockWidth = parseInt(args[index])
        except ValueError: discard
    of "--block_height":
      inc index
      if index < args.len:
        try: result.blockHeight = parseInt(args[index])
        except ValueError: discard
    of "--block_range":
      inc index
      if index + 1 < args.len:
        try:
          result.blockStart = parseInt(args[index])
          inc index
          result.blockEnd = parseInt(args[index])
        except ValueError: discard
    of "--col_offset":
      inc index
      if index < args.len and args[index] != "auto":
        try: result.blockOffset = parseInt(args[index])
        except ValueError: discard
    of "--title_fqdn":
      inc index
      if index < args.len: result.titleFqdn = args[index] != "off"
    of "--os_arch":
      inc index
      if index < args.len: result.osArch = args[index] != "off"
    of "--shell_path":
      inc index
      if index < args.len: result.shellPath = args[index] != "off"
    of "--shell_version":
      inc index
      if index < args.len: result.shellVersion = args[index] != "off"
    of "--memory_percent":
      inc index
      if index < args.len: result.memoryPercent = args[index] != "off"
    of "--memory_unit":
      inc index
      if index < args.len: result.memoryUnit = args[index].toLowerAscii
    of "--disk_percent":
      inc index
      if index < args.len: result.diskPercent = args[index] != "off"
    of "--disk_show":
      inc index
      if index < args.len: result.diskShow = args[index]
    of "--disk_subtitle":
      inc index
      if index < args.len: result.diskSubtitle = args[index].toLowerAscii
    of "--ip_host":
      inc index
      if index < args.len: result.ipHost = args[index]
    of "--ip_timeout":
      inc index
      if index < args.len:
        try: result.ipTimeout = parseInt(args[index])
        except ValueError: discard
    of "--ip_interface":
      inc index
      if index < args.len: result.ipInterface = args[index]
    of "--package_managers":
      inc index
      if index < args.len: result.packageManagers = args[index].toLowerAscii
    of "--uptime_shorthand":
      inc index
      if index < args.len: result.uptimeShorthand = args[index].toLowerAscii
    of "--distro_shorthand":
      inc index
      if index < args.len: result.distroShorthand = args[index].toLowerAscii
    of "--kernel_shorthand":
      inc index
      if index < args.len: result.kernelShorthand = args[index].toLowerAscii
    of "--bold":
      inc index
      if index < args.len: result.bold = args[index] != "off"
    of "--underline":
      inc index
      if index < args.len: result.underline = args[index] != "off"
    of "--underline_char":
      inc index
      if index < args.len: result.underlineChar = args[index]
    of "--memory_display":
      inc index
      if index < args.len: result.memoryDisplay = args[index].toLowerAscii
    of "--disk_display":
      inc index
      if index < args.len: result.diskDisplay = args[index].toLowerAscii
    of "--battery_display":
      inc index
      if index < args.len: result.batteryDisplay = args[index].toLowerAscii
    of "--bar_length":
      inc index
      if index < args.len:
        try: result.barLength = parseInt(args[index])
        except ValueError: discard
    of "--bar_char":
      inc index
      if index < args.len: result.barElapsed = args[index]
      inc index
      if index < args.len: result.barTotal = args[index]
    of "--bar_border":
      inc index
      if index < args.len: result.barBorder = args[index] != "off"
    of "--bar_colors":
      inc index
      if index < args.len: result.barColorElapsed = args[index]
      inc index
      if index < args.len: result.barColorTotal = args[index]
    of "--colors":
      var colors: seq[string]
      inc index
      while index < args.len and not args[index].startsWith("-") and colors.len < 6:
        colors.add(args[index])
        inc index
      dec index
      if colors.len >= 6:
        result.titleColor = colors[0]
        result.atColor = colors[1]
        result.underlineColor = colors[2]
        result.subtitleColor = colors[3]
        result.colonColor = colors[4]
        result.infoColor = colors[5]
    of "--ascii_distro":
      inc index
      if index < args.len: result.logo = args[index].toLowerAscii
    of "--de_version", "--gtk_shorthand", "--gtk2", "--gtk3",
       "--refresh_rate", "--cpu_brand", "--cpu_cores", "--cpu_speed", "--cpu_temp",
       "--gpu_brand",
       "--gpu_type", "--song_format", "--song_shorthand", "--music_player":
      inc index
    of "--image_size", "--size":
      inc index
      if index < args.len: result.imageSize = args[index]
    of "--catimg_size":
      inc index
      if index < args.len: result.catimgSize = args[index]
    of "--crop_mode":
      inc index
      if index < args.len: result.cropMode = args[index]
    of "--crop_offset":
      inc index
      if index < args.len: result.cropOffset = args[index]
    of "--xoffset":
      inc index
      if index < args.len:
        try: result.xOffset = parseInt(args[index])
        except ValueError: discard
    of "--yoffset":
      inc index
      if index < args.len:
        try: result.yOffset = parseInt(args[index])
        except ValueError: discard
    of "--background_color", "--bg_color":
      inc index
      if index < args.len: result.backgroundColor = args[index]
    of "--ascii_bold":
      inc index
      if index < args.len: result.asciiBold = args[index] != "off"
    of "--ascii_colors":
      result.asciiColors = @[]
      inc index
      while index < args.len and not args[index].startsWith("-") and result.asciiColors.len < 6:
        result.asciiColors.add(args[index])
        inc index
      dec index
    of "--gap":
      inc index
      if index < args.len:
        try: result.gap = parseInt(args[index])
        except ValueError: discard
    of "--pipe": result.plain = true
    of "--off": result.logo = "none"
    of "--speed_type", "--speed_shorthand", "--image_backend", "--color":
      inc index
    of "--loop", "-v", "-vv":
      discard
    else:
      if argument.startsWith("-"):
        discard
      result.selected.add(argument.toLowerAscii)
    inc index
  if getEnv("SYSFETCH_NEofETCH_COMPAT", "") == "1":
    result.hardwareDetails = false

proc ansiColor(value: string): string

proc addInfo(lines: var seq[string], info: MachineInfo, label, key: string, options: CliOptions) =
  if key in options.disabled: return
  if options.selected.len > 0 and key notin options.selected: return
  let value = valueFor(info, key)
  if value != unavailable:
    if options.plain:
      lines.add(&"{label}{options.separator} {value}")
    else:
      let bold = if options.bold: "\e[1m" else: ""
      lines.add(ansiColor(options.subtitleColor) & bold & label & ansiColor(options.colonColor) & options.separator & ansiColor(options.infoColor) & " " & value & "\e[0m")

proc trimLogoLines(lines: var seq[string]) =
  while lines.len > 0 and lines[^1].len == 0:
    lines.setLen(lines.len - 1)

proc remapAsciiLogoColors(lines: var seq[string], colors: seq[string]) =
  var sourceColors: seq[string]
  for line in lines:
    var cursor = 0
    while true:
      let start = line.find("\e[", cursor)
      if start < 0: break
      let finish = line.find('m', start + 2)
      if finish < 0: break
      let sequence = line[start .. finish]
      if sequence notin ["\e[0m", "\e[1m"] and sequence notin sourceColors:
        sourceColors.add(sequence)
      cursor = finish + 1
  let count = min(sourceColors.len, colors.len)
  if count == 0: return
  for index in 0 ..< lines.len:
    for colorIndex in 0 ..< count:
      lines[index] = lines[index].replace(sourceColors[colorIndex], &"\x01{colorIndex}\x02")
    for colorIndex in 0 ..< count:
      lines[index] = lines[index].replace(&"\x01{colorIndex}\x02", ansiColor(colors[colorIndex]))

proc styleLogo(lines: var seq[string], plain: bool, asciiBold: bool, asciiColors: seq[string]) =
  trimLogoLines(lines)
  if plain:
    for index in 0 ..< lines.len:
      lines[index] = stripAnsi(lines[index])
  else:
    for index in 0 ..< lines.len:
      if not asciiBold: lines[index] = lines[index].replace("\e[1m", "")
    if asciiColors.len > 0 and not (asciiColors.len == 1 and asciiColors[0].toLowerAscii == "distro"):
      remapAsciiLogoColors(lines, asciiColors)

proc imageGeometry(size: string, defaultWidth = 80, defaultHeight = 40): (int, int) =
  result = (defaultWidth, defaultHeight)
  let normalized = size.toLowerAscii.replace(" ", "")
  let separator = normalized.find('x')
  try:
    if separator > 0:
      result[0] = max(1, parseInt(normalized[0 ..< separator]))
      result[1] = max(1, parseInt(normalized[separator + 1 .. ^1]))
    elif normalized.len > 0 and normalized != "auto":
      result[0] = max(1, parseInt(normalized))
  except ValueError: discard

proc getLogo(plain: bool, source = "", backend = "", asciiBold = true, asciiColors: seq[string] = @[], imageSize = "auto", catimgSize = "", cropMode = "normal", cropOffset = "", xOffset = 0, yOffset = 0, backgroundColor = ""): seq[string] =
  if backend in ["off", "none"]: return @[]
  var sourcePath = if source in ["", "ascii", "auto"]: "" else: source
  if sourcePath == "wallpaper" and run("uname -s") == "Darwin":
    sourcePath = run("osascript -e 'tell application \"System Events\" to picture of current desktop' 2>/dev/null")
  if sourcePath.len > 0 and sourcePath.toLowerAscii notin ["macos", "mac", "darwin"] and
     not fileExists(sourcePath):
    result = bundledLogo(sourcePath)
    let cached = logoCacheFile(sourcePath)
    if result.len == 0 and fileExists(cached):
      result = readFile(cached).splitLines
    elif result.len == 0 and run("command -v curl 2>/dev/null").len > 0:
      let official = runRaw("curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch | bash -s -- --no_config --ascii_distro " & quoteShell(sourcePath) & " -L 2>/dev/null")
      if official.len > 0:
        let cleanOfficial = stripNonColorControls(official)
        writeFile(cached, cleanOfficial)
        result = cleanOfficial.splitLines
    if result.len == 0 and run("command -v fastfetch 2>/dev/null").len > 0:
      let fastfetchLogo = runRaw(&"fastfetch --logo {quoteShell(sourcePath)} --structure none --logo-print-remaining true --pipe 2>/dev/null")
      if fastfetchLogo.len > 0: result = fastfetchLogo.splitLines
  if result.len > 0:
    styleLogo(result, plain, asciiBold, asciiColors)
    return
  if backend notin ["", "ascii"] and sourcePath.len > 0 and fileExists(sourcePath):
    let quoted = quoteShell(sourcePath)
    let (width, height) = imageGeometry(if backend == "catimg" and catimgSize.len > 0: catimgSize else: imageSize)
    discard cropMode
    discard cropOffset
    discard xOffset
    discard yOffset
    discard backgroundColor
    let command = case backend
      of "caca": &"img2txt -W {width} -H {height} --gamma=0.6 {quoted} 2>/dev/null"
      of "catimg": &"catimg -w {width} -r 1 {quoted} 2>/dev/null"
      of "chafa": &"chafa --stretch --size={width}x{height} {quoted} 2>/dev/null"
      of "jp2a": &"jp2a --colors --width={width} --height={height} {quoted} 2>/dev/null"
      of "viu": &"viu -t -w {width} -h {height} {quoted} 2>/dev/null"
      of "kitty": &"kitty +kitten icat --align left --place {width}x{height}@{xOffset}x{yOffset} {quoted} 2>/dev/null"
      of "pot": &"pot {quoted} --size={width}x{height} 2>/dev/null"
      of "pixterm": &"pixterm -tc {width} -tr {height} {quoted} 2>/dev/null"
      of "termpix": &"termpix --width {width} --height {height} {quoted} 2>/dev/null"
      of "tycat": &"tycat -g {width}x{height} {quoted} 2>/dev/null"
      of "ueberzug": &"ueberzug layer --parser bash {quoted} 2>/dev/null"
      of "sixel": &"img2sixel -w {width} -h {height} {quoted} 2>/dev/null"
      of "w3m": &"w3mimgdisplay {quoted} 2>/dev/null"
      of "iterm2": &"printf '\\033]1337;File=width=80px;height=40px;inline=1:%s\\a\\n' \"$(base64 -i {quoted})\""
      else: ""
    let output = if command.len > 0: runRaw(command) else: ""
    if output.len > 0: result = output.splitLines
  if result.len > 0:
    styleLogo(result, plain, asciiBold, asciiColors)
    return
  if backend in ["", "ascii"] and sourcePath.len > 0 and fileExists(sourcePath):
    result = readFile(sourcePath).splitLines
  elif run("uname -s") == "Darwin":
    result = @[
      "\e[0m\e[32m\e[1m                    c.'",
      "                 ,xNMM.",
      "               .OMMMMo",
      "               lMM\"",
      "     .;loddo:.  .olloddol;.",
      "   cKMMMMMMMMMMNWMMMMMMMMMM0:",
      "\e[0m\e[33m\e[1m .KMMMMMMMMMMMMMMMMMMMMMMMWd.",
      " XMMMMMMMMMMMMMMMMMMMMMMMX.",
      "\e[0m\e[31m\e[1m;MMMMMMMMMMMMMMMMMMMMMMMM:",
      ":MMMMMMMMMMMMMMMMMMMMMMMM:",
      ".MMMMMMMMMMMMMMMMMMMMMMMX.",
      " kMMMMMMMMMMMMMMMMMMMMMMMMWd.",
      "\e[0m\e[35m\e[1m'XMMMMMMMMMMMMMMMMMMMMMMMMMMk",
      " 'XMMMMMMMMMMMMMMMMMMMMMMMMK.",
      "\e[0m\e[34m\e[1mkMMMMMMMMMMMMMMMMMMMMMMd",
      "     ;KMMMMMMMWXXWMMMMMMMk.",
      "       \"cooc*\"    \"*coo'\e[0m"]
  else:
    result = @["   _____ _   _ ____  ____  ", "  / ____| | | |  _ \\|  _ \\ ", " | (___ | |_| | |_) | |_) |", "  \\___ \\|  _  |  __/|  __/ ", "  ____) | | | | |   | |    ", " |_____/|_| |_|_|   |_|    "]
  styleLogo(result, plain, asciiBold, asciiColors)

proc getColorBlocks(plain: bool, options: CliOptions): string =
  let startColor = max(0, min(255, options.blockStart))
  let endColor = max(startColor, min(255, options.blockEnd))
  let width = max(1, options.blockWidth)
  let height = max(1, options.blockHeight)
  for row in 0 ..< height:
    if row > 0: result.add("\n")
    result.add(" ".repeat(max(0, options.blockOffset)))
    for color in startColor .. endColor:
      if color > startColor: result.add(" ")
      if plain: result.add(" ".repeat(width))
      else: result.add(&"\e[48;5;{color}m" & " ".repeat(width) & "\e[0m")

proc digitsOnly(value: string): string =
  for ch in value:
    if ch in {'0'..'9'}: result.add(ch)

proc ansiColor(value: string): string =
  if value == "reset" or value == "0": return "\e[0m"
  if value == "distro" or value.len == 0: return "\e[37m"
  try:
    let color = parseInt(value)
    if color < 8: return &"\e[3{color}m"
    if color < 16: return &"\e[9{color - 8}m"
    if color <= 255: return &"\e[38;5;{color}m"
  except ValueError: discard
  "\e[37m"

proc withBar(value: string, width = 15, colored = true, elapsedChar = "=", totalChar = "-", border = true, elapsedColor = "7", totalColor = "7"): string =
  let marker = value.find('%')
  try:
    var percent: int
    if marker > 0:
      let open = value.rfind('(')
      percent = if open >= 0: parseInt(value[open + 1 ..< marker]) else: parseInt(value[0 ..< marker])
    else:
      let slash = value.find(" / ")
      if slash < 1: return value
      let used = parseInt(digitsOnly(value[0 ..< slash]))
      let total = parseInt(digitsOnly(value[slash + 3 .. ^1]))
      if total <= 0: return value
      percent = (used * 100) div total
    percent = max(0, min(100, percent))
    let elapsed = (percent * width) div 100
    let inside = elapsedChar.repeat(elapsed) & totalChar.repeat(width - elapsed)
    let bar = if border: "[" & inside & "]" else: inside
    if colored:
      let elapsedPart = elapsedChar.repeat(elapsed)
      let totalPart = totalChar.repeat(width - elapsed)
      let elapsedAnsi = ansiColor(elapsedColor)
      let totalAnsi = ansiColor(totalColor)
      if border:
        if elapsedAnsi == totalAnsi:
          result = value & " \e[37m[" & inside & "\e[37m]"
        else:
          result = value & " \e[37m[" & elapsedAnsi & elapsedPart & totalAnsi & totalPart & "\e[37m]"
      else:
        if elapsedAnsi == totalAnsi:
          result = value & " " & elapsedAnsi & inside & "\e[37m"
        else:
          result = value & " " & elapsedAnsi & elapsedPart & totalAnsi & totalPart & "\e[37m"
    else:
      result = value & " " & bar
  except ValueError:
    result = value

proc barOnly(value: string, width = 15, colored = true, elapsedChar = "=", totalChar = "-", border = true, elapsedColor = "7", totalColor = "7"): string =
  let combined = withBar(value, width, colored, elapsedChar, totalChar, border, elapsedColor, totalColor)
  if not border:
    let colorStart = combined.find("\e[")
    if colorStart >= 0: return combined[colorStart .. ^1]
    let plainStart = combined.rfind(' ')
    return if plainStart >= 0: combined[plainStart + 1 .. ^1] else: combined
  let ansiMarker = combined.find("\e[37m[")
  if ansiMarker >= 0: return combined[ansiMarker .. ^1]
  let marker = combined.find(" [")
  if marker >= 0: combined[marker + 1 .. ^1] else: ""

proc applyOptions(info: var MachineInfo, options: CliOptions) =
  if options.distroShorthand in ["on", "tiny"] and run("uname -s") == "Darwin":
    let parts = strutils.splitWhitespace(info.os)
    if parts.len >= 4: info.os = &"{parts[0]} {parts[1]} {parts[^1]}"
  if options.kernelShorthand == "off" and run("uname -s") == "Darwin" and not info.kernel.startsWith("Darwin "):
    info.kernel = "Darwin " & info.kernel
  if not options.titleFqdn and run("uname -s") != "Darwin" and info.hostname.contains('.'):
    info.hostname = info.hostname.split('.')[0]
  if not options.osArch:
    let parts = info.os.rsplit(' ', 1)
    if parts.len == 2: info.os = parts[0]
  if not options.shellVersion:
    info.shell = info.shell.split(' ')[0]
  if options.shellPath:
    let path = getEnv("SHELL", "")
    if path.len > 0:
      let version = if options.shellVersion and info.shell.contains(' '): info.shell.split(' ', 1)[1] else: ""
      info.shell = path & (if version.len > 0: " " & version else: "")
  if options.ipInterface.len > 0 and run("uname -s") == "Darwin":
    let value = run(&"ipconfig getifaddr {options.ipInterface} 2>/dev/null")
    if value.len > 0: info.localIp = value
  if options.ipHost.len > 0:
    info.publicIp = getPublicIp(options.ipHost, options.ipTimeout)
  elif options.travis or "public_ip" in options.selected:
    info.publicIp = getPublicIp("http://ident.me", 2)
  if (options.travis or "song" in options.selected) and info.song == unavailable:
    info.song = "Unknown Artist - Unknown Album - Unknown Song"
  if options.packageManagers == "off":
    let marker = info.packages.find(" (")
    if marker >= 0: info.packages = info.packages[0 ..< marker]
  if options.uptimeShorthand == "tiny":
    info.uptime = info.uptime.replace(",", "").replace(" days", "d").replace(" day", "d")
    info.uptime = info.uptime.replace(" hours", "h").replace(" hour", "h")
    info.uptime = info.uptime.replace(" mins", "m").replace(" min", "m")
  elif options.uptimeShorthand == "off":
    if info.uptime.contains(" mins"):
      info.uptime = info.uptime.replace(" mins", " minutes")
    elif info.uptime.contains(" min"):
      info.uptime = info.uptime.replace(" min", " minute")
  if not options.diskPercent and info.disk.contains(" ("):
    info.disk = info.disk.split(" (")[0]
  if options.diskShow.len > 0:
    info.disk = diskAt(options.diskShow)
  if not options.diskPercent and info.disk.contains(" ("):
    info.disk = info.disk.split(" (")[0]
  if info.memory.contains("MiB"):
    let parts = info.memory.replace("MiB", "").split(" / ")
    if parts.len == 2:
      try:
        let used = parseInt(parts[0])
        let total = parseInt(parts[1])
        if options.memoryUnit == "gib":
          info.memory = &"{formatFloat(used.float / 1024, ffDecimal, 2)}GiB / {formatFloat(total.float / 1024, ffDecimal, 2)}GiB"
        else:
          let unit = if options.memoryUnit == "kib": "KiB" else: "MiB"
          let multiplier = if options.memoryUnit == "kib": 1024 else: 1
          info.memory = &"{used * multiplier}{unit} / {total * multiplier}{unit}"
        if options.memoryPercent: info.memory &= &" ({(used * 100) div total}%)"
      except ValueError: discard
  let memoryMode = if options.travis and options.memoryDisplay == "off": "infobar" else: options.memoryDisplay
  let diskMode = if options.travis and options.diskDisplay == "off": "infobar" else: options.diskDisplay
  let batteryMode = if options.travis and options.batteryDisplay == "off": "off" else: options.batteryDisplay
  let coloredBars = options.selected.len == 0
  if memoryMode == "bar": info.memory = barOnly(info.memory, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal)
  elif memoryMode == "infobar": info.memory = withBar(info.memory, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal)
  elif memoryMode == "barinfo": info.memory = barOnly(info.memory, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal) & " " & info.memory
  if diskMode == "bar": info.disk = barOnly(info.disk, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal)
  elif diskMode == "infobar": info.disk = withBar(info.disk, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal)
  elif diskMode == "barinfo": info.disk = barOnly(info.disk, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal) & " " & info.disk
  if batteryMode == "bar": info.battery = barOnly(info.battery, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal)
  elif batteryMode == "infobar": info.battery = withBar(info.battery, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal)
  elif batteryMode == "barinfo": info.battery = barOnly(info.battery, options.barLength, coloredBars, options.barElapsed, options.barTotal, options.barBorder, options.barColorElapsed, options.barColorTotal) & " " & info.battery

proc printHuman(info: MachineInfo, options: CliOptions) =
  if options.logoOnly and options.plain:
    echo ""
    echo ""
    return
  var lines: seq[string]
  var configuredFields: seq[(string, string)]
  var effectiveOptions = options
  let cliLogo = options.logo
  if effectiveOptions.selected.len > 0:
    effectiveOptions.plain = true
  if effectiveOptions.plain:
    effectiveOptions.colorBlocks = false
    effectiveOptions.logo = "none"
    effectiveOptions.logoOnly = false
  if effectiveOptions.logoOnly:
    effectiveOptions.colorBlocks = false
  if options.configPath.len > 0 and not options.noConfig:
    # parseOptions already applied the config before CLI arguments.  Capture
    # the configured print_info fields here without applying the config again;
    # reapplying it would incorrectly make config values override CLI flags.
    var configCaptureOptions = effectiveOptions
    loadConfig(options.configPath, configuredFields, configCaptureOptions)
  if effectiveOptions.plain:
    effectiveOptions.logo = "none"
    effectiveOptions.colorBlocks = false
  elif cliLogo.len > 0:
    effectiveOptions.logo = cliLogo
  if not effectiveOptions.logoOnly and effectiveOptions.selected.len == 0:
    if effectiveOptions.plain:
      lines.add(&"{info.username}@{info.hostname}")
      if effectiveOptions.underline:
        lines.add(effectiveOptions.underlineChar.repeat(displayWidth(&"{info.username}@{info.hostname}")))
    else:
      let bold = if effectiveOptions.bold: "\e[1m" else: ""
      lines.add(ansiColor(effectiveOptions.titleColor) & bold & info.username & ansiColor(effectiveOptions.atColor) & "@" & bold & info.hostname & "\e[0m")
      if effectiveOptions.underline:
        lines.add(ansiColor(effectiveOptions.underlineColor) & effectiveOptions.underlineChar.repeat(displayWidth(&"{info.username}@{info.hostname}")) & "\e[0m")
    var fields: seq[(string, string)]
    if configuredFields.len > 0:
      fields = configuredFields
    else:
      for item in defaultFields: fields.add(item)
    if effectiveOptions.hardwareDetails:
      fields.add(("CPU Details", "cpu_details"))
      fields.add(("GPU Details", "gpu_details"))
      fields.add(("Memory Details", "memory_details"))
      fields.add(("Disk Details", "disk_details"))
      fields.add(("External Devices", "external_devices"))
    if effectiveOptions.travis:
      var reordered: seq[(string, string)]
      for item in fields:
        if item[1] == "memory": reordered.add(("GPU Driver", "gpu_driver"))
        reordered.add(item)
      fields = reordered
      for item in extendedFields:
        if item[1] != "gpu_driver": fields.add(item)
    let diskPath = if effectiveOptions.diskShow.len > 0: effectiveOptions.diskShow else: "/"
    let diskName = if effectiveOptions.diskSubtitle == "dir": diskPath.splitPath.tail else: diskPath
    let diskLabel = if effectiveOptions.diskSubtitle == "none": "Disk" else: &"Disk ({diskName})"
    for item in fields:
      let label = if effectiveOptions.travis and item[1] == "disk": diskLabel else: item[0]
      addInfo(lines, info, label, item[1], effectiveOptions)
    if effectiveOptions.travis:
      lines.add("prin")
      lines.add("prin: prin")
      lines.add(info.uptime)
      lines.add(&"/{effectiveOptions.separator} {info.disk}")
  elif not effectiveOptions.logoOnly:
    for key in effectiveOptions.selected:
      let selectedDiskPath = if effectiveOptions.diskShow.len > 0: effectiveOptions.diskShow else: "/"
      let selectedDiskLabel = if effectiveOptions.diskSubtitle == "none": "disk" else: &"disk ({selectedDiskPath})"
      let label = if key == "disk": selectedDiskLabel else: key
      addInfo(lines, info, label, key, effectiveOptions)
  if not effectiveOptions.logoOnly and effectiveOptions.selected.len == 0 and effectiveOptions.colorBlocks:
    lines.add("")
    lines.add(getColorBlocks(effectiveOptions.plain, effectiveOptions))
  if effectiveOptions.travis:
    lines.insert("", 0)
  let logo = if effectiveOptions.logoOnly or (effectiveOptions.selected.len == 0 and effectiveOptions.logo != "none"):
    getLogo(effectiveOptions.plain, effectiveOptions.logo, effectiveOptions.backend, effectiveOptions.asciiBold,
      effectiveOptions.asciiColors, effectiveOptions.imageSize, effectiveOptions.catimgSize,
      effectiveOptions.cropMode, effectiveOptions.cropOffset, effectiveOptions.xOffset,
      effectiveOptions.yOffset, effectiveOptions.backgroundColor)
    else: @[]
  var logoWidth = 0
  for line in logo: logoWidth = max(logoWidth, displayWidth(line))
  for index in 0 ..< max(logo.len, lines.len):
    let left = if index < logo.len: logo[index] else: ""
    let padding = if logo.len == 0 or effectiveOptions.logoOnly: 0 else: max(1, logoWidth + effectiveOptions.gap - displayWidth(left))
    echo left & " ".repeat(padding) & (if index < lines.len: lines[index] else: "")
  if effectiveOptions.selected.len == 0 and not effectiveOptions.logoOnly:
    echo ""

proc main() =
  var options = parseOptions()
  if options.help:
    if run("command -v curl 2>/dev/null").len > 0:
      let officialHelp = runOutput("curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch | bash -s -- --help 2>/dev/null")
      if officialHelp.len > 0:
        stdout.write(officialHelp)
        return
    echo "Usage: sysfetch [options] [function ...]"
    echo "  --json                 Output structured machine information as JSON"
    echo "  --stdout, --pipe       Disable ANSI colors and image output"
    echo "  --disable field ...    Hide fields such as cpu, gpu, memory"
    echo "  --config path          Read simple Neofetch-compatible settings"
    echo "  --no_config            Ignore configuration files"
    echo "  --print_config         Print the generated default configuration"
    echo "  -L, --logo             Show only the ASCII logo"
    echo "  --logo none            Disable the ASCII logo"
    echo "  --source path          Use a custom ASCII file"
    echo "  --travis               Enable extended collectors and infobars"
    echo "  --separator value      Change the field separator"
    echo "  --colors x x x x x x   Set title, separator, subtitle and info colors"
    echo "  --bold on/off          Enable or disable bold text"
    echo "  --underline on/off     Enable or disable the title underline"
    echo "  --underline_char char  Change the underline character"
    echo "  --color_blocks on/off  Toggle color blocks"
    echo "  --block_width N        Set color block width"
    echo "  --block_height N       Set color block height"
    echo "  --block_range A B      Set color block range"
    echo "  --bar_char elapsed total  Set progress bar characters"
    echo "  --bar_border on/off    Toggle progress bar borders"
    echo "  --bar_length N         Set progress bar length"
    echo "  --bar_colors elapsed total  Set progress bar colors"
    echo "  --memory_display mode  Use off, bar, infobar or barinfo"
    echo "  --disk_display mode    Use off, bar, infobar or barinfo"
    echo "  --battery_display mode Use off, bar, infobar or barinfo"
    echo "  --ascii_distro name    Use a Neofetch distro logo"
    echo "  --ascii_colors ...     Override ASCII logo colors"
    echo "  --ascii_bold on/off    Toggle ASCII logo bold text"
    echo "  --gap N                Set logo-to-info spacing"
    echo "  --hardware              Show CPU/GPU/memory/disk hardware details"
    return
  if options.clean:
    return
  if options.genMan:
    echo ".TH SYSFETCH 1"
    echo ".SH NAME"
    echo "sysfetch - display system information"
    echo ".SH SYNOPSIS"
    echo "sysfetch [options] [function ...]"
    return
  if options.version:
    echo "sysfetch 7.1.0 (Nim compatibility)"
    return
  if options.printConfig:
    if run("command -v curl 2>/dev/null").len > 0:
      let officialConfig = runOutput("curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch | bash -s -- --print_config 2>/dev/null")
      if officialConfig.len > 0:
        stdout.write(officialConfig)
        return
    echo "print_info() {"
    for item in defaultFields:
      echo &"    info \"{item[0]}\" {item[1]}"
    echo "}"
    return
  var info = collect()
  applyOptions(info, options)
  if options.json:
    if options.configPath.len > 0 and not options.noConfig and not options.travis:
      var configFields: seq[(string, string)]
      var configOptions = options
      loadConfig(options.configPath, configFields, configOptions)
      if configFields.len > 0: echo toConfiguredJson(info, configFields).pretty(4)
      else: echo toJson(info, false, options.hardwareDetails).pretty(4)
    else:
      echo toJson(info, options.travis, options.hardwareDetails).pretty(4)
  else:
    printHuman(info, options)

when isMainModule:
  main()
