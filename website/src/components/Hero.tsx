import { FormEvent, useEffect, useRef, useState } from 'react'
import { ArrowDown, Send } from 'lucide-react'
import Wattson, { MOOD_LINE, Mood } from './Wattson'

const SPOTLIGHT_R = 260

/** Deterministic pseudo-random smoke blob layout so SSR/CSR match. */
const SMOKE_BLOBS = Array.from({ length: 9 }, (_, i) => ({
  left: (i * 137.5) % 100,
  bottom: -8 + ((i * 53) % 30),
  size: 130 + ((i * 97) % 200),
  dur: 13 + ((i * 41) % 10),
  delay: -((i * 29) % 14),
  dx: ((i * 67) % 120) - 60,
  peak: 0.25 + ((i * 31) % 28) / 100,
}))

interface Reaction {
  id: number
  grams: number
  label: string
}

function quipFor(grams: number): string {
  if (grams < 2.5) return 'barely a breeze 🍃'
  if (grams < 18) return 'felt that one 😮‍💨'
  return 'tell the GPUs I’m sorry 🥵'
}

export default function Hero() {
  // --- cursor spotlight with smoothing ---
  const mouse = useRef({ x: -999, y: -999 })
  const smooth = useRef({ x: -999, y: -999 })
  const rafRef = useRef<number>(0)
  const [cursorPos, setCursorPos] = useState({ x: -999, y: -999 })

  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      mouse.current = { x: e.clientX, y: e.clientY }
    }
    window.addEventListener('mousemove', onMove)
    const tick = () => {
      smooth.current.x += (mouse.current.x - smooth.current.x) * 0.1
      smooth.current.y += (mouse.current.y - smooth.current.y) * 0.1
      setCursorPos({ x: smooth.current.x, y: smooth.current.y })
      rafRef.current = requestAnimationFrame(tick)
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => {
      window.removeEventListener('mousemove', onMove)
      cancelAnimationFrame(rafRef.current)
    }
  }, [])

  // --- prompt simulator ---
  const [prompt, setPrompt] = useState('')
  const [sessionGrams, setSessionGrams] = useState(0)
  const [reaction, setReaction] = useState<Reaction | null>(null)

  const mood: Mood =
    sessionGrams < 6 ? 'thriving' : sessionGrams < 16 ? 'content' : sessionGrams < 32 ? 'sluggish' : 'sooty'

  const simulate = (e: FormEvent) => {
    e.preventDefault()
    const text = prompt.trim()
    if (!text) return
    const inputTokens = Math.max(8, Math.ceil(text.length / 4))
    const outputTokens = Math.min(2000, 120 + text.length * 2)
    // Rough EcoLogits-shaped figure for a frontier chat model; the app does this properly.
    const grams = +(0.9 + outputTokens * 0.011 + inputTokens * 0.0008).toFixed(1)
    setReaction({ id: Date.now(), grams, label: quipFor(grams) })
    setSessionGrams((total) => +(total + grams).toFixed(1))
    setPrompt('')
  }

  const smogExtra = Math.min(0.4, sessionGrams * 0.011)

  return (
    <section className="relative w-full overflow-hidden bg-[#141417]" style={{ height: '100dvh' }}>
      {/* z-10: the smog — base layer */}
      <div className="absolute inset-0 z-10 bg-gradient-to-b from-[#1b1b20] via-[#141417] to-[#0d0d10]">
        {SMOKE_BLOBS.map((blob, i) => (
          <div
            key={i}
            className="smoke-blob absolute rounded-full bg-gray-400/30 blur-3xl"
            style={{
              left: `${blob.left}%`,
              bottom: `${blob.bottom}%`,
              width: blob.size,
              height: blob.size * 0.8,
              ['--smoke-dur' as string]: `${blob.dur}s`,
              ['--smoke-delay' as string]: `${blob.delay}s`,
              ['--smoke-dx' as string]: `${blob.dx}px`,
              ['--smoke-peak' as string]: blob.peak,
            }}
          />
        ))}
      </div>

      {/* z-20: smog thickens as the demo session emits more */}
      <div
        className="pointer-events-none absolute inset-0 z-20 bg-black transition-opacity duration-1000"
        style={{ opacity: smogExtra }}
      />

      {/* z-30: clean air revealed by the cursor spotlight */}
      <RevealLayer cursorX={cursorPos.x} cursorY={cursorPos.y}>
        <div className="h-full w-full bg-gradient-to-b from-[#10382a] via-[#0e2e23] to-[#0a221a]">
          <div className="absolute left-[20%] top-[18%] h-64 w-64 rounded-full bg-emerald-400/25 blur-3xl" />
          <div className="absolute right-[18%] top-[40%] h-48 w-48 rounded-full bg-teal-300/20 blur-3xl" />
          {Array.from({ length: 14 }, (_, i) => (
            <span
              key={i}
              className="absolute text-emerald-300/70"
              style={{
                left: `${(i * 71) % 100}%`,
                top: `${(i * 37) % 100}%`,
                fontSize: 8 + ((i * 13) % 8),
              }}
            >
              ✦
            </span>
          ))}
        </div>
      </RevealLayer>

      {/* z-50: heading */}
      <div className="pointer-events-none absolute left-0 right-0 top-[10%] z-50 flex flex-col items-center px-5 text-center">
        <h1 className="text-white leading-[0.95]">
          <span
            className="hero-anim hero-reveal font-playfair block text-4xl italic sm:text-6xl md:text-7xl"
            style={{ letterSpacing: '-0.05em', animationDelay: '0.25s' }}
          >
            Your AI footprint,
          </span>
          <span
            className="hero-anim hero-reveal -mt-1 block text-4xl font-normal sm:text-6xl md:text-7xl"
            style={{ letterSpacing: '-0.08em', animationDelay: '0.42s' }}
          >
            sitting on your desktop.
          </span>
        </h1>
        <p
          className="hero-anim hero-fade mt-4 max-w-md text-sm text-white/70"
          style={{ animationDelay: '0.6s' }}
        >
          Move your cursor to clear the smog. Then make Wattson earn its keep below.
        </p>
      </div>

      {/* z-50: the pet + prompt simulator */}
      <div className="absolute left-1/2 top-[40%] z-50 flex -translate-x-1/2 flex-col items-center">
        <div className="hero-anim hero-fade" style={{ animationDelay: '0.7s' }}>
          <Wattson mood={mood} reaction={reaction} size={170} />
          <p className="mt-1 text-center text-xs font-medium text-white/75">{MOOD_LINE[mood]}</p>
        </div>

        <form
          onSubmit={simulate}
          className="hero-anim hero-fade mt-5 flex w-[88vw] max-w-md items-center gap-2 rounded-full border border-white/20 bg-white/10 py-1.5 pl-5 pr-1.5 backdrop-blur-md"
          style={{ animationDelay: '0.85s' }}
        >
          <input
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder="Type a pretend prompt to see its cost…"
            className="w-full bg-transparent text-sm text-white placeholder:text-white/45 focus:outline-none"
            aria-label="Try a pretend prompt"
          />
          <button
            type="submit"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-emerald-500 text-white transition-all hover:bg-emerald-400 active:scale-95"
            aria-label="Estimate this prompt"
          >
            <Send size={15} />
          </button>
        </form>
        <p className="mt-2 text-[11px] text-white/45">
          Demo estimate only — session total {sessionGrams.toFixed(1)} g · the app uses real token counts
        </p>
      </div>

      {/* z-50: bottom-left privacy line */}
      <div
        className="hero-anim hero-fade absolute bottom-10 left-10 z-50 hidden max-w-[270px] md:block lg:left-14"
        style={{ animationDelay: '0.95s' }}
      >
        <p className="text-sm leading-relaxed text-white/80">
          Sootling watches token counts, never words. Your prompts stay yours — the pet only feels
          their weight.
        </p>
      </div>

      {/* z-50: bottom-right CTA block */}
      <div
        className="hero-anim hero-fade absolute bottom-6 left-5 right-5 z-50 flex max-w-full flex-col items-center gap-4 sm:bottom-10 sm:left-auto sm:right-10 sm:max-w-[280px] sm:items-start md:right-14"
        style={{ animationDelay: '1.05s' }}
      >
        <p className="hidden text-sm leading-relaxed text-white/80 md:block">
          A tiny mossy critter for your Mac that turns invisible AI emissions into something you can
          feel.
        </p>
        <div className="flex flex-wrap items-center gap-3">
          <a
            href="/Sootling-0.1.0.dmg"
            download
            className="rounded-full bg-emerald-500 px-7 py-3 text-sm font-medium text-white transition-all hover:scale-[1.03] hover:bg-emerald-400 hover:shadow-lg hover:shadow-emerald-500/30 active:scale-95"
          >
            Download for macOS
          </a>
          <a
            href="#methodology"
            className="text-sm text-white/70 underline-offset-4 transition-colors hover:text-white hover:underline"
          >
            Read methodology
          </a>
        </div>
      </div>

      {/* scroll hint */}
      <a
        href="#what"
        aria-label="Scroll to learn more"
        className="float-slow absolute bottom-4 left-1/2 z-50 -translate-x-1/2 text-white/50 transition-colors hover:text-white"
      >
        <ArrowDown size={18} />
      </a>
    </section>
  )
}

