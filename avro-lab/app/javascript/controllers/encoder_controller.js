import { Controller } from "@hotwired/stimulus"

// Encode-and-download lab behavior: POST the editor JSON to the server,
// download the artifact, and time three phases — server encode, client
// download of the response body, client decode (Avro container decode or
// JSON.parse for the baseline). Each run renders a timeline bar with a
// colored segment per phase; full numbers go to the console.
//
//   <div data-controller="encoder">
//     <textarea data-encoder-target="jsonText"></textarea>
//     <input type="range" data-encoder-target="repeats">
//     <output data-encoder-target="repeatOutput"></output>
//     <button data-action="encoder#encodeJson">…</button>
//     <button data-action="encoder#encodeAvro">…</button>
//     <div data-encoder-target="status"></div>
//   </div>
export default class extends Controller {
  static targets = ["jsonText", "repeats", "repeatOutput", "jsonButton", "avroButton", "status"]

  connect() {
    this.statusTarget.replaceChildren()
    this.timeline = new Timeline(this.statusTarget)
  }

  encodeJson() {
    this.encode("json")
  }

  encodeAvro() {
    this.encode("avro")
  }

  syncRepeats() {
    // Throttle the drag: update the output immediately when the input events
    // are far apart, otherwise batch trailing updates at ~40ms so a fast drag
    // over the 100k range doesn't spam the DOM.
    const now = performance.now()
    if (this.syncTimer !== undefined) return
    if (this.syncLast === undefined || now - this.syncLast >= SYNC_THROTTLE_MS) {
      this.syncLast = now
      this.renderRepeat()
    } else {
      this.syncTimer = setTimeout(() => {
        this.syncTimer = undefined
        this.syncLast = performance.now()
        this.renderRepeat()
      }, SYNC_THROTTLE_MS - (now - this.syncLast))
    }
  }

  renderRepeat() {
    this.repeatOutputTarget.textContent = this.repeatsTarget.value
  }

  async encode(format) {
    if (this.busy) return
    const sourceText = this.jsonTextTarget.value
    const repeats = String(this.repeatsTarget.value)

    try {
      JSON.parse(sourceText)
    } catch (error) {
      this.timeline.addRun({ format, repeats, error: `Invalid JSON: ${error.message}` })
      return
    }

    this.setBusy(true)
    try {
      const response = await fetch("/encoding", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/octet-stream, application/json, text/plain",
          "X-CSRF-Token": csrfToken()
        },
        body: JSON.stringify({ encoding: { json_text: sourceText, repeats, format } })
      })
      if (!response.ok) {
        throw new Error(await errorMessage(response))
      }

      const encodeMs = Number(response.headers.get("X-Encode-Ms") || "0")
      const transferStarted = performance.now()
      const bytes = await response.arrayBuffer()
      const transferMs = performance.now() - transferStarted

      const segments = [
        { key: "encode", label: "encode", ms: encodeMs },
        { key: "download", label: "download", ms: transferMs }
      ]
      const meta = { bytes: bytes.byteLength }

      if (format === "avro") {
        // Keep the .avro download inside the user gesture. The decoded JSON
        // download happens right after decoding and may be blocked by the
        // browser (post-await), which the network tab will show.
        download(bytes, `payload-${repeats}.avro`, "application/octet-stream")
        const details = await this.decodeAvro(bytes, sourceText, repeats)
        download(details.prettyDecoded, `payload-${repeats}-decoded.json`)
        segments.push({ key: "decode", label: "decode", ms: details.decodeMs })
        Object.assign(meta, { count: details.count, match: details.match })
      } else {
        const text = new TextDecoder().decode(bytes)
        const parseStarted = performance.now()
        const parsed = JSON.parse(text)
        const parseMs = performance.now() - parseStarted
        segments.push({ key: "decode", label: "parse", ms: parseMs })
        Object.assign(meta, {
          count: Array.isArray(parsed) ? parsed.length : null,
          match: JSON.stringify(parsed) === JSON.stringify(repeatArray(sourceText, repeats))
        })
        download(bytes, `payload-${repeats}.json`, "application/json")
      }

      this.timeline.addRun({ format, repeats, segments, meta })
    } catch (error) {
      this.timeline.addRun({ format, repeats, error: error.message })
    } finally {
      this.setBusy(false)
    }
  }

  async decodeAvro(bytes, sourceText, repeats) {
    const decodeStarted = performance.now()
    const { records, count } = await window.avrojs.decodeContainer(bytes)
    const decodeMs = performance.now() - decodeStarted

    const decoded = JSON.stringify(records)
    const expected = JSON.stringify(repeatArray(sourceText, repeats))
    const match = decoded === expected && count === Number(repeats)
    if (!match) {
      console.warn("[avro-lab] decoded JSON does not match the source", { expected, decoded })
    }

    // Pretty-printed like the server's JSON download so both artifacts are
    // byte-comparable; the compact string above is only for the match check.
    const prettyDecoded = JSON.stringify(records, null, 2)
    return { decodeMs, count, match, prettyDecoded }
  }

  setBusy(busy) {
    this.busy = busy
    this.jsonButtonTarget.disabled = busy
    this.avroButtonTarget.disabled = busy
    this.statusTarget.classList.toggle("is-busy", busy)
  }
}

