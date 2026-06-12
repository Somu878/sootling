import Foundation

public enum PetHealthState: String, CaseIterable, Sendable {
    case thriving
    case content
    case sluggish
    case sooty

    public static func fromBudgetProgress(_ progress: Double) -> PetHealthState {
        switch progress {
        case ..<0.25:
            return .thriving
        case ..<0.60:
            return .content
        case ..<1.0:
            return .sluggish
        default:
            return .sooty
        }
    }

    public var title: String {
        switch self {
        case .thriving: "Thriving"
        case .content: "Content"
        case .sluggish: "Sluggish"
        case .sooty: "Sooty"
        }
    }

    /// A short, in-character line Wattson "says" for each mood.
    public var mood: String {
        switch self {
        case .thriving: "Wattson is vibing 🌱"
        case .content: "Wattson is chill 😎"
        case .sluggish: "Wattson is wheezing 😮‍💨"
        case .sooty: "Wattson is in the smog 😵‍💫"
        }
    }
}

/// A single, animatable reaction to one detected prompt. Drives Wattson's puff
/// size, colour, face, and squash-stretch bounce in the overlay.
public struct PetReaction: Equatable, Identifiable, Sendable {
    /// How dramatic the reaction is. Thresholds are tuned to real agentic-CLI
    /// prompts (typically ~5–30 gCO2e each), not toy one-liners.
    public enum Tier: Sendable {
        case breeze   // barely registers — sparkle and a happy squint
        case puff     // a visible soot puff and a cough
        case choke    // smoke storm, dizzy eyes, dramatic complaint
    }

    public let id: UUID
    public let grams: Double
    public let source: UsageSource
    public let state: PetHealthState
    public let model: String
    public let tokensIn: Int
    public let tokensOut: Int
    public let dailyTotal: Double

    public init(
        id: UUID = UUID(),
        grams: Double,
        source: UsageSource,
        state: PetHealthState,
        model: String = "",
        tokensIn: Int = 0,
        tokensOut: Int = 0,
        dailyTotal: Double = 0
    ) {
        self.id = id
        self.grams = grams
        self.source = source
        self.state = state
        self.model = model
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.dailyTotal = dailyTotal
    }

    public var tier: Tier {
        if grams < 2.5 { return .breeze }
        if grams < 18 { return .puff }
        return .choke
    }

    /// 0…1 intensity used to scale the puff and the bounce, log-shaped so a
    /// tiny prompt still registers and a huge one doesn't blow out the panel.
    public var intensity: Double {
        let clamped = max(0.05, grams)
        return min(1, log10(clamped + 1) / log10(31))
    }

    public var formattedGrams: String {
        grams < 10 ? String(format: "+%.1fg CO₂e", grams) : String(format: "+%.0fg CO₂e", grams)
    }
}

