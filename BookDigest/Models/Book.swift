import SwiftUI

enum BookCategory: String, CaseIterable, Identifiable {
    case habits
    case focus
    case priorities
    case systems
    case leadership
    case startup
    case product
    case sales
    case careers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .habits:
            return "Habits"
        case .focus:
            return "Focus"
        case .priorities:
            return "Priorities"
        case .systems:
            return "Systems"
        case .leadership:
            return "Leadership"
        case .startup:
            return "Startup"
        case .product:
            return "Product"
        case .sales:
            return "Sales"
        case .careers:
            return "Careers"
        }
    }

    var subtitle: String {
        switch self {
        case .habits:
            return "Behavior change and consistency"
        case .focus:
            return "Attention and distraction control"
        case .priorities:
            return "Choosing what matters most"
        case .systems:
            return "Execution, planning, and operating rhythm"
        case .leadership:
            return "Managing people, influence, and effectiveness"
        case .startup:
            return "Building, testing, and scaling ventures"
        case .product:
            return "Product thinking, discovery, and delivery"
        case .sales:
            return "Persuasion, negotiation, and closing"
        case .careers:
            return "Career navigation and modern work paths"
        }
    }

    var systemImage: String {
        switch self {
        case .habits:
            return "repeat.circle"
        case .focus:
            return "scope"
        case .priorities:
            return "flag.circle"
        case .systems:
            return "slider.horizontal.3"
        case .leadership:
            return "person.3.sequence"
        case .startup:
            return "flame"
        case .product:
            return "shippingbox"
        case .sales:
            return "dollarsign.arrow.circlepath"
        case .careers:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }
}

extension Book {
    static func slug(fromTitle title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .split(separator: " ")
            .prefix(6)
            .joined(separator: "-")
    }
}

