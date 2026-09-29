import Foundation

/// How an exercise is matched against what the user typed.
///
/// The library holds 400+ entries and the old search was a single
/// `name.contains(query)`, which meant the query had to be a literal substring
/// of the name. That fails the way people actually type at the gym: "lat pull
/// down" found nothing because the catalog spells it "Lat Pulldown", "seated
/// row" skipped "Seated Cable Row" because of the word wedged in the middle,
/// and "incline db press" found nothing at all.
///
/// So matching happens on three fronts, cheapest first:
///
/// 1. **Token prefixes.** Every word you type has to prefix some word in the
///    entry — not the whole query in a row. "seated row" reaches "Seated Cable
///    Row", "leg ext" reaches "Leg Extension".
/// 2. **Aliases.** Gym shorthand is folded to the catalog's own vocabulary on
///    both sides, alongside the literal words, so "db" and "dumbbell" are the same word by the time they're
///    compared.
/// 3. **The squashed form.** Spaces and punctuation stripped entirely, matched
///    as a substring. This is what makes "pulldown" and "pull down" — and
///    "ezbar" and "EZ-Bar" — the same query.
enum ExerciseSearch {

    // MARK: - Vocabulary

    /// Gym shorthand folded to the word the catalog uses. Applied to the
    /// indexed text *and* the query, so both sides meet in the middle and
    /// neither spelling has to be the one that's stored. The literal spelling
    /// is kept beside the folded one on both sides, so an alias only ever adds
    /// matches and never takes one away.
    ///
    /// Only genuine abbreviations and spelling splits belong here. Singulars
    /// and plurals are already handled — matching is by prefix, so "shoulder"
    /// reaches "shoulders" without an entry.
    static let aliases: [String: String] = [
        // Equipment
        "db": "dumbbell", "dbs": "dumbbell", "dumbell": "dumbbell", "dumbbells": "dumbbell",
        "bb": "barbell", "kb": "kettlebell", "hs": "hammer strength",
        "bw": "bodyweight", "smithmachine": "smith",

        // Muscles — folded to whichever form the catalog spells them in.
        "bicep": "biceps", "bis": "biceps",
        "tricep": "triceps", "tris": "triceps",
        "quad": "quads", "quadricep": "quads", "quadriceps": "quads",
        "ham": "hamstrings", "hams": "hamstrings", "hamstring": "hamstrings",
        "glute": "glutes", "calves": "calf", "pecs": "pec",
        "abdominals": "abs", "abdominal": "abs",

        // Movements
        "ohp": "overhead press", "rdl": "romanian deadlift",
        "sldl": "stiff leg deadlift", "dl": "deadlift",
        "ext": "extension", "exts": "extension",
        "flye": "fly", "flyes": "fly", "flies": "fly",
    ]

    // MARK: - Normalising