/// Wattson's vocabulary: per-prompt one-liners and idle chatter. The overlay
/// samples these (avoiding recent repeats) instead of a deterministic pick, so
/// back-to-back prompts stop sounding canned.
public enum PetQuips {
    /// Candidate one-liners for a detected prompt. Pass source/model/tokens for
    /// source-aware and token-count quips to mix into the pool.
    public static func reactionLines(
        tier: PetReaction.Tier,
        grams: Double,
        source: UsageSource = .claudeCode,
        model: String = "",
        tokensOut: Int = 0
    ) -> [String] {
        let carMeters      = max(1, Int((grams / 0.251).rounded()))
        let netflixSec     = max(1, Int((grams / 55.0 * 3600).rounded()))
        let netflixMin     = max(1, Int((grams / 55.0 * 60).rounded()))
        let phoneCharges   = String(format: "%.1f", grams / 5.0)
        let ledMin         = max(1, Int((grams / 3.84 * 60).rounded()))
        let googleSearches = max(1, Int((grams / 0.2).rounded()))
        let tokStr         = tokensOut > 0 ? "\(tokensOut)" : "several thousand"

        let hour = Calendar.current.component(.hour, from: Date())
        let isLateNight = hour < 5 || hour >= 23
        let isMorning   = hour >= 6 && hour < 9

        var lines: [String]

        switch tier {
        case .breeze:
            lines = [
                "barely a breeze 🍃",
                "cache hit — practically free 😎",
                "I've sneezed bigger 🤧",
                "eco mode activated 💚",
                "my sprout didn't even flinch 🌱",
                "a rounding error, honestly 🤏",
                "green and serene 🧘",
                "feather-light. I approve 🤍",
                "the fans didn't even flutter 🌬️",
                "this is what responsible AI looks like 🎖️",
                "prompt? what prompt? barely registered 📡",
                "tiny tokens, big dreams 🌠",
                "GPUs went 'meh' 😴",
                "Wattson approves of this lifestyle 🌿",
                "the atmosphere says thanks 🌍",
                "≈ \(ledMin) min of LED light 💡",
                "≈ \(googleSearches) Google search\(googleSearches == 1 ? "" : "es") 🔍",
                "the datacenter gave a polite yawn 🏢",
                "costs less than sending a text message 📱",
                "prompt economy: solid A+ 📈",
                "the grid barely blinked ⚡",
                "I'd hug you but I'm busy photosynthesizing 🌿"
            ]
            switch source {
            case .claudeCode:
                lines += ["Claude Code being suspiciously efficient today 📟",
                          "CLI agent: Wattson certified green 🌿"]
            case .codexCLI:
                lines += ["Codex keeping it feather-light ⚙️"]
            case .openCode:
                lines += ["OpenCode tiptoeing through the datacenter 🤫"]
            case .geminiCLI, .geminiWeb:
                lines += ["Google's servers gave a gentle hum 🌐"]
            case .claudeWeb, .chatgptWeb:
                lines += ["browser tab doing less damage than expected 🌐"]
            default: break
            }
            if isLateNight { lines += ["3am and barely a blip — Wattson is impressed 🌙"] }
            if isMorning   { lines += ["morning warmup prompt: eco-approved ☀️"] }

        case .puff:
            lines = [
                "felt that one 😮‍💨",
                "*small cough* 💨",
                "the GPUs stirred… 👀",
                "spicy little prompt 🌶️",
                "somewhere, a fan spun faster 🌀",
                "token tax collected 🧾",
                "warm. getting warm 🌡️",
                "not great, not terrible 🙃",
                "the inference engine clocked in 🤖",
                "I felt that one in my tufts 🌿",
                "mild turbulence ✈️",
                "a CO₂ molecule has entered the chat 💨",
                "that'll leave a faint carbon shadow 🪶",
                "GPU: 'ok fine, I'll do some math' 🖥️",
                "carbon clock is ticking 🕰️",
                "still in budget… *nervous laugh* 😅",
                "I'm aware. I'm watching. 👁️",
                "that felt like an espresso shot ☕",
                "≈ \(carMeters)m by car 🚗",
                "≈ \(netflixSec)s of Netflix 📺",
                "≈ \(ledMin) min of LED light 💡",
                "≈ \(googleSearches) Google searches 🔍"
            ]
            switch source {
            case .claudeCode:
                lines += ["Claude Code's inference invoice: delivered 📬",
                          "that's Claude Code flexing its context window 📟"]
            case .codexCLI:
                lines += ["Codex CLI earning its keep 💻"]
            case .openCode:
                lines += ["OpenCode editor just did a thing 🛠️"]
            case .geminiCLI, .geminiWeb:
                lines += ["Google's data centers felt this one 🌐"]
            case .claudeWeb, .chatgptWeb:
                lines += ["that browser chat hit different 🌐"]
            default: break
            }
            if isLateNight { lines += ["late-night prompting detected 🌙 Wattson is watching"] }
            if isMorning   { lines += ["good morning! already billing the atmosphere ☀️"] }

        case .choke:
            lines = [
                "tell the GPUs I'm sorry 🥵",
                "*cough cough* WHO wrote that prompt?? 🫁",
                "a datacenter just sighed 🏭",
                "I taste tokens. SO many tokens 😵‍💫",
                "was that a whole novel?? 📚",
                "the grid felt that one ⚡",
                "my therapist will hear about this 🛋️",
                "I need to lie down 🛌",
                "somewhere a polar bear shed a tear 🐻‍❄️",
                "that's it. I'm planting a tree 🌳",
                "is this an essay? this feels like an essay 📝",
                "my leaves are wilting 🍂",
                "I can FEEL the datacenter heating up 🔥",
                "Wattson.exe has stopped responding 💀",
                "CO₂ has entered the chat — at scale 📢",
                "we need to talk about your prompts 🗣️",
                "I'm not mad. I'm disappointed 😔",
                "the GPUs are unionizing as we speak 🤝",
                "\(tokStr) output tokens. Let that land. 🤯",
                "≈ \(carMeters)m by car 🚗💨",
                "≈ \(phoneCharges)× phone charges 🔋😬",
                "≈ \(netflixMin) min of Netflix 📺",
                "≈ \(googleSearches) Google searches — think about that 🔍"
            ]
            switch source {
            case .claudeCode:
                lines += ["Claude Code went BRRRR 🖥️💨",
                          "the CLI is eating well today 📟🔥"]
            case .codexCLI:
                lines += ["Codex went full turbo mode 🚀",
                          "Codex CLI: unlimited power, unlimited carbon 🌩️"]
            case .openCode:
                lines += ["OpenCode declared war on the atmosphere 💥",
                          "OpenCode did NOT hold back 🛠️🔥"]
            case .geminiCLI, .geminiWeb:
                lines += ["Google's data centers took a hit 🌐🔥"]
            case .claudeWeb, .chatgptWeb:
                lines += ["browser AI went full send 🌐🔥",
                          "a browser tab did this. A BROWSER TAB. 😤"]
            default: break
            }
            if isLateNight { lines += ["3am carbon crime in progress 🌙🚨"] }
            if isMorning   { lines += ["morning espresso AND a big prompt? bold strategy ☀️🔥"] }
        }

        return lines
    }

