import {
  Activity,
  ArrowRight,
  BarChart3,
  Calculator,
  CheckCircle2,
  Circle,
  Cloud,
  Database,
  Download,
  EyeOff,
  Globe,
  HeartPulse,
  Leaf,
  ShieldCheck,
  Terminal,
} from 'lucide-react'
import Hero from './components/Hero'
import Wattson from './components/Wattson'

export default function App() {
  return (
    <div className="min-h-screen bg-[#faf9f5] tracking-[-0.02em]" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Nav />
      <Hero />
      <WhatItDoes />
      <Privacy />
      <HowItWorks />
      <Preview />
      <Methodology />
      <DownloadSection />
      <Roadmap />
      <Footer />
    </div>
  )
}

/* ---------------------------------- nav ---------------------------------- */

function Nav() {
  const links = [
    ['What it does', '#what'],
    ['Privacy', '#privacy'],
    ['How it works', '#how'],
    ['Methodology', '#methodology'],
    ['Roadmap', '#roadmap'],
  ] as const

  return (
    <nav className="fixed left-0 right-0 top-0 z-[100] flex items-center justify-between p-4 sm:p-5">
      <a
        href="#"
        className="flex items-center gap-2 rounded-full border border-white/20 bg-black/30 px-4 py-2 backdrop-blur-md"
      >
        <SootLogo />
        <span className="font-playfair text-xl italic text-white">Sootling</span>
      </a>

      <div className="absolute left-1/2 hidden -translate-x-1/2 items-center gap-1 rounded-full border border-white/25 bg-black/30 px-2 py-2 backdrop-blur-md md:flex">
        {links.map(([label, href]) => (
          <a
            key={href}
            href={href}
            className="rounded-full px-4 py-1.5 text-sm font-medium text-white/80 transition-colors hover:bg-white/20 hover:text-white"
          >
            {label}
          </a>
        ))}
      </div>

      <a
        href="#download"
        className="hidden rounded-full border border-gray-200 bg-white px-6 py-2.5 text-sm font-semibold text-gray-900 shadow-md transition-colors hover:bg-gray-100 md:block"
      >
        Download
      </a>
    </nav>
  )
}

function SootLogo() {
  return (
    <svg width="26" height="26" viewBox="0 0 64 64" aria-hidden>
      <circle cx="32" cy="36" r="20" fill="#2e9e4d" />
      <circle cx="18" cy="26" r="8" fill="#247a3c" />
      <circle cx="46" cy="27" r="7" fill="#247a3c" />
      <circle cx="32" cy="14" r="6" fill="#247a3c" />
      <circle cx="26" cy="34" r="3" fill="#fff" />
      <circle cx="38" cy="34" r="3" fill="#fff" />
    </svg>
  )
}

/* ----------------------------- building blocks ---------------------------- */

function Section({
  id,
  eyebrow,
  title,
  children,
  dark = false,
}: {
  id: string
  eyebrow: string
  title: React.ReactNode
  children: React.ReactNode
  dark?: boolean
}) {
  return (
    <section id={id} className={`px-6 py-20 sm:py-24 ${dark ? 'bg-[#161619] text-white' : ''}`}>
      <div className="mx-auto max-w-5xl">
        <p className={`text-xs font-bold uppercase tracking-[0.18em] ${dark ? 'text-emerald-400' : 'text-emerald-700'}`}>
          {eyebrow}
        </p>
        <h2
          className={`font-playfair mt-2 max-w-xl text-3xl italic sm:text-4xl ${dark ? 'text-white' : 'text-gray-900'}`}
          style={{ letterSpacing: '-0.03em' }}
        >
          {title}
        </h2>
        <div className="mt-10">{children}</div>
      </div>
    </section>
  )
}

/* ------------------------------- what it does ----------------------------- */

