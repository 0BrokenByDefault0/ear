import Foundation

struct Experiment: Identifiable {
    var lens: Lens
    var title: String
    var purpose: String
    var minutes: Int
    var steps: [String]
    var check: String
    var key: String? = nil
    var id: String { key ?? lens.rawValue }

    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        let content = ([title, purpose, lens.rawValue, check] + steps).joined(separator: " ")
        return words.allSatisfy { content.localizedStandardContains(String($0)) }
    }

    static func make(_ lens: Lens, daw: DAW, tempo: Double?) -> Experiment {
        let studio = daw == .studio
        let returnName = studio ? "FX Channel" : "aux channel"
        let routing = studio
            ? "Create an FX Channel in the Console, name it EAR Space, then add a send from your source channel to it. Keep the source routed to Main."
            : "On your source channel strip, choose an unused Bus in a Send slot. Logic creates an aux; name it EAR Space. Keep the source routed to Stereo Out."
        let delay = studio ? "Analog Delay" : "Stereo Delay"
        let reverb = studio ? "Room Reverb" : "ChromaVerb"
        let tempoText = tempo.map { "At \(decimal($0, 0)) BPM, start at \(decimal(30000 / $0, 0)) ms (1/8 note)." } ?? "Tap or set the song tempo first, then start at a synced 1/8 note."
        switch lens {
        case .drums:
            return Experiment(lens: lens, title: "Shape the front of the hit", purpose: "Discover how attack and sustain change a groove without changing the pattern.", minutes: 5, steps: ["In your own session, loop two bars of drums. Use a drum stem or your drum bus, not the imported full mix.", "Insert the stock Compressor or FabFilter Pro-C 2. Start at 3:1, 20 ms attack and 100 ms release. Lower threshold until the biggest hits produce roughly 2–3 dB of gain reduction.", "Match output to bypass. Compare 3 ms and 30 ms attack. Listen for a softer front at the faster setting and more initial punch at the slower setting; the source and compressor can change the result.", "Adjust release until the gain reduction recovers musically between hits. If the tail swells or the groove feels smaller, reduce the amount."], check: "Bypass at the same perceived loudness. Keep the version that supports the groove; undo it if you only prefer the louder one.")
        case .vocals:
            return Experiment(lens: lens, title: "An intimate lead, a wider answer", purpose: "Build width with a second performance while keeping the main vocal close.", minutes: 10, steps: ["Keep your lead centered. Record two new takes of only the last few words of selected lines. On an instrumental, use two variations of the lead phrase.", "Pan the support takes about 45% left and right. Start around 12 dB below the lead. Identical duplicated audio is not a new double.", "Align the first consonant enough to stay clear, but preserve some natural timing and pitch difference. Fade the region boundaries.", "Use EQ to remove only distracting low end from the support tracks. Try less high-frequency detail than the lead, then automate the layers out of the next phrase."], check: "Listen in mono and at low volume. The lead should remain intelligible. If it sounds phasey or crowded, lower the supports or use one answer instead.")
        case .delay:
            return Experiment(lens: lens, title: "Throw one word into orbit", purpose: "Let a phrase end answer itself without washing out the next line.", minutes: 7, steps: [routing, "Insert \(delay) on the \(returnName). Set its wet output/mix to 100%, keeping the original dry source audible. " + tempoText + " Start feedback at 20%.", "Filter the return with a low cut near 200 Hz and a high cut near 5 kHz as audition starts. The repeats should tuck behind the original; stop filtering before they become dull or tiny.", "Show automation for the source’s send level. Keep the send down, raise it only across the chosen word, then drop it after the word. Leave the return up so existing repeats can decay.", "Compare 1/8 and dotted 1/8. Use fewer repeats if the next phrase gets crowded."], check: "The original word stays clear, the tail continues after the send drops, and the next line has room. Mute the return for a level-conscious comparison.")
        case .space:
            return Experiment(lens: lens, title: "A room behind the performance", purpose: "Hear how predelay separates an intimate source from a distant tail.", minutes: 6, steps: [routing, "Insert \(reverb) on the \(returnName), fully wet. Start with a small room or plate-like preset, about 1.2 s decay and 25 ms predelay. These are experiment values, not measurements of the reference.", "Bring the send up until you clearly hear the space, then back it off. Compare 0 ms with 25–45 ms predelay; listen for articulation in front of the tail.", "EQ the return: remove rumble and roll off enough top end to put the tail behind the source. Try a shorter decay during a dense verse and a longer one at an exposed ending."], check: "Mute the return. You should miss the depth more than a cloud of hiss. If words blur, reduce the send or decay before adding more EQ.")
        case .stereo:
            return Experiment(lens: lens, title: "Give the center something to hold", purpose: "Make the sides feel expansive by protecting a stable middle.", minutes: 5, steps: ["Keep kick, bass and your main lead near the center as a starting composition choice. Pick one pad, double or ambience return for width.", "Use independent performances or a stereo effect for the support. Begin with moderate panning; raising a width control on a mono duplicate cannot invent an independent performance.", "Automate the support wider or slightly louder at a hook, then pull it inward during the verse. Leave the lead anchor stable.", "Use your DAW’s mono monitoring or a mono-summing utility on the monitoring path. Compare the hook in stereo and mono."], check: "The main musical parts should survive mono. If the support vanishes unpleasantly, reduce widening or replace short-delay widening with a new performance.")
        case .arrangement:
            return Experiment(lens: lens, title: "Make the lift before it arrives", purpose: "Create a bigger entrance through subtraction and timing.", minutes: 8, steps: ["Mark an upcoming hook or section change in your own session. Listen to the preceding two bars as a setup.", "Mute one busy layer in the final bar: hats, a pad or a support vocal. Try removing the bass for just the last beat if the harmony permits.", "At the new section, restore the missing layer and introduce one new detail: a double, a higher texture or a wider ambience.", "Add a short automation fade around edits to avoid clicks. Compare with the original arrangement at the same master level."], check: "Can you feel the entrance with your eyes closed? If it feels like an accidental dropout, shorten the gap or keep one timing cue audible.")
        case .bass:
            return Experiment(lens: lens, title: "Let the kick open a small door", purpose: "Give kick and bass separate moments without thinning the whole low end.", minutes: 8, steps: ["Use separate kick and bass tracks in your own session. First try shortening overlapping bass notes or moving their starts slightly; judge the groove before adding processing.", "If masking remains, insert Compressor or Pro-C 2 on the bass. " + (studio ? "Enable its external sidechain and route a send from the kick to that sidechain." : "Choose the kick track or its bus in the compressor’s Side Chain menu."), "Start near 4:1, 2–5 ms attack and 80–150 ms release. Lower threshold until the kick produces roughly 1–3 dB of bass reduction. These are starting points; listen for clean recovery.", "Check that the kick reaches the detector without becoming a second audible kick path. Shorten release if the bass stays missing; lengthen it if recovery chatters."], check: "The kick is clearer, but the bass line still has its intended weight. Bypass at matched level; keep the unprocessed version if note editing already solved it.")
        case .dynamics:
            return Experiment(lens: lens, title: "Feel the release breathe", purpose: "Learn to hear the envelope instead of chasing a preset.", minutes: 6, steps: ["Choose an 8-bar drum or instrument bus in your session. Insert the stock Compressor or Pro-C 2 with automatic makeup gain off.", "Start at 2:1, 25 ms attack and 120 ms release. Lower threshold for about 2 dB of reduction on strong moments. Match output to bypass.", "Compare 60 ms and 250 ms release. Watch the reduction recover while listening for breathing, softened hits or a permanently pushed-back sound.", "Choose the smallest amount that gives the motion you want. If low hits make everything dip, investigate the detector filter or rebalance the low end."], check: "Keep the same loudness through the comparison. Compression should change movement or consistency, not win merely by being louder.")
        case .texture:
            return Experiment(lens: lens, title: "Make a shadow of the sound", purpose: "Add controlled grain underneath a clear source.", minutes: 7, steps: [routing, "Place a saturation or distortion processor on the \(returnName), followed by EQ. Use a stock processor or FabFilter Saturn. Keep this parallel path fully wet.", "Start its return fader all the way down. Increase drive until you hear an intentional character in solo, then filter roughly below 250 Hz and above 6 kHz as a first audition.", "Bring the return under the dry source. Stop while you mostly feel added density rather than hear a second fuzzy performance.", "Automate the return up only on an important phrase. Listen for extra hiss, harsh consonants and a softer transient."], check: "Mute the return at a similar overall level. If the dry performance loses clarity or the low end turns fuzzy, lower or remove the parallel layer.")
        }
    }

    func text(daw: DAW) -> String {
        "EAR EXPERIMENT — \(title)\n\(daw.rawValue) • \(minutes) min\n\n\(purpose)\n\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n") + "\n\nCHECK\n\(check)"
    }
}