function repeatArray(sourceText, repeats) {
  const value = JSON.parse(sourceText)
  return Array.from({ length: Number(repeats) }, () => value)
}

function formatBytes(bytes) {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(2)} MB`
  if (bytes >= 1e3) return `${(bytes / 1e3).toFixed(1)} KB`
  return `${bytes} B`
}

function download(data, filename, type) {
  if (type === undefined) {
    type = typeof data === "string" ? "application/json" : "application/octet-stream"
  }
  const blob = new Blob([data], { type })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement("a")
  anchor.href = url
  anchor.download = filename
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}

async function errorMessage(response) {
  try {
    const body = await response.json()
    return body.error || `HTTP ${response.status}`
  } catch {
    return `HTTP ${response.status}`
  }
}

function csrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta ? meta.content : ""
}

const MAX_RUNS = 12
const BAR_MAX_WIDTH = 560
const SYNC_THROTTLE_MS = 40

class Timeline {
  constructor(container) {
    this.container = container
    this.runs = []
    this.container.appendChild(this.legend())
  }

  addRun(run) {
    const normalized = this.normalize(run)
    // One bar per (format, repeats): replacing an earlier identical run keeps
    // the timeline comparable (AVRO x100 + JSON x100) instead of piling up
    // duplicates from repeated clicks.
    this.runs = this.runs.filter((prev) => !(prev.format === run.format && prev.repeats === run.repeats))
    this.runs.unshift(normalized)
    this.runs = this.runs.slice(0, MAX_RUNS)
    console.log(`[avro-lab] ${run.format} x${run.repeats}`, run)
    this.render()
  }

  normalize(run) {
    return {
      ...run,
      formatLabel: run.format.toUpperCase(),
      totalMs: () => run.error ? 0 : run.segments.reduce((sum, segment) => sum + segment.ms, 0)
    }
  }

  legend() {
    const legend = document.createElement("div")
    legend.className = "timeline__legend"
    legend.innerHTML = `
      <span class="legend__item"><i class="legend__swatch legend__swatch--encode"></i>encode (server)</span>
      <span class="legend__item"><i class="legend__swatch legend__swatch--download"></i>download (client)</span>
      <span class="legend__item"><i class="legend__swatch legend__swatch--decode"></i>decode (client)</span>
      <span class="legend__note">bar width ∝ total ms · sub-millisecond segments floored to stay visible · decode = Avro container decode, or JSON.parse for the baseline</span>`
    return legend
  }

  render() {
    const legend = this.container.firstChild
    this.container.replaceChildren(legend)
    const maxTotal = Math.max(...this.runs.map((run) => run.totalMs()), 1)
    const scale = BAR_MAX_WIDTH / maxTotal
    this.runs.forEach((run) => this.container.appendChild(this.barFor(run, scale)))
  }

  barFor(run, scale) {
    const wrapper = document.createElement("div")
    wrapper.className = "run-bar"

    if (run.error) {
      const pill = document.createElement("div")
      pill.className = "run-bar__error"
      pill.textContent = `${run.formatLabel} x${run.repeats} — failed: ${run.error}`
      wrapper.appendChild(pill)
      return wrapper
    }

    const label = document.createElement("div")
    label.className = "run-bar__label"
    label.textContent = `${run.formatLabel} ×${run.repeats}`
    if (run.meta.bytes !== undefined || run.meta.count !== undefined) {
      label.title = [run.meta.bytes !== undefined ? formatBytes(run.meta.bytes) : null, run.meta.count !== null && run.meta.count !== undefined ? `${run.meta.count} records` : null].filter(Boolean).join(" · ")
    }
    if (run.meta.match !== undefined) {
      const badge = document.createElement("span")
      badge.className = `run-bar__badge ${run.meta.match ? "run-bar__badge--ok" : "run-bar__badge--bad"}`
      badge.textContent = run.meta.match ? "✓" : "✗"
      label.appendChild(document.createTextNode(" "))
      label.appendChild(badge)
    }

    const track = document.createElement("div")
    track.className = "run-bar__track"
    run.segments.forEach((segment) => {
      const segmentEl = document.createElement("div")
      segmentEl.className = `run-bar__seg run-bar__seg--${segment.key}`
      segmentEl.style.width = `${Math.max(2, segment.ms * scale)}px`
      segmentEl.title = `${segment.label}: ${segment.ms.toFixed(2)} ms`
      track.appendChild(segmentEl)
    })

    wrapper.append(label, track)
    return wrapper
  }
}