function WhatItDoes() {
  const cards = [
    {
      icon: Terminal,
      title: 'Watches your CLI agents',
      body: 'Claude Code, Codex CLI, Gemini CLI, and OpenCode — exact token counts read from the logs they already write locally.',
    },
    {
      icon: Globe,
      title: 'Follows browser chats',
      body: 'A companion extension estimates tokens for ChatGPT, Claude, and Gemini web chats and sends only the counts to your Mac.',
    },
    {
      icon: Activity,
      title: 'Makes it felt, instantly',
      body: 'Every prompt becomes grams of CO₂e within a second — a puff of soot, a mood change, a running daily total in your menu bar.',
    },
  ]
  return (
    <Section id="what" eyebrow="What it does" title="A carbon Tamagotchi for the AI era.">
      <div className="grid gap-5 sm:grid-cols-3">
        {cards.map((card) => (
          <div
            key={card.title}
            className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm transition-shadow hover:shadow-md"
          >
            <card.icon className="text-emerald-600" size={22} />
            <h3 className="mt-4 text-base font-semibold text-gray-900">{card.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-gray-600">{card.body}</p>
          </div>
        ))}
      </div>
    </Section>
  )
}

/* --------------------------------- privacy -------------------------------- */

function Privacy() {
  const promises = [
    { icon: EyeOff, text: 'Not one word of your prompts or replies is ever stored — or even read.' },
    { icon: ShieldCheck, text: 'Browser page text never leaves the extension. Only token counts cross the localhost bridge.' },
    { icon: Database, text: 'The app keeps token counts, source, model name, timestamps, and estimates — in a local SQLite file you can open yourself.' },
    { icon: Cloud, text: 'No accounts, no telemetry, no cloud. Nothing leaves your Mac.' },
  ]
  return (
    <Section id="privacy" dark eyebrow="The promise" title="Visible emissions. Invisible prompts.">
      <div className="grid gap-4 sm:grid-cols-2">
        {promises.map((promise) => (
          <div key={promise.text} className="flex items-start gap-4 rounded-2xl border border-white/10 bg-white/5 p-5">
            <promise.icon className="mt-0.5 shrink-0 text-emerald-400" size={20} />
            <p className="text-sm leading-relaxed text-white/85">{promise.text}</p>
          </div>
        ))}
      </div>
    </Section>
  )
}

/* ------------------------------- how it works ----------------------------- */

function HowItWorks() {
  const steps = [
    { icon: Terminal, label: 'AI usage', sub: 'CLI logs & browser chats' },
    { icon: Calculator, label: 'Token counts', sub: 'exact where available' },
    { icon: Leaf, label: 'EcoLogits estimate', sub: 'energy → gCO₂e ranges' },
    { icon: HeartPulse, label: 'Pet mood + stats', sub: 'puffs, totals, equivalents' },
  ]
  return (
    <Section id="how" eyebrow="How it works" title="Four small steps from prompt to puff.">
      <div className="flex flex-col items-stretch gap-3 sm:flex-row sm:items-center">
        {steps.map((step, i) => (
          <div key={step.label} className="flex flex-1 items-center gap-3">
            <div className="flex-1 rounded-2xl border border-gray-200 bg-white p-5 text-center shadow-sm">
              <step.icon className="mx-auto text-emerald-600" size={20} />
              <p className="mt-2 text-sm font-semibold text-gray-900">{step.label}</p>
              <p className="mt-0.5 text-xs text-gray-500">{step.sub}</p>
            </div>
            {i < steps.length - 1 && (
              <ArrowRight className="hidden shrink-0 text-gray-300 sm:block" size={18} />
            )}
          </div>
        ))}
      </div>
      <p className="mt-6 text-xs text-gray-500">
        Restart-safe: per-file byte offsets mean nothing is ever double-counted.
      </p>
    </Section>
  )
}

/* --------------------------------- preview -------------------------------- */

function Preview() {
  const week = [38, 61, 22, 80, 47, 95, 64]
  const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S']
  return (
    <Section id="preview" eyebrow="On your desktop" title="A pet that floats, a dashboard that tells the truth.">
      <div className="flex flex-col items-center gap-10 lg:flex-row lg:items-start">
        {/* the pet, as it floats over your windows */}
        <div className="flex flex-col items-center">
          <Wattson mood="content" reaction={null} size={210} />
          <span className="rounded-full bg-black/70 px-3 py-1 text-xs font-semibold text-white">Wattson</span>
          <p className="mt-4 max-w-[240px] text-center text-xs leading-relaxed text-gray-500">
            Always on top, every Space, drag anywhere. Click for stats, right-click to hide. Sleeps
            when you do.
          </p>
        </div>

        {/* dashboard recreation */}
        <div className="w-full max-w-md">
          <div className="rounded-3xl border border-gray-200 bg-white p-4 shadow-lg">
            <div className="rounded-2xl bg-gradient-to-br from-emerald-700 to-emerald-900 p-5 text-white">
              <p className="text-[10px] font-bold tracking-[0.12em] text-white/70">TODAY'S FOOTPRINT</p>
              <div className="flex items-end justify-between">
                <p className="text-3xl font-extrabold">128 g</p>
                <div className="text-right">
                  <p className="text-lg font-bold">6%</p>
                  <p className="text-[10px] text-white/70">of budget</p>
                </div>
              </div>
              <p className="mt-1 text-[11px] text-white/80">74–212 g range · 31 prompts · Wattson is chill 😎</p>
            </div>
            <div className="mt-3 rounded-2xl bg-gray-50 p-4">
              <p className="text-[11px] font-bold text-gray-500">LAST 7 DAYS</p>
              <div className="mt-3 flex h-20 items-end gap-2.5">
                {week.map((value, i) => (
                  <div key={i} className="flex flex-1 flex-col items-center gap-1">
                    <div
                      className={`w-full rounded-full ${i === 5 ? 'bg-gradient-to-b from-teal-400 to-emerald-600' : 'bg-gray-300'}`}
                      style={{ height: `${value}%` }}
                    />
                    <span className="text-[9px] text-gray-400">{days[i]}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {[
                ['📱', '25.6', 'phone charges'],
                ['🚗', '510 m', 'by car'],
              ].map(([emoji, value, label]) => (
                <div key={label} className="flex items-center gap-2.5 rounded-xl bg-gray-50 p-3">
                  <span className="text-lg">{emoji}</span>
                  <div>
                    <p className="text-sm font-bold text-gray-900">{value}</p>
                    <p className="text-[10px] text-gray-500">{label}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
          <p className="mt-3 flex items-center gap-1.5 text-[11px] text-gray-400">
            <BarChart3 size={12} /> Faithful HTML recreation of the in-app dashboard — numbers are
            illustrative.
          </p>
        </div>
      </div>
    </Section>
  )
}

/* ------------------------------- methodology ------------------------------ */

function Methodology() {
  const points = [
    {
      title: 'Ranges, not point estimates',
      body: 'Every figure ships as min–mean–max. Nobody knows these numbers exactly; pretending otherwise would be marketing, not measurement.',
    },
    {
      title: 'EcoLogits-inspired',
      body: 'Token-to-energy follows the EcoLogits methodology (MPL-2.0, gratefully attributed): a regression over model parameter counts fit on ML.ENERGY benchmarks, plus server overhead, datacenter PUE, and an embodied-hardware share.',
    },
    {
      title: 'Your grid, your numbers',
      body: 'Carbon intensity defaults to the world average (~480 gCO₂e/kWh) with regional presets — France and India are very different places to run a GPU.',
    },
    {
      title: 'Honest about unknowns',
      body: 'Closed model sizes are estimates from a bundled registry; unknown models fall back to a conservative default rather than a flattering one.',
    },
  ]
  return (
    <Section id="methodology" eyebrow="Methodology" title="Estimates, clearly labelled as estimates.">
      <div className="grid gap-5 sm:grid-cols-2">
        {points.map((point) => (
          <div key={point.title} className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
            <h3 className="text-base font-semibold text-gray-900">{point.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-gray-600">{point.body}</p>
          </div>
        ))}
      </div>
      <p className="mt-6 text-xs text-gray-500">
        The full assumption-by-assumption write-up ships with the app as docs/methodology.md.
      </p>
    </Section>
  )
}

/* --------------------------------- download ------------------------------- */

function DownloadSection() {
  return (
    <Section id="download" dark eyebrow="Get Sootling" title="Adopt a Wattson.">
      <div className="flex flex-col gap-10 lg:flex-row">
        <div className="flex-1">
          <a
            href="/Sootling-0.1.0.dmg"
            download
            className="inline-flex items-center gap-2.5 rounded-full bg-emerald-500 px-8 py-4 text-base font-semibold text-white transition-all hover:scale-[1.03] hover:bg-emerald-400 hover:shadow-lg hover:shadow-emerald-500/30 active:scale-95"
          >
            <Download size={18} /> Download for macOS
          </a>
          <p className="mt-3 text-xs text-white/60">macOS 14 (Sonoma) or later · Apple silicon · ~0.5 MB</p>
          <ol className="mt-8 space-y-3 text-sm text-white/85">
            {[
              'Open the DMG and drag Sootling into Applications.',
              'First launch: right-click → Open (the build isn’t notarized yet, so macOS will warn once).',
              'Wattson appears, your menu bar shows today’s grams — that’s it. No setup, no account.',
            ].map((step, i) => (
              <li key={i} className="flex gap-3">
                <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-bold">
                  {i + 1}
                </span>
                {step}
              </li>
            ))}
          </ol>
        </div>
        <div className="flex-1 rounded-2xl border border-white/10 bg-white/5 p-6">
          <h3 className="text-sm font-semibold text-white">Optional: browser chats</h3>
          <ol className="mt-4 space-y-2.5 text-sm text-white/75">
            <li>1. Open Sootling Settings and copy the bridge port + secret.</li>
            <li>2. Load the bundled extension folder in any Chromium browser (Chrome, Arc, Brave, Edge).</li>
            <li>3. Paste the port + secret into the extension options.</li>
            <li>4. Chat on chatgpt.com, claude.ai, or gemini.google.com — Wattson reacts.</li>
          </ol>
          <p className="mt-4 text-xs text-white/50">
            Page text stays inside the extension; only token estimates reach the app over 127.0.0.1.
          </p>
        </div>
      </div>
    </Section>
  )
}

/* --------------------------------- roadmap -------------------------------- */

function Roadmap() {
  const shipped = [
    'CLI agents: Claude Code, Codex, Gemini, OpenCode',
    'Living pet with reactions, sleep, and screen smoke',
    'Browser extension bridge (Chromium, beta)',
    'Daily budget, equivalents, 7-day dashboard',
  ]
  const next = [
    'Weekly insight digests',
    'Better model → parameter mappings',
    'Safari extension',
    'Desktop chat app integrations',
  ]
  return (
    <Section id="roadmap" eyebrow="Roadmap" title="Where the soot settles next.">
      <div className="grid gap-5 sm:grid-cols-2">
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <h3 className="text-sm font-bold uppercase tracking-wide text-emerald-700">Shipped</h3>
          <ul className="mt-4 space-y-2.5">
            {shipped.map((item) => (
              <li key={item} className="flex items-start gap-2.5 text-sm text-gray-700">
                <CheckCircle2 className="mt-0.5 shrink-0 text-emerald-600" size={16} /> {item}
              </li>
            ))}
          </ul>
        </div>
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <h3 className="text-sm font-bold uppercase tracking-wide text-amber-600">Next</h3>
          <ul className="mt-4 space-y-2.5">
            {next.map((item) => (
              <li key={item} className="flex items-start gap-2.5 text-sm text-gray-700">
                <Circle className="mt-0.5 shrink-0 text-amber-500" size={16} /> {item}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </Section>
  )
}

/* ---------------------------------- footer -------------------------------- */

function Footer() {
  return (
    <footer className="border-t border-gray-200 px-6 py-14">
      <div className="mx-auto max-w-5xl">
        <p className="font-playfair max-w-2xl text-2xl italic text-gray-900" style={{ letterSpacing: '-0.02em' }}>
          “Sootling makes invisible AI emissions visible — without spying on what you ask.”
        </p>
        <div className="mt-8 flex flex-col gap-2 text-xs text-gray-500 sm:flex-row sm:items-center sm:justify-between">
          <p>Carbon figures are estimates, not measurements. Methodology inspired by EcoLogits (MPL-2.0).</p>
          <p>© 2026 Sootling contributors</p>
        </div>
      </div>
    </footer>
  )
}