    /// Lowercased, punctuation flattened to spaces, runs collapsed. "EZ-Bar
    /// Preacher Curl" and "ez bar preacher curl" land on the same string.
    static func normalise(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Normalised, then every word put through the alias table. An alias may
    /// expand to several words ("ohp" → "overhead press"), so the result can be
    /// longer than what went in.
    static func tokenise(_ text: String) -> [String] {
        normalise(text).split(separator: " ").flatMap(expansion(of:))
    }

    /// What one typed or indexed word stands for once the alias table has had
    /// its say. A word with no alias stands for itself.
    static func expansion(of word: Substring) -> [String] {
        guard let alias = aliases[String(word)] else { return [String(word)] }
        return alias.split(separator: " ").map(String.init)
    }

    /// Shortest half-typed word that is allowed to stand for an alias it only
    /// begins. Below this, two letters would drag in every abbreviation.
    private static let partialAliasLength = 3

    /// Every alias expansion a typed word could mean: the one for the word
    /// itself, and the ones for any alias it is the beginning of.
    static func readings(of word: String) -> [[String]] {
        var readings = [expansion(of: Substring(word))]
        if word.count >= partialAliasLength {
            for (key, value) in aliases where key != word && key.hasPrefix(word) {
                readings.append(value.split(separator: " ").map(String.init))
            }
        }
        return readings
    }

    /// The normalised words with no alias applied — what was literally typed,
    /// or literally spelled in the catalog.
    static func rawWords(_ text: String) -> [String] {
        normalise(text).split(separator: " ").map(String.init)
    }

    // MARK: - The index

    /// One exercise's searchable text, prepared once when the catalog loads
    /// rather than rebuilt on every keystroke across 400+ entries.
    ///
    /// Every field exists twice, aliased and literal. An alias must only ever
    /// widen what a query reaches: folding "calves" to "calf" in the index
    /// alone meant "calv" prefixed nothing, and folding "ham" to "hamstrings"
    /// in the query alone hid Hammer Curl behind it.
    struct Entry {
        /// The name's own words, in order, aliased — what a phrase match runs along.
        let nameTokens: [String]
        /// The name's words as spelled, for a phrase typed in the catalog's own words.
        let nameWords: [String]
        /// The name with every separator removed, for "pulldown" ↔ "pull down".
        let squashedName: String
        /// The same, from the literal words.
        let squashedWords: String
        /// Name, muscles and equipment together, aliased and literal — what a
        /// word has to appear in somewhere for the entry to match at all.
        let allTokens: Set<String>

        init(exercise: CatalogExercise) {
            let name = ExerciseSearch.tokenise(exercise.name)
            let words = ExerciseSearch.rawWords(exercise.name)
            nameTokens = name
            nameWords = words
            squashedName = name.joined()
            squashedWords = words.joined()
            let fields = exercise.muscleGroups + exercise.equipment + [exercise.category]
            allTokens = Set(name).union(words)
                .union(fields.flatMap(ExerciseSearch.tokenise))
                .union(fields.flatMap(ExerciseSearch.rawWords))
        }
    }

    /// A query, prepared once per search rather than once per candidate.
    struct Query {
        /// Each typed word with every reading the alias table gives it. A word
        /// matches if the word itself or any reading does, so "ham" reaches both
        /// hamstrings and Hammer, and a half-typed "fli" reaches the "Fly"
        /// entries through "flies" before the word is finished.
        let terms: [(raw: String, readings: [[String]])]
        /// The query aliased word by word, for the phrase and squashed matches.
        let tokens: [String]
        let words: [String]
        let squashed: String
        let squashedWords: String
        var isEmpty: Bool { terms.isEmpty }

        init(_ text: String) {
            words = ExerciseSearch.rawWords(text)
            terms = words.map { ($0, ExerciseSearch.readings(of: $0)) }
            tokens = words.flatMap { ExerciseSearch.expansion(of: Substring($0)) }
            squashed = tokens.joined()
            squashedWords = words.joined()
        }
    }

    // MARK: - Scoring

    /// How well an entry answers a query. `nil` means it doesn't — the caller
    /// drops it rather than showing a weak match.
    ///
    /// The bands exist to settle ties in the order a person would: the exercise
    /// whose *name* you typed beats one that merely works the same muscle, and
    /// a match at the front of the name beats one buried in the middle. That's
    /// what puts "Seated Cable Row" above "Banded Seated Row" for "seated row".
    static func score(entry: Entry, query: Query) -> Int? {
        guard !query.isEmpty else { return 1 }

        // Every word has to land somewhere, or the whole query has to appear
        // as one run of characters in the name.
        let everyWordMatches = query.terms.allSatisfy { term in
            matches(term, in: entry.allTokens)
        }
        let squashedMatches = entry.squashedName.contains(query.squashed)
            || entry.squashedWords.contains(query.squashedWords)
        guard everyWordMatches || squashedMatches else { return nil }

        if entry.squashedName == query.squashed || entry.squashedWords == query.squashedWords { return 100 }
        if entry.squashedName.hasPrefix(query.squashed)
            || entry.squashedWords.hasPrefix(query.squashedWords) { return 95 }

        let aliased = phrasePosition(of: query.tokens, in: entry.nameTokens)
        let literal = phrasePosition(of: query.words, in: entry.nameWords)
        switch [aliased, literal].compactMap({ $0 }).min() {
        case 0: return 90          // the name opens with what you typed
        case .some: return 85      // the words run together further along
        case nil: break
        }

        let nameTokens = Set(entry.nameTokens).union(entry.nameWords)
        let everyWordInName = query.terms.allSatisfy { matches($0, in: nameTokens) }
        if everyWordInName { return 80 }
        if squashedMatches { return 70 }
        return 50                  // matched on muscle or equipment alone
    }

    /// Whether a typed word lands in a set of entry words, read either way: as
    /// typed, or as its alias says. Prefix matching on the typed form is what
    /// keeps a half-typed word ("calv") alive after the alias table would only
    /// have recognised the finished one.
    private static func matches(_ term: (raw: String, readings: [[String]]), in tokens: Set<String>) -> Bool {
        if tokens.contains(where: { $0.hasPrefix(term.raw) }) { return true }
        return term.readings.contains { reading in
            reading.allSatisfy { part in tokens.contains { $0.hasPrefix(part) } }
        }
    }

    /// Where the query's words appear as a consecutive run in the name, if they
    /// do. Words match by prefix, so "leg ext" runs along "leg extension".
    private static func phrasePosition(of query: [String], in name: [String]) -> Int? {
        guard !query.isEmpty, query.count <= name.count else { return nil }
        for start in 0...(name.count - query.count) {
            let fits = query.indices.allSatisfy { name[start + $0].hasPrefix(query[$0]) }
            if fits { return start }
        }
        return nil
    }
}
