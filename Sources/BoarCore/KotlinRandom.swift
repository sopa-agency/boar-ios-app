/// Kotlin's seeded `Random(seed: Long)` (kotlin.random.XorWowRandom, Marsaglia's xorwow) with `nextInt(until)` and
/// `shuffled`, number for number: a choice Android draws from a seed (the Daily Quiz's questions and options, by the date)
/// comes out the same on the iPhone. From the Kotlin stdlib sources (XorWowRandom.kt, Random.kt, MutableCollections.kt).
public struct KotlinRandom: Sendable {
    private var x: Int32, y: Int32, z: Int32, w: Int32, v: Int32, addend: Int32

    /// `Random(seed: Long)`: XorWowRandom(seed.toInt(), (seed shr 32).toInt()).
    public init(seed: Int64) {
        let seed1 = Int32(truncatingIfNeeded: seed)
        let seed2 = Int32(truncatingIfNeeded: seed >> 32)
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        // Some trivial seeds give several values with zeroes in the upper bits, so the first 64 are discarded.
        for _ in 0..<64 { _ = nextInt() }
    }

    public mutating func nextInt() -> Int32 {
        var t = x
        t ^= Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362_437
        return t &+ addend
    }

    /// The upper `bitCount` bits of the next Int (0...32).
    public mutating func nextBits(_ bitCount: Int) -> Int32 {
        let r = UInt32(bitPattern: nextInt())
        if bitCount == 0 { return 0 }
        return Int32(bitPattern: r >> UInt32(32 - bitCount))
    }

    /// `nextInt(until)`: uniform in 0..<until, until > 0.
    public mutating func nextInt(_ until: Int) -> Int {
        precondition(until > 0, "until must be positive")
        let n = Int32(until)
        if n & -n == n {
            return Int(nextBits(31 - n.leadingZeroBitCount))
        }
        var bits: Int32
        var value: Int32
        repeat {
            bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            value = bits % n
        } while bits &- value &+ (n - 1) < 0
        return Int(value)
    }

    /// `MutableList.shuffle(random)`: from the last index down, swap with a random one at or below it.
    public mutating func shuffle<T>(_ list: inout [T]) {
        var i = list.count - 1
        while i >= 1 {
            let j = nextInt(i + 1)
            list.swapAt(i, j)
            i -= 1
        }
    }

    /// `Iterable.shuffled(random)`.
    public mutating func shuffled<T>(_ list: [T]) -> [T] {
        var copy = list
        shuffle(&copy)
        return copy
    }
}