struct Book: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let author: String
    let angle: String
    let category: BookCategory
    let keywords: [String]
    let coverColors: [Color]
    // Known cover image URL (e.g. from an Open Library search hit). When set,
    // the cover service uses it directly instead of searching by title/author.
    var coverURL: URL?

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        let haystack = [
            title,
            shortTitle,
            author,
            angle,
            category.title
        ] + keywords

        let normalizedQuery = query.localizedLowercase
        return haystack.joined(separator: " ").localizedLowercase.contains(normalizedQuery)
    }

    static let catalog: [Book] = [
        Book(
            id: "atomic-habits",
            title: "Atomic Habits",
            shortTitle: "Atomic Habits",
            author: "James Clear",
            angle: "Tiny behavior changes, identity-based habits, and practical systems for compounding improvement.",
            category: .habits,
            keywords: ["behavior change", "consistency", "identity", "routines"],
            coverColors: [Color(red: 0.12, green: 0.16, blue: 0.18), Color(red: 0.88, green: 0.27, blue: 0.18)]
        ),
        Book(
            id: "power-of-habit",
            title: "The Power of Habit",
            shortTitle: "Power of Habit",
            author: "Charles Duhigg",
            angle: "The habit loop, cues and rewards, and how routines can be redesigned at the personal and organizational level.",
            category: .habits,
            keywords: ["habit loop", "behavior", "cue", "reward", "discipline"],
            coverColors: [Color(red: 0.18, green: 0.18, blue: 0.19), Color(red: 0.91, green: 0.80, blue: 0.29)]
        ),
        Book(
            id: "deep-work",
            title: "Deep Work",
            shortTitle: "Deep Work",
            author: "Cal Newport",
            angle: "Focused attention, distraction control, and designing workdays around cognitively demanding output.",
            category: .focus,
            keywords: ["focus", "concentration", "attention", "distraction"],
            coverColors: [Color(red: 0.03, green: 0.20, blue: 0.26), Color(red: 0.34, green: 0.72, blue: 0.72)]
        ),
        Book(
            id: "hyperfocus",
            title: "Hyperfocus",
            shortTitle: "Hyperfocus",
            author: "Chris Bailey",
            angle: "Attention management, deliberate concentration, and using intentional mind-wandering to support creativity.",
            category: .focus,
            keywords: ["attention", "concentration", "mind wandering", "creative focus"],
            coverColors: [Color(red: 0.11, green: 0.16, blue: 0.33), Color(red: 0.96, green: 0.56, blue: 0.18)]
        ),
        Book(
            id: "indistractable",
            title: "Indistractable",
            shortTitle: "Indistractable",
            author: "Nir Eyal",
            angle: "Internal triggers, distraction-proof planning, and practical tactics for protecting attention.",
            category: .focus,
            keywords: ["distraction", "attention", "technology", "traction", "focus"],
            coverColors: [Color(red: 0.12, green: 0.19, blue: 0.22), Color(red: 0.07, green: 0.74, blue: 0.63)]
        ),
        Book(
            id: "stolen-focus",
            title: "Stolen Focus",
            shortTitle: "Stolen Focus",
            author: "Johann Hari",
            angle: "Why attention erodes in modern life and what environmental and behavioral shifts help restore it.",
            category: .focus,
            keywords: ["attention crisis", "phones", "distraction", "modern work"],
            coverColors: [Color(red: 0.11, green: 0.13, blue: 0.18), Color(red: 0.98, green: 0.84, blue: 0.42)]
        ),
        Book(
            id: "essentialism",
            title: "Essentialism",
            shortTitle: "Essentialism",
            author: "Greg McKeown",
            angle: "Deliberate trade-offs, saying no, and focusing energy on the highest-value commitments.",
            category: .priorities,
            keywords: ["trade-offs", "saying no", "focus", "less but better"],
            coverColors: [Color(red: 0.09, green: 0.12, blue: 0.14), Color(red: 0.99, green: 0.98, blue: 0.96)]
        ),
        Book(
            id: "one-thing",
            title: "The ONE Thing",
            shortTitle: "The ONE Thing",
            author: "Gary Keller and Jay Papasan",
            angle: "Extreme prioritization, time blocking, and using a focusing question to reduce scattered effort.",
            category: .priorities,
            keywords: ["priority", "time blocking", "multitasking", "leverage"],
            coverColors: [Color(red: 0.08, green: 0.08, blue: 0.10), Color(red: 0.92, green: 0.60, blue: 0.20)]
        ),
        Book(
            id: "make-time",
            title: "Make Time",
            shortTitle: "Make Time",
            author: "Jake Knapp and John Zeratsky",
            angle: "Daily highlights, energy-aware scheduling, and practical defaults for reclaiming time from busywork.",
            category: .priorities,
            keywords: ["daily highlight", "calendar", "energy", "time design"],
            coverColors: [Color(red: 0.13, green: 0.15, blue: 0.18), Color(red: 0.98, green: 0.73, blue: 0.18)]
        ),
        Book(
            id: "eat-that-frog",
            title: "Eat That Frog!",
            shortTitle: "Eat That Frog!",
            author: "Brian Tracy",
            angle: "Anti-procrastination tactics centered on tackling the most important task before everything else.",
            category: .priorities,
            keywords: ["procrastination", "time management", "important tasks", "execution"],
            coverColors: [Color(red: 0.05, green: 0.20, blue: 0.26), Color(red: 0.56, green: 0.81, blue: 0.36)]
        ),
        Book(
            id: "slow-productivity",
            title: "Slow Productivity",
            shortTitle: "Slow Productivity",
            author: "Cal Newport",
            angle: "A calmer approach to output built around fewer commitments, higher quality, and a sustainable pace.",
            category: .priorities,
            keywords: ["sustainable pace", "quality", "workload", "calm ambition"],
            coverColors: [Color(red: 0.14, green: 0.17, blue: 0.25), Color(red: 0.71, green: 0.78, blue: 0.85)]
        ),
        Book(
            id: "four-thousand-weeks",
            title: "Four Thousand Weeks",
            shortTitle: "Four Thousand Weeks",
            author: "Oliver Burkeman",
            angle: "Time management reframed through finitude, helping readers prioritize meaning over endless optimization.",
            category: .priorities,
            keywords: ["time management", "finitude", "meaning", "limitations"],
            coverColors: [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.78, green: 0.58, blue: 0.24)]
        ),
        Book(
            id: "getting-things-done",
            title: "Getting Things Done",
            shortTitle: "Getting Things Done",
            author: "David Allen",
            angle: "Capture, clarify, organize, review, and execute work with lower mental friction.",
            category: .systems,
            keywords: ["GTD", "workflow", "capture", "reviews", "task management"],
            coverColors: [Color(red: 0.10, green: 0.16, blue: 0.30), Color(red: 0.18, green: 0.48, blue: 0.92)]
        ),
        Book(
            id: "smarter-faster-better",
            title: "Smarter Faster Better",
            shortTitle: "Smarter Faster Better",
            author: "Charles Duhigg",
            angle: "The science of productive teams and individuals across motivation, goals, decision-making, and innovation.",
            category: .systems,
            keywords: ["motivation", "decision making", "teams", "performance"],
            coverColors: [Color(red: 0.12, green: 0.18, blue: 0.24), Color(red: 0.97, green: 0.46, blue: 0.17)]
        ),
        Book(
            id: "organized-mind",
            title: "The Organized Mind",
            shortTitle: "The Organized Mind",
            author: "Daniel J. Levitin",
            angle: "Cognitive science for organizing information, decisions, and environments in a world of overload.",
            category: .systems,
            keywords: ["cognitive load", "organization", "information", "decision fatigue"],
            coverColors: [Color(red: 0.17, green: 0.18, blue: 0.20), Color(red: 0.87, green: 0.89, blue: 0.90)]
        ),
        Book(
            id: "measure-what-matters",
            title: "Measure What Matters",
            shortTitle: "Measure What Matters",
            author: "John Doerr",
            angle: "OKRs, measurable execution, and how clear objectives align teams around the highest-impact work.",
            category: .systems,
            keywords: ["OKRs", "goals", "alignment", "measurement", "execution"],
            coverColors: [Color(red: 0.06, green: 0.21, blue: 0.33), Color(red: 0.96, green: 0.35, blue: 0.34)]
        ),
        Book(
            id: "high-output-management",
            title: "High Output Management",
            shortTitle: "High Output Mgmt",
            author: "Andrew S. Grove",
            angle: "Managerial leverage, operating cadence, one-on-ones, and systems thinking from Intel's former CEO.",
            category: .systems,
            keywords: ["management", "leverage", "operations", "one-on-ones"],
            coverColors: [Color(red: 0.07, green: 0.11, blue: 0.22), Color(red: 0.85, green: 0.28, blue: 0.25)]
        ),
        Book(
            id: "seven-habits",
            title: "The 7 Habits of Highly Effective People",
            shortTitle: "7 Habits",
            author: "Stephen R. Covey",
            angle: "Principle-centered effectiveness across personal responsibility, priorities, and relationships.",
            category: .leadership,
            keywords: ["effectiveness", "principles", "relationships", "personal leadership"],
            coverColors: [Color(red: 0.18, green: 0.24, blue: 0.14), Color(red: 0.60, green: 0.70, blue: 0.27)]
        ),
        Book(
            id: "radical-candor",
            title: "Radical Candor",
            shortTitle: "Radical Candor",
            author: "Kim Scott",
            angle: "Clear feedback, caring directly, and building teams that challenge each other well.",
            category: .leadership,
            keywords: ["feedback", "management", "communication", "team culture"],
            coverColors: [Color(red: 0.06, green: 0.33, blue: 0.42), Color(red: 0.95, green: 0.56, blue: 0.22)]
        ),
        Book(
            id: "effective-executive",
            title: "The Effective Executive",
            shortTitle: "Effective Executive",
            author: "Peter F. Drucker",
            angle: "Executive effectiveness through time awareness, contribution, strengths, and disciplined decision-making.",
            category: .leadership,
            keywords: ["executive", "decision making", "strengths", "management"],
            coverColors: [Color(red: 0.18, green: 0.12, blue: 0.08), Color(red: 0.86, green: 0.62, blue: 0.36)]
        ),
        Book(
            id: "so-good-they-cant-ignore-you",
            title: "So Good They Can't Ignore You",
            shortTitle: "So Good They Can't Ignore You",
            author: "Cal Newport",
            angle: "Career capital, deliberate skill-building, and why craftsmanship beats passion-first advice.",
            category: .leadership,
            keywords: ["career capital", "craftsmanship", "skills", "career strategy"],
            coverColors: [Color(red: 0.14, green: 0.15, blue: 0.18), Color(red: 0.63, green: 0.80, blue: 0.95)]
        ),
        Book(
            id: "lean-startup",
            title: "The Lean Startup",
            shortTitle: "Lean Startup",
            author: "Eric Ries",
            angle: "Validated learning, build-measure-learn loops, and iterative experimentation for startups and new products.",
            category: .startup,
            keywords: ["MVP", "experimentation", "validated learning", "innovation"],
            coverColors: [Color(red: 0.11, green: 0.12, blue: 0.15), Color(red: 0.72, green: 0.77, blue: 0.80)]
        ),
        Book(
            id: "zero-to-one",
            title: "Zero to One",
            shortTitle: "Zero to One",
            author: "Peter Thiel and Blake Masters",
            angle: "Contrarian startup thinking, monopoly-style differentiation, and creating companies that move from novelty to scale.",
            category: .startup,
            keywords: ["competition", "innovation", "strategy", "founders"],
            coverColors: [Color(red: 0.05, green: 0.18, blue: 0.31), Color(red: 0.60, green: 0.85, blue: 0.98)]
        ),
        Book(
            id: "hard-thing-about-hard-things",
            title: "The Hard Thing About Hard Things",
            shortTitle: "Hard Thing About Hard Things",
            author: "Ben Horowitz",
            angle: "Operating through crisis, layoffs, wartime leadership, and the messy realities of company building.",
            category: .startup,
            keywords: ["founder", "crisis", "leadership", "company building"],
            coverColors: [Color(red: 0.13, green: 0.13, blue: 0.14), Color(red: 0.95, green: 0.83, blue: 0.22)]
        ),
        Book(
            id: "mom-test",
            title: "The Mom Test",
            shortTitle: "The Mom Test",
            author: "Rob Fitzpatrick",
            angle: "Customer conversations that uncover real demand instead of polite but misleading validation.",
            category: .startup,
            keywords: ["customer discovery", "interviews", "validation", "research"],
            coverColors: [Color(red: 0.10, green: 0.19, blue: 0.15), Color(red: 0.73, green: 0.88, blue: 0.53)]
        ),
        Book(
            id: "art-of-the-deal",
            title: "The Art of the Deal",
            shortTitle: "Art of the Deal",
            author: "Donald J. Trump",
            angle: "Negotiation posture, deal framing, leverage, and the public persona behind the lessons.",
            category: .sales,
            keywords: ["negotiation", "dealmaking", "leverage", "persuasion"],
            coverColors: [Color(red: 0.17, green: 0.21, blue: 0.42), Color(red: 0.74, green: 0.11, blue: 0.17)]
        ),
        Book(
            id: "inspired",
            title: "Inspired",
            shortTitle: "Inspired",
            author: "Marty Cagan",
            angle: "How strong product teams discover, shape, and launch technology products customers actually want.",
            category: .product,
            keywords: ["product management", "discovery", "roadmap", "product team"],
            coverColors: [Color(red: 0.10, green: 0.14, blue: 0.26), Color(red: 0.96, green: 0.39, blue: 0.28)]
        ),
        Book(
            id: "empowered",
            title: "Empowered",
            shortTitle: "Empowered",
            author: "Marty Cagan and Chris Jones",
            angle: "Product leadership, coaching strong teams, and creating the conditions for empowered execution.",
            category: .product,
            keywords: ["product leadership", "coaching", "teams", "management"],
            coverColors: [Color(red: 0.12, green: 0.17, blue: 0.30), Color(red: 0.22, green: 0.63, blue: 0.96)]
        ),
        Book(
            id: "continuous-discovery-habits",
            title: "Continuous Discovery Habits",
            shortTitle: "Continuous Discovery Habits",
            author: "Teresa Torres",
            angle: "Ongoing customer discovery, opportunity solution trees, and evidence-based product decisions.",
            category: .product,
            keywords: ["discovery", "customer research", "opportunity solution tree", "product"],
            coverColors: [Color(red: 0.13, green: 0.14, blue: 0.20), Color(red: 0.96, green: 0.71, blue: 0.28)]
        ),
        Book(
            id: "obviously-awesome",
            title: "Obviously Awesome",
            shortTitle: "Obviously Awesome",
            author: "April Dunford",
            angle: "Category design and positioning so customers understand why your product matters and for whom.",
            category: .product,
            keywords: ["positioning", "messaging", "market", "category"],
            coverColors: [Color(red: 0.14, green: 0.12, blue: 0.19), Color(red: 0.82, green: 0.42, blue: 0.94)]
        ),
        Book(
            id: "never-split-the-difference",
            title: "Never Split the Difference",
            shortTitle: "Never Split the Difference",
            author: "Chris Voss",
            angle: "Tactical empathy, calibrated questions, and high-stakes negotiation methods translated into daily business use.",
            category: .sales,
            keywords: ["negotiation", "empathy", "questions", "closing"],
            coverColors: [Color(red: 0.09, green: 0.10, blue: 0.14), Color(red: 0.94, green: 0.50, blue: 0.15)]
        ),
        Book(
            id: "spin-selling",
            title: "SPIN Selling",
            shortTitle: "SPIN Selling",
            author: "Neil Rackham",
            angle: "Consultative selling through situation, problem, implication, and need-payoff questioning.",
            category: .sales,
            keywords: ["sales process", "questioning", "enterprise sales", "consultative selling"],
            coverColors: [Color(red: 0.11, green: 0.15, blue: 0.25), Color(red: 0.95, green: 0.67, blue: 0.19)]
        ),
        Book(
            id: "influence",
            title: "Influence",
            shortTitle: "Influence",
            author: "Robert B. Cialdini",
            angle: "Core persuasion principles such as reciprocity, social proof, authority, and commitment.",
            category: .sales,
            keywords: ["persuasion", "psychology", "social proof", "authority"],
            coverColors: [Color(red: 0.12, green: 0.16, blue: 0.20), Color(red: 0.81, green: 0.21, blue: 0.24)]
        ),
        Book(
            id: "to-sell-is-human",
            title: "To Sell Is Human",
            shortTitle: "To Sell Is Human",
            author: "Daniel H. Pink",
            angle: "A broader view of selling as influence, clarity, and service across modern knowledge work.",
            category: .sales,
            keywords: ["influence", "communication", "clarity", "service"],
            coverColors: [Color(red: 0.09, green: 0.20, blue: 0.31), Color(red: 0.91, green: 0.32, blue: 0.30)]
        ),
        Book(
            id: "squiggly-careers",
            title: "The Squiggly Career",
            shortTitle: "Squiggly Career",
            author: "Helen Tupper and Sarah Ellis",
            angle: "Navigating non-linear career growth through strengths, values, experiments, and adaptable confidence.",
            category: .careers,
            keywords: ["career growth", "nonlinear", "strengths", "experiments"],
            coverColors: [Color(red: 0.14, green: 0.15, blue: 0.20), Color(red: 0.98, green: 0.41, blue: 0.60)]
        ),
        Book(
            id: "designing-your-life",
            title: "Designing Your Life",
            shortTitle: "Designing Your Life",
            author: "Bill Burnett and Dave Evans",
            angle: "Design-thinking applied to career decisions, prototypes, and building a more intentional life path.",
            category: .careers,
            keywords: ["career design", "prototyping", "decision making", "life design"],
            coverColors: [Color(red: 0.12, green: 0.18, blue: 0.23), Color(red: 0.99, green: 0.75, blue: 0.18)]
        ),
        Book(
            id: "working-identity",
            title: "Working Identity",
            shortTitle: "Working Identity",
            author: "Herminia Ibarra",
            angle: "Reinventing your career through experiments, networks, and iterative identity shifts rather than one big leap.",
            category: .careers,
            keywords: ["career change", "identity", "network", "reinvention"],
            coverColors: [Color(red: 0.11, green: 0.13, blue: 0.17), Color(red: 0.65, green: 0.80, blue: 0.94)]
        )
    ]
}

extension Book {
    var coverImageName: String {
        "cover-\(id)"
    }

    var keyIdeaCount: Int {
        min(max(contentsItems.count + 1, 4), 7)
    }

    var deck: String {
        category.title
    }

    var contentsItems: [String] {
        ContentsStorage.load(for: id) ?? []
    }

    var categoryShelfTitle: String {
        switch category {
        case .habits:
            return "Currently Reading"
        case .focus, .priorities, .systems:
            return "The Catalogue"
        case .leadership:
            return "Leadership Shelf"
        case .startup:
            return "Startup Shelf"
        case .product:
            return "Product Shelf"
        case .sales:
            return "Sales Shelf"
        case .careers:
            return "Career Shelf"
        }
    }

}
