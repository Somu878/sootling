import { useEffect, useState } from 'react'

export type Mood = 'thriving' | 'content' | 'sluggish' | 'sooty'

const PALETTE: Record<Mood, { top: string; bottom: string; tuft: string; glow: string }> = {
  thriving: { top: '#73d973', bottom: '#2e9e4d', tuft: '#4db35c', glow: 'rgba(74,222,128,0.45)' },
  content: { top: '#66c79e', bottom: '#389473', tuft: '#479e80', glow: 'rgba(94,234,212,0.4)' },
  sluggish: { top: '#8c8c6b', bottom: '#615c4d', tuft: '#706b57', glow: 'rgba(251,191,36,0.3)' },
  sooty: { top: '#4d4d52', bottom: '#1a1a1f', tuft: '#29292e', glow: 'rgba(120,120,130,0.35)' },
}

export const MOOD_LINE: Record<Mood, string> = {
  thriving: 'Wattson is vibing 🌱',
  content: 'Wattson is chill 😎',
  sluggish: 'Wattson is wheezing 😮‍💨',
  sooty: 'Wattson is in the smog 😵‍💫',
}

interface Reaction {
  id: number
  grams: number
  label: string
}

interface Props {
  mood: Mood
  reaction: Reaction | null
  size?: number
}

/** The desktop pet, rebuilt in SVG: breathing, blinking, mood-coloured, and
 *  puffing soot (or sparkles) when a simulated prompt lands. */
export default function Wattson({ mood, reaction, size = 190 }: Props) {
  const colors = PALETTE[mood]
  const happy = mood === 'thriving' || mood === 'content'
  const [puffKeys, setPuffKeys] = useState<number[]>([])

  useEffect(() => {
    if (!reaction) return
    setPuffKeys((keys) => [...keys.slice(-6), reaction.id])
  }, [reaction])

  const sparkle = reaction !== null && reaction.grams < 2.5

  return (
    <div className="relative select-none" style={{ width: size, height: size }}>
      {/* mood glow */}
      <div
        className="absolute inset-[12%] rounded-full blur-2xl transition-colors duration-700"
        style={{ background: colors.glow }}
      />

      {/* reaction bubble */}
      {reaction && (
        <div
          key={reaction.id}
          className="bubble-pop absolute -top-12 left-1/2 z-20 -translate-x-1/2 whitespace-nowrap rounded-xl px-3 py-1.5 text-center shadow-lg"
          style={{
            background: reaction.grams < 2.5 ? '#15803d' : reaction.grams < 18 ? '#b45309' : '#b91c1c',
          }}
        >
          <span className="block text-sm font-bold text-white">
            +{reaction.grams.toFixed(1)} g CO₂e
          </span>
          <span className="block text-[10px] font-medium text-white/85">{reaction.label}</span>
        </div>
      )}

      {/* puffs / sparkles */}
      {puffKeys.map((key, i) => (
        <div
          key={key}
          className={`${sparkle ? 'sparkle-rise' : 'puff-rise'} pointer-events-none absolute z-10`}
          style={{ top: '22%', left: `${38 + (i % 3) * 14}%`, animationDelay: `${(i % 3) * 0.12}s` }}
        >
          {sparkle ? (
            <span className="text-lg">✦</span>
          ) : (
            <div className="h-5 w-5 rounded-full bg-black/45 blur-[2px]" />
          )}
        </div>
      ))}

      <svg viewBox="0 0 200 200" className="pet-breathe relative z-[5] h-full w-full">
        <defs>
          <linearGradient id={`body-${mood}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor={colors.top} />
            <stop offset="100%" stopColor={colors.bottom} />
          </linearGradient>
          <radialGradient id="shine" cx="0.35" cy="0.28" r="0.6">
            <stop offset="0%" stopColor="rgba(255,255,255,0.4)" />
            <stop offset="100%" stopColor="rgba(255,255,255,0)" />
          </radialGradient>
        </defs>

        {/* ground shadow */}
        <ellipse cx="100" cy="178" rx="42" ry="9" fill="rgba(0,0,0,0.22)" />

        {/* crown tufts */}
        <circle cx="64" cy="78" r="15" fill={colors.tuft} className="transition-colors duration-700" />
        <circle cx="136" cy="80" r="13" fill={colors.tuft} className="transition-colors duration-700" />
        <circle cx="100" cy="58" r="12" fill={colors.tuft} className="transition-colors duration-700" />
        <circle cx="146" cy="116" r="11" fill={colors.tuft} className="transition-colors duration-700" />
        <circle cx="54" cy="114" r="11" fill={colors.tuft} className="transition-colors duration-700" />

        {/* body */}
        <circle cx="100" cy="110" r="56" fill={`url(#body-${mood})`} className="transition-colors duration-700" />
        <circle cx="100" cy="110" r="56" fill="url(#shine)" />

        {/* sprout (healthy only) */}
        <g
          style={{
            opacity: happy ? 1 : 0,
            transform: happy ? 'scale(1)' : 'scale(0.4)',
            transformOrigin: '100px 54px',
            transition: 'opacity 0.6s, transform 0.6s',
          }}
        >
          <rect x="98.5" y="40" width="3" height="14" rx="1.5" fill="#22c55e" />
          <ellipse cx="92" cy="38" rx="7" ry="4.5" fill="#22c55e" transform="rotate(-35 92 38)" />
          <ellipse cx="108" cy="38" rx="7" ry="4.5" fill="#22c55e" transform="rotate(35 108 38)" />
        </g>

        {/* eyes */}
        <g className="pet-blink">
          <ellipse cx="84" cy="102" rx="7" ry={happy ? 9 : 6} fill="rgba(255,255,255,0.96)" />
          <ellipse cx="116" cy="102" rx="7" ry={happy ? 9 : 6} fill="rgba(255,255,255,0.96)" />
          <circle cx="85.5" cy="103" r="3.4" fill="rgba(10,10,12,0.88)" />
          <circle cx="117.5" cy="103" r="3.4" fill="rgba(10,10,12,0.88)" />
          <circle cx="84.4" cy="101.8" r="1.1" fill="white" />
          <circle cx="116.4" cy="101.8" r="1.1" fill="white" />
        </g>

        {/* cheeks */}
        {happy && (
          <>
            <circle cx="74" cy="115" r="5" fill="rgba(244,114,182,0.4)" />
            <circle cx="126" cy="115" r="5" fill="rgba(244,114,182,0.4)" />
          </>
        )}

        {/* mouth */}
        {mood === 'thriving' && (
          <path d="M88 124 Q100 134 112 124" stroke="rgba(10,10,12,0.55)" strokeWidth="3.4" strokeLinecap="round" fill="none" />
        )}
        {mood === 'content' && (
          <rect x="92" y="124" width="16" height="3.6" rx="1.8" fill="rgba(10,10,12,0.45)" />
        )}
        {mood === 'sluggish' && (
          <rect x="92" y="125" width="15" height="3.4" rx="1.7" fill="rgba(255,255,255,0.55)" transform="rotate(-7 100 126)" />
        )}
        {mood === 'sooty' && (
          <path d="M89 129 Q100 121 111 129" stroke="rgba(255,255,255,0.55)" strokeWidth="3.2" strokeLinecap="round" fill="none" />
        )}
      </svg>
    </div>
  )
}