/** Reveals its children only inside a soft circular spotlight that trails the cursor. */
function RevealLayer({
  cursorX,
  cursorY,
  children,
}: {
  cursorX: number
  cursorY: number
  children: React.ReactNode
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const layerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const resize = () => {
      const canvas = canvasRef.current
      if (!canvas) return
      canvas.width = window.innerWidth
      canvas.height = window.innerHeight
    }
    resize()
    window.addEventListener('resize', resize)
    return () => window.removeEventListener('resize', resize)
  }, [])

  useEffect(() => {
    const canvas = canvasRef.current
    const layer = layerRef.current
    if (!canvas || !layer) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    ctx.clearRect(0, 0, canvas.width, canvas.height)
    const gradient = ctx.createRadialGradient(cursorX, cursorY, 0, cursorX, cursorY, SPOTLIGHT_R)
    gradient.addColorStop(0, 'rgba(255,255,255,1)')
    gradient.addColorStop(0.4, 'rgba(255,255,255,1)')
    gradient.addColorStop(0.6, 'rgba(255,255,255,0.75)')
    gradient.addColorStop(0.75, 'rgba(255,255,255,0.4)')
    gradient.addColorStop(0.88, 'rgba(255,255,255,0.12)')
    gradient.addColorStop(1, 'rgba(255,255,255,0)')
    ctx.fillStyle = gradient
    ctx.beginPath()
    ctx.arc(cursorX, cursorY, SPOTLIGHT_R, 0, Math.PI * 2)
    ctx.fill()

    const url = canvas.toDataURL()
    layer.style.maskImage = `url(${url})`
    layer.style.webkitMaskImage = `url(${url})`
    layer.style.maskSize = '100% 100%'
    layer.style.webkitMaskSize = '100% 100%'
    layer.style.maskRepeat = 'no-repeat'
  }, [cursorX, cursorY])

  return (
    <>
      <canvas
        ref={canvasRef}
        className="pointer-events-none absolute inset-0"
        style={{ display: 'none' }}
      />
      <div ref={layerRef} className="pointer-events-none absolute inset-0 z-30">
        {children}
      </div>
    </>
  )
}