    public static func idle(for state: PetHealthState) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let isLateNight = hour < 5 || hour >= 23
        let isMorning   = hour >= 6 && hour < 9

        var lines: [String]
        switch state {
        case .thriving:
            lines = [
                "so fresh out here ✨",
                "carbon? barely know her 💅",
                "*photosynthesizing*… jk 🌱",
                "best air I've had all week 🏞️",
                "I could get used to this 😌",
                "vibing at near-zero emissions 🌿",
                "the atmosphere sends its regards 🌍",
                "clean air detected. fully thriving. 🌬️",
                "peak Wattson hours 🎖️",
                "green flag: been a while since a prompt 💚",
                "soaking in the silence 🤫",
                "this is the life I was built for 🌱"
            ]
        case .content:
            lines = [
                "cruising along 😌",
                "nice and steady today 👍",
                "*hums in renewable energy*",
                "watching you work. no pressure 👀",
                "we're doing okay, you and me 🤝",
                "sustainable pace — I respect it 📊",
                "the carbon budget says hi 🙋",
                "equilibrium achieved. for now 🧘",
                "not thriving, not suffering — just vibing 😐",
                "keeping an eye on the gram counter 🔢",
                "all good in the neighbourhood 🏡",
                "neutral vibes. certified fine. ✅"
            ]
        case .sluggish:
            lines = [
                "getting a bit smoky in here… 😶‍🌫️",
                "maybe… shorter prompts? 🥺",
                "*wheeze* I'm fine. probably.",
                "is it warm in here or is it the GPUs 🥵",
                "I miss the morning air 🌫️",
                "the tufts are turning grey 🪨",
                "Wattson is hanging in there. barely. 😮‍💨",
                "coughing into the void here 🌑",
                "the carbon budget is not amused 📉",
                "consider: fewer tokens 🤏",
                "I can see the smog from here 🌁",
                "Wattson requests a prompt holiday 🏖️"
            ]
        case .sooty:
            lines = [
                "I've seen things. token things 🫠",
                "send help. or a forest 🌲",
                "*coughs in CO₂e*",
                "tomorrow we go green. right? RIGHT? 😤",
                "consider me carbon-marinated 🫥",
                "I live in the fog now. this is my life 🌁",
                "the smog is my permanent address 📍",
                "one more prompt and I'm done 😤 (I'll never be done)",
                "at this rate the datacenter knows my name 🏭",
                "the sprout is gone. it is simply gone 🍂",
                "Wattson: fully caramelised 😵‍💫",
                "I'm starting to look like the smoke 👻"
            ]
        }
        if isLateNight {
            switch state {
            case .thriving, .content:
                lines += ["burning midnight oil — but responsibly 🌙"]
            case .sluggish, .sooty:
                lines += ["3am and already this much carbon. we need to talk. 🌙"]
            }
        }
        if isMorning {
            switch state {
            case .thriving, .content:
                lines += ["good morning! off to a clean start ☀️"]
            case .sluggish, .sooty:
                lines += ["morning carbon already? the GPUs never sleep 🌅"]
            }
        }
        return lines[Int.random(in: 0..<lines.count)]
    }
}

