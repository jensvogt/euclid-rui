pragma Singleton
import QtQuick

// EAP's per-instance limits - memoryLimitMb and cpuLimit on an application - read, written and
// explained the same way on every page that shows them. The rules are the server's
// (Entity::EAP::LimitRefusal / CpuLimitRefusal) and the CLI's ("512M", "2G", "1.5G"), so what this
// accepts is what set-application-limits accepts.
//
// See docs/resource-limits.md in the euclid repository for the whole of it.
QtObject {
    id: limits
    // Below these nothing starts (a JVM reserves more than 64 MiB before it loads a class), and
    // cpu.max cannot be given less than 1 ms of a 100 ms period. 0 is always allowed: no limit.
    readonly property int minimumMemoryMb: 64
    readonly property real minimumCpu: 0.01

    // What the worker hands a JVM under an enforced limit, unless the application sizes its heap
    // itself - euclid.worker.java-max-ram-percent in euclid-wrk(8).
    readonly property int javaMaxRamPercent: 75

    // "512", "512M", "2G", "1.5G", "2048 MiB" - into MiB. Empty is 0, no limit. NaN for anything
    // that is not a size.
    function parseMemory(text) {
        const t = String(text === undefined || text === null ? "" : text).trim().toUpperCase().replace(/\s+/g, "")
        if (t.length === 0) return 0
        const m = /^(\d+(?:\.\d+)?)(M|MB|MIB|G|GB|GIB)?$/.exec(t)
        if (!m) return NaN
        const n = Number(m[1])
        const giga = m[2] !== undefined && m[2].charAt(0) === "G"
        return Math.round(giga ? n * 1024 : n)
    }

    // Empty is 0, no limit; NaN for anything that is not a number.
    function parseCpu(text) {
        const t = String(text === undefined || text === null ? "" : text).trim()
        if (t.length === 0) return 0
        if (!/^\d+(?:\.\d+)?$/.test(t)) return NaN
        return Number(t)
    }

    // Why a memory limit would be refused, or empty. In the server's terms.
    function memoryProblem(mb) {
        if (isNaN(mb)) return "The memory limit has to be a size: 512, 512M, 2G or 1.5G. Empty or 0 for none."
        if (mb < 0) return "The memory limit cannot be negative."
        if (mb > 0 && mb < limits.minimumMemoryMb)
            return "A memory limit below " + limits.minimumMemoryMb + " MiB kills every instance on start. 0 removes the limit."
        return ""
    }

    function cpuProblem(cores) {
        if (isNaN(cores)) return "The CPU limit has to be a number of cores: 0.5, 1.5, 4. Empty or 0 for none."
        if (cores < 0) return "The CPU limit cannot be negative."
        if (cores > 0 && cores < limits.minimumCpu)
            return "A CPU limit below " + limits.minimumCpu + " cores cannot be enforced. 0 removes the limit."
        return ""
    }

    // What goes back into a field: "2G" for whole GiB, MiB otherwise, "" for none.
    function memoryInput(mb) {
        const n = Number(mb)
        if (!(n > 0)) return ""
        return n % 1024 === 0 ? (n / 1024) + "G" : n + "M"
    }

    function cpuInput(cores) {
        const n = Number(cores)
        return n > 0 ? String(n) : ""
    }

    // For reading: "2 GiB", "1.5 GiB", "512 MiB", "none".
    function memoryText(mb) {
        const n = Number(mb)
        if (!(n > 0)) return "none"
        if (n >= 1024) {
            const g = n / 1024
            return (Number.isInteger(g) ? g : g.toFixed(2).replace(/0+$/, "")) + " GiB"
        }
        return n + " MiB"
    }

    // A machine's memory in use against what is installed: "64 GiB / 128 GiB". Whole GiB from ten
    // up, where a decimal is noise that changes every renewal; one decimal below that. Just the
    // total when the node sends no used figure (macOS), and "—" when it sends neither.
    function machineMemoryText(usedMb, totalMb) {
        const total = Number(totalMb)
        if (!(total > 0)) return "—"
        const used = Number(usedMb)
        return used > 0 ? gibText(used) + " / " + gibText(total) : gibText(total)
    }

    function gibText(mb) {
        const g = Number(mb) / 1024
        if (g < 1) return Math.round(Number(mb)) + " MiB"
        return (g >= 10 ? Math.round(g) : Math.round(g * 10) / 10) + " GiB"
    }

    // The share of a machine's memory in use, as a whole percentage, or -1 when not reported.
    function machineMemoryPercent(usedMb, totalMb) {
        const total = Number(totalMb)
        const used = Number(usedMb)
        return total > 0 && used > 0 ? Math.round(100 * used / total) : -1
    }

    function cpuText(cores) {
        const n = Number(cores)
        if (!(n > 0)) return "none"
        return n + (n === 1 ? " core" : " cores")
    }

    // Both together, for a card or a column: "2 GiB · 1.5 cores", "2 GiB", "none".
    function summary(mb, cores) {
        const parts = []
        if (Number(mb) > 0) parts.push(limits.memoryText(mb))
        if (Number(cores) > 0) parts.push(limits.cpuText(cores))
        return parts.length > 0 ? parts.join(" · ") : "none"
    }

    function isJavaRuntime(runtime) {
        const r = String(runtime || "").toUpperCase()
        return r === "JAVA" || r === "JAVA21" || r === "JAVA25"
    }

    // The heap flag an application already sets itself, in one of the three variables a JVM reads
    // options from - the worker leaves such an application alone. Empty when there is none.
    // Arguments do not count: they follow the jar and never reach the JVM.
    function ownHeapFlag(environment) {
        const env = environment || {}
        for (const name of ["JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS"]) {
            const value = env[name]
            if (value === undefined || value === null) continue
            for (const option of String(value).split(/\s+/)) {
                if (option.startsWith("-Xmx") || option.startsWith("-XX:MaxHeapSize=")
                        || option.startsWith("-XX:MaxRAMPercentage=") || option.startsWith("-XX:MaxRAM=")
                        || option.startsWith("-XX:MaxRAMFraction="))
                    return name + ": " + option
            }
        }
        return ""
    }

    // What the worker does about the JVM heap for this application, in one line - the same
    // decision ApplicationLaunch::JavaHeapOption() makes on the node. Empty for a runtime that is
    // not a JVM, where there is nothing to say.
    function jvmHeapText(runtime, command, environment, memoryLimitMb) {
        if (!limits.isJavaRuntime(runtime)) return ""
        if (String(command || "").length > 0)
            return "Left alone: the application starts with its own command, so the worker adds no JVM options."
        const own = limits.ownHeapFlag(environment)
        if (own.length > 0)
            return "Sized by the application itself (" + own + "); the worker adds nothing."
        if (!(Number(memoryLimitMb) > 0))
            return "JVM default: a quarter of the host's memory. No flag is added without a limit - an unlimited "
                   + "JVM would take " + limits.javaMaxRamPercent + "% of the whole host."
        const heap = Math.floor(Number(memoryLimitMb) * limits.javaMaxRamPercent / 100)
        return "-XX:MaxRAMPercentage=" + limits.javaMaxRamPercent + " added on nodes that enforce the limit: a heap of about "
               + limits.memoryText(heap) + " of " + limits.memoryText(memoryLimitMb) + "."
    }
}
