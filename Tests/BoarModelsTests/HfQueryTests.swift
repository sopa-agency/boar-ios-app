import Testing
@testable import BoarModels

@Suite struct HfQueryTests {
    @Test func searchAsksForTextGenerationGGUFReposInTheBucketWithTheirGGUFFacts() {
        let url = HfQuery.searchUrl(" qwen 3 ", size: .b1_3, sort: .trending)
        #expect(url.hasPrefix("https://huggingface.co/api/models?search=qwen+3&filter=gguf&pipeline_tag=text-generation"))
        #expect(url.contains("num_parameters=min:1B,max:3B"))
        #expect(url.contains("sort=trendingScore") && url.contains("expand[]=gguf"))
    }

    @Test func browsingWithoutAQueryHasNoSearchTermAndAnyStopsAt20B() {
        let url = HfQuery.searchUrl("", size: .any, sort: .downloads)
        #expect(!url.contains("search="))
        #expect(url.contains("num_parameters=min:0,max:20B"))
    }

    @Test func formEncodingMatchesJavasURLEncoder() {
        #expect(HfQuery.formEncode("a b&c/ü*-._~") == "a+b%26c%2F%C3%BC*-._%7E")
    }

    @Test func theNextPageComesFromTheLinkHeaderAndStaysOnTheListing() {
        let next = "https://huggingface.co/api/models?filter=gguf&cursor=abc"
        #expect(HfQuery.nextUrl("<\(next)>; rel=\"next\"") == next)
        #expect(HfQuery.nextUrl("<https://evil.example/api/models?x>; rel=\"next\"") == nil)
        #expect(HfQuery.nextUrl(nil) == nil)
        #expect(HfQuery.nextUrl("<\(next)>; rel=\"prev\", <\(next)2>;rel=\"next\"") == next + "2")
    }

    @Test func keepsChatArchitecturesDropsDraftsEmbeddersAndDiffusion() {
        #expect(HfQuery.chatArchitecture("qwen3"))
        #expect(HfQuery.chatArchitecture("lfm2"))
        for a in ["dflash", "bert", "llada", "clip", nil] as [String?] { #expect(!HfQuery.chatArchitecture(a), "\(a ?? "nil")") }
    }

    @Test func onlyWholeGGUFFilesUnder12GB() {
        #expect(HfQuery.addableFile("Qwen3-4B-Q4_K_M.gguf", sizeBytes: 2_500_000_000))
        #expect(!HfQuery.addableFile("Big-Q4_K_M-00001-of-00003.gguf", sizeBytes: 5_000_000_000))
        #expect(!HfQuery.addableFile("mmproj-model-f16.gguf", sizeBytes: 800_000_000))
        #expect(!HfQuery.addableFile("Huge-Q8_0.gguf", sizeBytes: 13 * 1024 * 1024 * 1024))
        #expect(!HfQuery.addableFile("README.md", sizeBytes: 10))
        #expect(!HfQuery.addableFile("empty.gguf", sizeBytes: 0))
    }

    @Test func suggestsQ4KMAndPrintsParameterCounts() {
        #expect(HfQuery.recommended(["m-Q8_0.gguf", "m-Q4_K_M.gguf"]) == "m-Q4_K_M.gguf")
        #expect(HfQuery.recommended(["m-Q8_0.gguf"]) == nil)
    }

    @Test func theQuantTagAndItsLevelTellVersionsApart() {
        #expect(HfQuery.quant("Qwen3-1.7B-Q4_K_M.gguf") == "Q4_K_M")
        #expect(HfQuery.quant("qwen3-1.7b-q8_0.gguf") == "Q8_0")
        #expect(HfQuery.quant("Qwen3-1.7B-UD-IQ2_XXS.gguf") == "IQ2_XXS")
        #expect(HfQuery.quant("sub/Qwen3-1.7B-BF16.gguf") == "BF16")
        #expect(HfQuery.quant("Qwen3-1.7B.gguf") == nil)
        #expect(HfQuery.quantLevel("Q2_K") == .smallest)
        #expect(HfQuery.quantLevel("IQ3_M") == .small)
        #expect(HfQuery.quantLevel("Q4_K_M") == .balanced)
        #expect(HfQuery.quantLevel("Q5_K_S") == .better)
        #expect(HfQuery.quantLevel("Q8_0") == .high)
        #expect(HfQuery.quantLevel("F16") == .full)
        #expect(HfQuery.quantLevel("TQ1_0") == nil)
        #expect(HfQuery.formatParams(2_697_198_592) == "2.7B")
        #expect(HfQuery.formatParams(4_000_000_000) == "4B")
        #expect(HfQuery.formatParams(500_000_000) == "500M")
    }

    @Test func uncensoredModelsAreRecognized() {
        #expect(HfQuery.uncensored("Orenguteng/Llama-3-8B-Lexi-Uncensored-GGUF"))
        #expect(HfQuery.uncensored("mlabonne/gemma-3-4b-it-abliterated-GGUF"))
        #expect(HfQuery.uncensored("someone/plain-name-GGUF", tags: ["text-generation", "not-for-all-audiences"]))
        #expect(HfQuery.uncensored("someone/model-GGUF", tags: ["nsfw"]))
        #expect(HfQuery.uncensored("someone/Adult-Chat-7B-GGUF"))
        #expect(!HfQuery.uncensored("Qwen/Qwen3-4B-Instruct-2507-GGUF", tags: ["text-generation", "gguf"]))
        // Whole words only: "therapy" isn't "erp", "superpower" isn't "erp" either.
        #expect(!HfQuery.uncensored("someone/therapy-superpower-GGUF"))
    }
}
