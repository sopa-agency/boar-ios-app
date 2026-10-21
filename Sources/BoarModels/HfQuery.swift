import Foundation

/// The rules of the Hugging Face model search, without the network (the app does the calls): which repos to ask for, which
/// to keep, and which files can be added. Port of `HfQuery.kt`.
public enum HfQuery {
    public static let api = "https://huggingface.co/api"

    /// A file over this can't run on a phone BOAR targets (and would take the whole disk).
    public static let maxFileBytes: Int64 = 12 * 1024 * 1024 * 1024

    /// Parameter buckets, as on huggingface.co/models; capped at 20B, past which no Q4 file fits under `maxFileBytes`.
    public enum Size: Sendable, CaseIterable {
        case any, under1B, b1_3, b3_6, b6_9, b9_20

        public var min: String {
            switch self {
            case .any, .under1B: return "0"
            case .b1_3: return "1B"
            case .b3_6: return "3B"
            case .b6_9: return "6B"
            case .b9_20: return "9B"
            }
        }

        public var max: String {
            switch self {
            case .any, .b9_20: return "20B"
            case .under1B: return "1B"
            case .b1_3: return "3B"
            case .b3_6: return "6B"
            case .b6_9: return "9B"
            }
        }
    }

    public enum Sort: Sendable, CaseIterable {
        case trending, downloads, likes, newest

        public var api: String {
            switch self {
            case .trending: return "trendingScore"
            case .downloads: return "downloads"
            case .likes: return "likes"
            case .newest: return "lastModified"
            }
        }
    }

    /// Text-generation architectures the bundled llama.cpp loads and BOAR can chat with: its LLM_ARCH_NAMES
    /// (src/llama-arch.cpp) without encoders and embedders (bert family, t5, *-embed), speech (tts, wavtokenizer), OCR,
    /// speculative-decoding drafts (eagle3, dflash, gemma4-assistant), vision-only (clip, cogvlm, chameleon) and diffusion
    /// models (dream, llada, rnd1). Update with the llama.cpp pin.
    public static let chatArchitectures: Set<String> = [
        "llama", "llama4", "deci", "falcon", "grok", "gpt2", "gptj", "gptneox", "mpt", "baichuan", "starcoder",
        "refact", "bloom", "stablelm", "qwen", "qwen2", "qwen2moe", "qwen2vl", "qwen3", "qwen3moe", "qwen3next",
        "qwen3vl", "qwen3vlmoe", "qwen35", "qwen35moe", "qwen4exp", "phi2", "phi3", "phimoe", "plamo", "plamo2",
        "plamo3", "codeshell", "orion", "internlm2", "minicpm", "minicpm3", "gemma", "gemma2", "gemma3", "gemma3n",
        "gemma4", "starcoder2", "mamba", "mamba2", "maple", "jamba", "falcon-h1", "xverse", "command-r", "cohere2",
        "cohere2moe", "dbrx", "olmo", "olmo2", "olmoe", "muse-glimmer", "openelm", "arctic", "deepseek", "deepseek2",
        "deepseek32", "deepseek4", "chatglm", "glm4", "glm4moe", "glm-dsa", "bitnet", "jais", "jais2", "nemotron",
        "nemotron_h", "nemotron_h_moe", "exaone", "exaone4", "exaone-moe", "rwkv6", "rwkv6qwen2", "rwkv7", "arwkv7",
        "granite", "granitemoe", "granitehybrid", "graniteswitch", "granite_swa", "plm", "bailingmoe", "bailingmoe2",
        "bailingmoe3", "dots1", "dots3note", "arcee", "afmoe", "laguna", "ernie4_5", "ernie4_5-moe", "hunyuan-moe",
        "hunyuan-dense", "hunyuan_vl", "hy_v3", "hy_v4", "smollm3", "gpt-oss", "lfm2", "lfm2moe",
        "smallthinker", "seed_oss", "grovemoe", "apertus", "minimax-01", "hrm_text",
        "minimax-m2", "minimax-m3", "pangu-embedded", "mistral3", "mistral4", "mimo2", "step35", "spark2_5",
        "maincoder", "kimi-linear", "kimi-k3", "talkie", "mellum", "nanbeige",
    ]

