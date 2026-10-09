import Foundation

/// In-place iterative radix-2 complex FFT. Portable Swift so the analysis is identical on every platform.
struct FFT: Sendable {
    let size: Int
    private let cosines: [Double]
    private let sines: [Double]
    private let reversed: [Int]

    init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        cosines = (0..<size / 2).map { cos(-2 * .pi * Double($0) / Double(size)) }
        sines = (0..<size / 2).map { sin(-2 * .pi * Double($0) / Double(size)) }
        let bits = size.trailingZeroBitCount
        reversed = (0..<size).map { index in
            var value = 0, input = index
            for _ in 0..<bits { value = (value << 1) | (input & 1); input >>= 1 }
            return value
        }
    }

    func transform(_ real: inout [Double], _ imag: inout [Double]) {
        let n = size
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                cosines.withUnsafeBufferPointer { cs in
                    sines.withUnsafeBufferPointer { sn in
                        reversed.withUnsafeBufferPointer { rev in
                            for i in 0..<n where i < rev[i] {
                                re.swapAt(i, rev[i]); im.swapAt(i, rev[i])
                            }
                            var length = 2
                            while length <= n {
                                let half = length / 2, step = n / length
                                var start = 0
                                while start < n {
                                    for k in 0..<half {
                                        let wr = cs[k * step], wi = sn[k * step]
                                        let a = start + k, b = a + half
                                        let tr = re[b] * wr - im[b] * wi
                                        let ti = re[b] * wi + im[b] * wr
                                        re[b] = re[a] - tr; im[b] = im[a] - ti
                                        re[a] += tr; im[a] += ti
                                    }
                                    start += length
                                }
                                length <<= 1
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Transposed direct-form II biquad.
struct Biquad: Sendable {
    var b0, b1, b2, a1, a2: Double
    private var z1 = 0.0, z2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    @inline(__always) mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// ITU-R BS.1770 K-weighting (pre-filter shelf + RLB high-pass) for any sample rate.
struct KWeighting: Sendable {
    private var shelf: Biquad
    private var highPass: Biquad

    init(sampleRate rate: Double) {
        let shelfK = tan(.pi * 1681.974450955533 / rate)
        let shelfQ = 0.7071752369554196
        let vh = pow(10, 3.999843853973347 / 20)
        let vb = pow(vh, 0.4996667741545416)
        let shelfA0 = 1 + shelfK / shelfQ + shelfK * shelfK
        shelf = Biquad(b0: (vh + vb * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
                       b1: 2 * (shelfK * shelfK - vh) / shelfA0,
                       b2: (vh - vb * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
                       a1: 2 * (shelfK * shelfK - 1) / shelfA0,
                       a2: (1 - shelfK / shelfQ + shelfK * shelfK) / shelfA0)
        let passK = tan(.pi * 38.13547087602444 / rate)
        let passQ = 0.5003270373238773
        let passA0 = 1 + passK / passQ + passK * passK
        highPass = Biquad(b0: 1, b1: -2, b2: 1,
                          a1: 2 * (passK * passK - 1) / passA0,
                          a2: (1 - passK / passQ + passK * passK) / passA0)
    }

    var coefficients: (shelf: Biquad, highPass: Biquad) { (shelf, highPass) }

    @inline(__always) mutating func process(_ x: Double) -> Double { highPass.process(shelf.process(x)) }
}

/// Inter-sample peak estimate using 4× polyphase windowed-sinc interpolation (BS.1770 Annex 2 method).
struct TruePeakMeter: Sendable {
    static let taps = 16
    /// Three interpolating phases (¼, ½, ¾ between samples); phase 0 reproduces the samples themselves.
    private static let phases: [[Double]] = {
        let length = 64, centre = 32.0, beta = 6.0
        func bessel(_ x: Double) -> Double {
            var sum = 1.0, term = 1.0, k = 1.0
            while term > 1e-12 * sum { term *= (x / (2 * k)) * (x / (2 * k)); sum += term; k += 1 }
            return sum
        }
        let h = (0..<length).map { n -> Double in
            let t = (Double(n) - centre) / 4
            let sinc = t == 0 ? 1 : sin(.pi * t) / (.pi * t)
            let r = (Double(n) - centre) / centre
            return sinc * bessel(beta * sqrt(max(0, 1 - r * r))) / bessel(beta)
        }
        return (1...3).map { phase in
            let coefficients = (0..<taps).map { h[phase + 4 * $0] }
            let sum = coefficients.reduce(0, +)
            return coefficients.map { $0 / sum }
        }
    }()

    private var history = [Double](repeating: 0, count: taps)
    private var cursor = 0
    private(set) var maximum = 0.0

    @inline(__always) mutating func process(_ sample: Double) {
        history[cursor] = sample
        cursor = (cursor + 1) % Self.taps
        let magnitude = abs(sample)
        if magnitude > maximum { maximum = magnitude }
        // The interpolated region sits between the two centre taps. Skip quiet regions, which
        // cannot produce a new maximum, to keep long files fast.
        let a = abs(history[(cursor + 7) % Self.taps]), b = abs(history[(cursor + 8) % Self.taps])
        guard max(a, b) >= maximum * 0.5 else { return }
        for coefficients in Self.phases {
            var value = 0.0
            for j in 0..<Self.taps {
                value += coefficients[j] * history[(cursor - 1 - j + 2 * Self.taps) % Self.taps]
            }
            if abs(value) > maximum { maximum = abs(value) }
        }
    }

    mutating func flush() { for _ in 0..<Self.taps { process(0) } }
}