    /// The first page of a search: text-generation GGUF repos in the size bucket, with their GGUF header facts.
    public static func searchUrl(_ query: String, size: Size, sort: Sort, limit: Int = 30) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = trimmed.isEmpty ? "" : "search=\(formEncode(trimmed))&"
        return "\(api)/models?\(q)filter=gguf&pipeline_tag=text-generation&num_parameters=min:\(size.min),max:\(size.max)" +
            "&sort=\(sort.api)&direction=-1&limit=\(limit)&expand[]=gguf&expand[]=downloads&expand[]=likes&expand[]=tags"
    }

    /// The next page from the response's Link header, only when it stays on the models listing.
    public static func nextUrl(_ link: String?) -> String? {
        guard let link,
              let re = try? NSRegularExpression(pattern: #"<([^>]+)>;\s*rel="next""#),
              let m = re.firstMatch(in: link, range: NSRange(link.startIndex..., in: link)),
              let r = Range(m.range(at: 1), in: link) else { return nil }
        let url = String(link[r])
        return url.hasPrefix("\(api)/models?") ? url : nil
    }

    public static func chatArchitecture(_ arch: String?) -> Bool {
        guard let arch else { return false }
        return chatArchitectures.contains(arch)
    }

    private static let uncensoredWords: Set<String> = [
        "uncensored", "abliterated", "abliteration", "nsfw", "erotic", "erp", "lewd", "porn", "hentai", "unaligned", "adult",
    ]

    /// An uncensored or adult model, hidden from Discover unless the build allows them: Hugging Face's own adult tag, or a
    /// telling word in the repo name or tags. A name check, so it misses quiet ones.
    public static func uncensored(_ repoId: String, tags: [String] = []) -> Bool {
        if tags.contains("not-for-all-audiences") { return true }
        for text in [repoId] + tags {
            // split(Regex("[^a-z0-9]+")) on the lowercased text: words are runs of ASCII letters and digits.
            var word = ""
            for ch in text.lowercased().unicodeScalars + [" "] {
                if (ch.value >= 97 && ch.value <= 122) || (ch.value >= 48 && ch.value <= 57) {
                    word.unicodeScalars.append(ch)
                } else {
                    if uncensoredWords.contains(word) { return true }
                    word = ""
                }
            }
        }
        return false
    }

    /// One whole model file: a .gguf, not one part of a split model, not a vision projector, and not over `maxFileBytes`.
    public static func addableFile(_ name: String, sizeBytes: Int64) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".gguf")
            && lower.range(of: "-[0-9]{5}-of-[0-9]{5}\\.gguf$", options: .regularExpression) == nil
            && !lower.contains("mmproj")
            && sizeBytes >= 1 && sizeBytes <= maxFileBytes
    }

    /// The quant to suggest: Q4_K_M, the usual balance of size and quality on a phone.
    public static func recommended(_ names: [String]) -> String? {
        names.first { $0.lowercased().contains("q4_k_m") }
    }

    /// How much a file's quantization keeps of the model, from its bits per weight: what tells versions of one model apart.
    public enum QuantLevel: Sendable, Equatable {
        case smallest, small, balanced, better, high, full
    }

    /// The quant tag in a file name, upper-cased: "Q4_K_M" for "Qwen3-1.7B-Q4_K_M.gguf", "IQ2_XS", "BF16".
    /// Nil when the name has none.
    public static func quant(_ filename: String) -> String? {
        let base = filename.split(separator: "/").last.map(String.init) ?? filename
        let stem = base.replacing(/\.gguf$/.ignoresCase(), with: "")
        let tag = /(?i)(?:^|[-_.])((?:I?Q[1-8](?:_[A-Z0-9]+)*)|BF16|F16|F32)$/
        return stem.firstMatch(of: tag).map { String($0.1).uppercased() }
    }

    /// The level of a quant tag: 1-2 bit smallest, 3 small, 4 balanced, 5 better, 6-8 high, 16-32 bit full.
    public static func quantLevel(_ quant: String) -> QuantLevel? {
        let q = quant.uppercased()
        if ["F16", "BF16", "F32"].contains(q) { return .full }
        guard let bits = q.firstMatch(of: /^I?Q([1-8])/).flatMap({ Int($0.1) }) else { return nil }
        switch bits {
        case 1, 2: return .smallest
        case 3: return .small
        case 4: return .balanced
        case 5: return .better
        default: return .high
        }
    }

    /// "2.7B", "500M".
    public static func formatParams(_ n: Int64) -> String {
        if n >= 1_000_000_000 {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = false
            f.roundingMode = .halfUp
            f.minimumFractionDigits = 1
            f.maximumFractionDigits = 1
            let s = f.string(from: NSNumber(value: Double(n) / 1e9)) ?? "\(Double(n) / 1e9)"
            return (s + "B").replacingOccurrences(of: ".0B", with: "B")
        }
        return "\(Int(Double(n) / 1e6))M"
    }

    /// `java.net.URLEncoder.encode(s, "UTF-8")`: application/x-www-form-urlencoded (space is "+").
    static func formEncode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "_"):
                out.unicodeScalars.append(Unicode.Scalar(b))
            case UInt8(ascii: " "):
                out += "+"
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }
}
