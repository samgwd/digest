#!/usr/bin/env python3
"""Resolve Open Library cover IDs for curated book lists and emit CuratedBooks.swift."""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

SCRATCH = os.path.dirname(os.path.abspath(__file__))
CACHE_PATH = os.path.join(SCRATCH, "cover_cache.json")
SWIFT_OUT = "/Users/samgreenwood/code/personal_development/book-digest/BookDigest/Models/CuratedBooks.swift"

# (category, title, author) — 50 per category
BOOKS = [
    # ---------------- HABITS ----------------
    ("habits", "Atomic Habits", "James Clear"),
    ("habits", "The Power of Habit", "Charles Duhigg"),
    ("habits", "Tiny Habits", "BJ Fogg"),
    ("habits", "Good Habits, Bad Habits", "Wendy Wood"),
    ("habits", "Better Than Before", "Gretchen Rubin"),
    ("habits", "The Four Tendencies", "Gretchen Rubin"),
    ("habits", "Mini Habits", "Stephen Guise"),
    ("habits", "Elastic Habits", "Stephen Guise"),
    ("habits", "High Performance Habits", "Brendon Burchard"),
    ("habits", "The Compound Effect", "Darren Hardy"),
    ("habits", "The Slight Edge", "Jeff Olson"),
    ("habits", "The Willpower Instinct", "Kelly McGonigal"),
    ("habits", "Willpower", "Roy F. Baumeister and John Tierney"),
    ("habits", "How to Change", "Katy Milkman"),
    ("habits", "Stick with It", "Sean D. Young"),
    ("habits", "Triggers", "Marshall Goldsmith"),
    ("habits", "The 5 Second Rule", "Mel Robbins"),
    ("habits", "The Miracle Morning", "Hal Elrod"),
    ("habits", "Discipline Equals Freedom", "Jocko Willink"),
    ("habits", "Can't Hurt Me", "David Goggins"),
    ("habits", "The Now Habit", "Neil Fiore"),
    ("habits", "Solving the Procrastination Puzzle", "Timothy A. Pychyl"),
    ("habits", "Drive", "Daniel H. Pink"),
    ("habits", "Switch", "Chip Heath and Dan Heath"),
    ("habits", "Nudge", "Richard H. Thaler and Cass R. Sunstein"),
    ("habits", "The Power of Full Engagement", "Jim Loehr and Tony Schwartz"),
    ("habits", "One Small Step Can Change Your Life", "Robert Maurer"),
    ("habits", "Habit Stacking", "S.J. Scott"),
    ("habits", "Make Your Bed", "William H. McRaven"),
    ("habits", "Awaken the Giant Within", "Tony Robbins"),
    ("habits", "Grit", "Angela Duckworth"),
    ("habits", "Peak", "Anders Ericsson and Robert Pool"),
    ("habits", "The Talent Code", "Daniel Coyle"),
    ("habits", "Mindset", "Carol S. Dweck"),
    ("habits", "The Practicing Mind", "Thomas M. Sterner"),
    ("habits", "Daily Rituals", "Mason Currey"),
    ("habits", "Breaking the Habit of Being Yourself", "Joe Dispenza"),
    ("habits", "Dopamine Nation", "Anna Lembke"),
    ("habits", "Unwinding Anxiety", "Judson Brewer"),
    ("habits", "The Craving Mind", "Judson Brewer"),
    ("habits", "Superhuman by Habit", "Tynan"),
    ("habits", "The War of Art", "Steven Pressfield"),
    ("habits", "Finish", "Jon Acuff"),
    ("habits", "The Happiness Advantage", "Shawn Achor"),
    ("habits", "The Motivation Myth", "Jeff Haden"),
    ("habits", "Rewire", "Richard O'Connor"),
    ("habits", "The Molecule of More", "Daniel Z. Lieberman and Michael E. Long"),
    ("habits", "Hardwiring Happiness", "Rick Hanson"),
    ("habits", "Two Awesome Hours", "Josh Davis"),
    ("habits", "Feel-Good Productivity", "Ali Abdaal"),
    # ---------------- FOCUS ----------------
    ("focus", "Deep Work", "Cal Newport"),
    ("focus", "Indistractable", "Nir Eyal"),
    ("focus", "Stolen Focus", "Johann Hari"),
    ("focus", "Hyperfocus", "Chris Bailey"),
    ("focus", "Digital Minimalism", "Cal Newport"),
    ("focus", "A World Without Email", "Cal Newport"),
    ("focus", "Flow", "Mihaly Csikszentmihalyi"),
    ("focus", "Finding Flow", "Mihaly Csikszentmihalyi"),
    ("focus", "The Shallows", "Nicholas Carr"),
    ("focus", "Attention Span", "Gloria Mark"),
    ("focus", "Free to Focus", "Michael Hyatt"),
    ("focus", "The Distracted Mind", "Adam Gazzaley and Larry D. Rosen"),
    ("focus", "Rapt", "Winifred Gallagher"),
    ("focus", "Focus", "Daniel Goleman"),
    ("focus", "The Rise of Superman", "Steven Kotler"),
    ("focus", "The Art of Impossible", "Steven Kotler"),
    ("focus", "Limitless", "Jim Kwik"),
    ("focus", "Peak Performance", "Brad Stulberg and Steve Magness"),
    ("focus", "Do Nothing", "Celeste Headlee"),
    ("focus", "How to Break Up with Your Phone", "Catherine Price"),
    ("focus", "10% Happier", "Dan Harris"),
    ("focus", "The Miracle of Mindfulness", "Thich Nhat Hanh"),
    ("focus", "Wherever You Go, There You Are", "Jon Kabat-Zinn"),
    ("focus", "Search Inside Yourself", "Chade-Meng Tan"),
    ("focus", "Altered Traits", "Daniel Goleman and Richard J. Davidson"),
    ("focus", "The Attention Merchants", "Tim Wu"),
    ("focus", "Irresistible", "Adam Alter"),
    ("focus", "Mindfulness in Plain English", "Bhante Henepola Gunaratana"),
    ("focus", "Zen Mind, Beginner's Mind", "Shunryu Suzuki"),
    ("focus", "The Power of Now", "Eckhart Tolle"),
    ("focus", "Singletasking", "Devora Zack"),
    ("focus", "The Twelve Monotasks", "Thatcher Wine"),
    ("focus", "The Joy of Missing Out", "Tonya Dalton"),
    ("focus", "Bored and Brilliant", "Manoush Zomorodi"),
    ("focus", "Reclaiming Conversation", "Sherry Turkle"),
    ("focus", "Alone Together", "Sherry Turkle"),
    ("focus", "In Praise of Slowness", "Carl Honoré"),
    ("focus", "The Ruthless Elimination of Hurry", "John Mark Comer"),
    ("focus", "Stillness Is the Key", "Ryan Holiday"),
    ("focus", "24/6", "Tiffany Shlain"),
    ("focus", "The Extended Mind", "Annie Murphy Paul"),
    ("focus", "Your Brain at Work", "David Rock"),
    ("focus", "Driven to Distraction", "Edward M. Hallowell and John J. Ratey"),
    ("focus", "ADHD 2.0", "Edward M. Hallowell and John J. Ratey"),
    ("focus", "Scattered Minds", "Gabor Maté"),
    ("focus", "Why We Sleep", "Matthew Walker"),
    ("focus", "Rest", "Alex Soojung-Kim Pang"),
    ("focus", "The Inner Game of Tennis", "W. Timothy Gallwey"),
    ("focus", "The Mindful Athlete", "George Mumford"),
    ("focus", "The Power of Concentration", "Theron Q. Dumont"),
    # ---------------- PRIORITIES ----------------
    ("priorities", "Essentialism", "Greg McKeown"),
    ("priorities", "Effortless", "Greg McKeown"),
    ("priorities", "The ONE Thing", "Gary Keller and Jay Papasan"),
    ("priorities", "Four Thousand Weeks", "Oliver Burkeman"),
    ("priorities", "Make Time", "Jake Knapp and John Zeratsky"),
    ("priorities", "Eat That Frog!", "Brian Tracy"),
    ("priorities", "Slow Productivity", "Cal Newport"),
    ("priorities", "First Things First", "Stephen R. Covey"),
    ("priorities", "The 80/20 Principle", "Richard Koch"),
    ("priorities", "168 Hours", "Laura Vanderkam"),
    ("priorities", "Tranquility by Tuesday", "Laura Vanderkam"),
    ("priorities", "When", "Daniel H. Pink"),
    ("priorities", "The Dip", "Seth Godin"),
    ("priorities", "Hell Yeah or No", "Derek Sivers"),
    ("priorities", "Subtract", "Leidy Klotz"),
    ("priorities", "Die with Zero", "Bill Perkins"),
    ("priorities", "The Top Five Regrets of the Dying", "Bronnie Ware"),
    ("priorities", "A Guide to the Good Life", "William B. Irvine"),
    ("priorities", "Boundaries", "Henry Cloud and John Townsend"),
    ("priorities", "The Lazy Genius Way", "Kendra Adachi"),
    ("priorities", "The Gap and the Gain", "Dan Sullivan and Benjamin Hardy"),
    ("priorities", "10x Is Easier Than 2x", "Dan Sullivan and Benjamin Hardy"),
    ("priorities", "Procrastinate on Purpose", "Rory Vaden"),
    ("priorities", "The 5 Choices", "Kory Kogon, Adam Merrill, and Leena Rinne"),
    ("priorities", "Time Management from the Inside Out", "Julie Morgenstern"),
    ("priorities", "Thinking in Bets", "Annie Duke"),
    ("priorities", "Quit", "Annie Duke"),
    ("priorities", "Decisive", "Chip Heath and Dan Heath"),
    ("priorities", "The Paradox of Choice", "Barry Schwartz"),
    ("priorities", "Predictably Irrational", "Dan Ariely"),
    ("priorities", "Margin", "Richard A. Swenson"),
    ("priorities", "How to Do Nothing", "Jenny Odell"),
    ("priorities", "Meditations", "Marcus Aurelius"),
    ("priorities", "The Almanack of Naval Ravikant", "Eric Jorgenson"),
    ("priorities", "Clear Thinking", "Shane Parrish"),
    ("priorities", "The Great Mental Models", "Shane Parrish and Rhiannon Beaubien"),
    ("priorities", "Buy Back Your Time", "Dan Martell"),
    ("priorities", "Who Not How", "Dan Sullivan and Benjamin Hardy"),
    ("priorities", "The 4-Hour Workweek", "Timothy Ferriss"),
    ("priorities", "Overwhelmed", "Brigid Schulte"),
    ("priorities", "Time Smart", "Ashley Whillans"),
    ("priorities", "Happier Hour", "Cassie Holmes"),
    ("priorities", "The Time Paradox", "Philip Zimbardo and John Boyd"),
    ("priorities", "Your Money or Your Life", "Vicki Robin and Joe Dominguez"),
    ("priorities", "The Psychology of Money", "Morgan Housel"),
    ("priorities", "Enough", "John C. Bogle"),
    ("priorities", "Wanting", "Luke Burgis"),
    ("priorities", "The Second Mountain", "David Brooks"),
    ("priorities", "Man's Search for Meaning", "Viktor E. Frankl"),
    ("priorities", "The Obstacle Is the Way", "Ryan Holiday"),
    # ---------------- SYSTEMS ----------------
    ("systems", "Getting Things Done", "David Allen"),
    ("systems", "Measure What Matters", "John Doerr"),
    ("systems", "High Output Management", "Andrew S. Grove"),
    ("systems", "Smarter Faster Better", "Charles Duhigg"),
    ("systems", "The Organized Mind", "Daniel J. Levitin"),
    ("systems", "The Checklist Manifesto", "Atul Gawande"),
    ("systems", "Building a Second Brain", "Tiago Forte"),
    ("systems", "How to Take Smart Notes", "Sönke Ahrens"),
    ("systems", "Algorithms to Live By", "Brian Christian and Tom Griffiths"),
    ("systems", "Thinking in Systems", "Donella H. Meadows"),
    ("systems", "The Fifth Discipline", "Peter M. Senge"),
    ("systems", "Principles", "Ray Dalio"),
    ("systems", "Traction: Get a Grip on Your Business", "Gino Wickman"),
    ("systems", "The E-Myth Revisited", "Michael E. Gerber"),
    ("systems", "Work the System", "Sam Carpenter"),
    ("systems", "The Goal", "Eliyahu M. Goldratt"),
    ("systems", "The Phoenix Project", "Gene Kim, Kevin Behr, and George Spafford"),
    ("systems", "The Toyota Way", "Jeffrey K. Liker"),
    ("systems", "Lean Thinking", "James P. Womack and Daniel T. Jones"),
    ("systems", "Scrum: The Art of Doing Twice the Work in Half the Time", "Jeff Sutherland"),
    ("systems", "The 4 Disciplines of Execution", "Chris McChesney, Sean Covey, and Jim Huling"),
    ("systems", "The 12 Week Year", "Brian P. Moran and Michael Lennington"),
    ("systems", "Upstream", "Dan Heath"),
    ("systems", "Super Thinking", "Gabriel Weinberg and Lauren McCann"),
    ("systems", "The Personal MBA", "Josh Kaufman"),
    ("systems", "Thinking, Fast and Slow", "Daniel Kahneman"),
    ("systems", "Antifragile", "Nassim Nicholas Taleb"),
    ("systems", "The Art of Action", "Stephen Bungay"),
    ("systems", "Good Strategy Bad Strategy", "Richard Rumelt"),
    ("systems", "Playing to Win", "A.G. Lafley and Roger L. Martin"),
    ("systems", "Team of Teams", "Stanley McChrystal"),
    ("systems", "Reinventing Organizations", "Frederic Laloux"),
    ("systems", "Accelerate", "Nicole Forsgren, Jez Humble, and Gene Kim"),
    ("systems", "Radical Focus", "Christina Wodtke"),
    ("systems", "The Great CEO Within", "Matt Mochary"),
    ("systems", "Scaling Up", "Verne Harnish"),
    ("systems", "Who", "Geoff Smart and Randy Street"),
    ("systems", "Work Rules!", "Laszlo Bock"),
    ("systems", "The Life-Changing Magic of Tidying Up", "Marie Kondo"),
    ("systems", "The PARA Method", "Tiago Forte"),
    ("systems", "Where Good Ideas Come From", "Steven Johnson"),
    ("systems", "Loonshots", "Safi Bahcall"),
    ("systems", "Simple Rules", "Donald Sull and Kathleen M. Eisenhardt"),
    ("systems", "The Bullet Journal Method", "Ryder Carroll"),
    ("systems", "The Decision Book", "Mikael Krogerus and Roman Tschäppeler"),
    ("systems", "Six Thinking Hats", "Edward de Bono"),
    ("systems", "Out of the Crisis", "W. Edwards Deming"),
    ("systems", "Great by Choice", "Jim Collins and Morten T. Hansen"),
    ("systems", "How Big Things Get Done", "Bent Flyvbjerg and Dan Gardner"),
    ("systems", "Death by Meeting", "Patrick Lencioni"),
    # ---------------- LEADERSHIP ----------------
    ("leadership", "The 7 Habits of Highly Effective People", "Stephen R. Covey"),
    ("leadership", "Radical Candor", "Kim Scott"),
    ("leadership", "The Effective Executive", "Peter F. Drucker"),
    ("leadership", "So Good They Can't Ignore You", "Cal Newport"),
    ("leadership", "How to Win Friends and Influence People", "Dale Carnegie"),
    ("leadership", "Dare to Lead", "Brené Brown"),
    ("leadership", "Leaders Eat Last", "Simon Sinek"),
    ("leadership", "Start with Why", "Simon Sinek"),
    ("leadership", "The Infinite Game", "Simon Sinek"),
    ("leadership", "The Five Dysfunctions of a Team", "Patrick Lencioni"),
    ("leadership", "The Advantage", "Patrick Lencioni"),
    ("leadership", "Extreme Ownership", "Jocko Willink and Leif Babin"),
    ("leadership", "Turn the Ship Around!", "L. David Marquet"),
    ("leadership", "Multipliers", "Liz Wiseman"),
    ("leadership", "The Culture Code", "Daniel Coyle"),
    ("leadership", "Good to Great", "Jim Collins"),
    ("leadership", "Built to Last", "Jim Collins and Jerry I. Porras"),
    ("leadership", "First, Break All the Rules", "Marcus Buckingham and Curt Coffman"),
    ("leadership", "The Leadership Challenge", "James M. Kouzes and Barry Z. Posner"),
    ("leadership", "On Becoming a Leader", "Warren Bennis"),
    ("leadership", "The 21 Irrefutable Laws of Leadership", "John C. Maxwell"),
    ("leadership", "The Making of a Manager", "Julie Zhuo"),
    ("leadership", "The Manager's Path", "Camille Fournier"),
    ("leadership", "An Elegant Puzzle", "Will Larson"),
    ("leadership", "Trillion Dollar Coach", "Eric Schmidt, Jonathan Rosenberg, and Alan Eagle"),
    ("leadership", "The Coaching Habit", "Michael Bungay Stanier"),
    ("leadership", "Crucial Conversations", "Kerry Patterson, Joseph Grenny, Ron McMillan, and Al Switzler"),
    ("leadership", "Difficult Conversations", "Douglas Stone, Bruce Patton, and Sheila Heen"),
    ("leadership", "Thanks for the Feedback", "Douglas Stone and Sheila Heen"),
    ("leadership", "Nonviolent Communication", "Marshall B. Rosenberg"),
    ("leadership", "The Speed of Trust", "Stephen M.R. Covey"),
    ("leadership", "Emotional Intelligence", "Daniel Goleman"),
    ("leadership", "Primal Leadership", "Daniel Goleman, Richard Boyatzis, and Annie McKee"),
    ("leadership", "What Got You Here Won't Get You There", "Marshall Goldsmith"),
    ("leadership", "The First 90 Days", "Michael D. Watkins"),
    ("leadership", "It's Your Ship", "D. Michael Abrashoff"),
    ("leadership", "Legacy", "James Kerr"),
    ("leadership", "The Score Takes Care of Itself", "Bill Walsh"),
    ("leadership", "Wooden on Leadership", "John Wooden"),
    ("leadership", "Ego Is the Enemy", "Ryan Holiday"),
    ("leadership", "The 48 Laws of Power", "Robert Greene"),
    ("leadership", "No Rules Rules", "Reed Hastings and Erin Meyer"),
    ("leadership", "Powerful", "Patty McCord"),
    ("leadership", "Setting the Table", "Danny Meyer"),
    ("leadership", "Creativity, Inc.", "Ed Catmull"),
    ("leadership", "The Ride of a Lifetime", "Robert Iger"),
    ("leadership", "Nine Lies About Work", "Marcus Buckingham and Ashley Goodall"),
    ("leadership", "Act Like a Leader, Think Like a Leader", "Herminia Ibarra"),
    ("leadership", "Leadership and Self-Deception", "The Arbinger Institute"),
    ("leadership", "The Servant", "James C. Hunter"),
    # ---------------- STARTUP ----------------
    ("startup", "The Lean Startup", "Eric Ries"),
    ("startup", "Zero to One", "Peter Thiel and Blake Masters"),
    ("startup", "The Hard Thing About Hard Things", "Ben Horowitz"),
    ("startup", "The Mom Test", "Rob Fitzpatrick"),
    ("startup", "Founders at Work", "Jessica Livingston"),
    ("startup", "Venture Deals", "Brad Feld and Jason Mendelson"),
    ("startup", "The $100 Startup", "Chris Guillebeau"),
    ("startup", "Rework", "Jason Fried and David Heinemeier Hansson"),
    ("startup", "It Doesn't Have to Be Crazy at Work", "Jason Fried and David Heinemeier Hansson"),
    ("startup", "Anything You Want", "Derek Sivers"),
    ("startup", "Company of One", "Paul Jarvis"),
    ("startup", "The Startup Owner's Manual", "Steve Blank and Bob Dorf"),
    ("startup", "The Four Steps to the Epiphany", "Steve Blank"),
    ("startup", "Crossing the Chasm", "Geoffrey A. Moore"),
    ("startup", "The Innovator's Dilemma", "Clayton M. Christensen"),
    ("startup", "Blitzscaling", "Reid Hoffman and Chris Yeh"),
    ("startup", "High Growth Handbook", "Elad Gil"),
    ("startup", "Secrets of Sand Hill Road", "Scott Kupor"),
    ("startup", "Angel", "Jason Calacanis"),
    ("startup", "Shoe Dog", "Phil Knight"),
    ("startup", "That Will Never Work", "Marc Randolph"),
    ("startup", "The Everything Store", "Brad Stone"),
    ("startup", "Delivering Happiness", "Tony Hsieh"),
    ("startup", "Lost and Founder", "Rand Fishkin"),
    ("startup", "The Art of the Start 2.0", "Guy Kawasaki"),
    ("startup", "Running Lean", "Ash Maurya"),
    ("startup", "Traction: How Any Startup Can Achieve Explosive Customer Growth", "Gabriel Weinberg and Justin Mares"),
    ("startup", "The Founder's Dilemmas", "Noam Wasserman"),
    ("startup", "The Power Law", "Sebastian Mallaby"),
    ("startup", "Start Small, Stay Small", "Rob Walling"),
    ("startup", "The SaaS Playbook", "Rob Walling"),
    ("startup", "Zero to Sold", "Arvid Kahl"),
    ("startup", "The Minimalist Entrepreneur", "Sahil Lavingia"),
    ("startup", "The Cold Start Problem", "Andrew Chen"),
    ("startup", "Play Bigger", "Al Ramadan, Dave Peterson, Christopher Lochhead, and Kevin Maney"),
    ("startup", "Behind the Cloud", "Marc Benioff"),
    ("startup", "Elon Musk", "Ashlee Vance"),
    ("startup", "Steve Jobs", "Walter Isaacson"),
    ("startup", "Super Pumped", "Mike Isaac"),
    ("startup", "Bad Blood", "John Carreyrou"),
    ("startup", "The Upstarts", "Brad Stone"),
    ("startup", "Hatching Twitter", "Nick Bilton"),
    ("startup", "The Airbnb Story", "Leigh Gallagher"),
    ("startup", "Masters of Scale", "Reid Hoffman"),
    ("startup", "Disciplined Entrepreneurship", "Bill Aulet"),
    ("startup", "Will It Fly?", "Pat Flynn"),
    ("startup", "Hackers & Painters", "Paul Graham"),
    ("startup", "The Launch Pad", "Randall Stross"),
    ("startup", "Lean Analytics", "Alistair Croll and Benjamin Yoskovitz"),
    ("startup", "Built to Sell", "John Warrillow"),
    # ---------------- PRODUCT ----------------
    ("product", "Inspired", "Marty Cagan"),
    ("product", "Empowered", "Marty Cagan and Chris Jones"),
    ("product", "Continuous Discovery Habits", "Teresa Torres"),
    ("product", "Obviously Awesome", "April Dunford"),
    ("product", "The Lean Product Playbook", "Dan Olsen"),
    ("product", "Hooked", "Nir Eyal"),
    ("product", "Sprint", "Jake Knapp, John Zeratsky, and Braden Kowitz"),
    ("product", "The Design of Everyday Things", "Don Norman"),
    ("product", "Don't Make Me Think", "Steve Krug"),
    ("product", "Lean UX", "Jeff Gothelf and Josh Seiden"),
    ("product", "User Story Mapping", "Jeff Patton"),
    ("product", "Escaping the Build Trap", "Melissa Perri"),
    ("product", "Product-Led Growth", "Wes Bush"),
    ("product", "Positioning", "Al Ries and Jack Trout"),
    ("product", "Competing Against Luck", "Clayton M. Christensen"),
    ("product", "When Coffee and Kale Compete", "Alan Klement"),
    ("product", "Shape Up", "Ryan Singer"),
    ("product", "Making Things Happen", "Scott Berkun"),
    ("product", "Cracking the PM Interview", "Gayle Laakmann McDowell and Jackie Bavaro"),
    ("product", "Decode and Conquer", "Lewis C. Lin"),
    ("product", "Swipe to Unlock", "Neel Mehta, Aditya Agashe, and Parth Detroja"),
    ("product", "Hacking Growth", "Sean Ellis and Morgan Brown"),
    ("product", "Product Management in Practice", "Matt LeMay"),
    ("product", "Badass: Making Users Awesome", "Kathy Sierra"),
    ("product", "Creative Selection", "Ken Kocienda"),
    ("product", "Build", "Tony Fadell"),
    ("product", "Working Backwards", "Colin Bryar and Bill Carr"),
    ("product", "The Innovator's Solution", "Clayton M. Christensen and Michael E. Raynor"),
    ("product", "Blue Ocean Strategy", "W. Chan Kim and Renée Mauborgne"),
    ("product", "7 Powers", "Hamilton Helmer"),
    ("product", "Understanding Michael Porter", "Joan Magretta"),
    ("product", "Platform Revolution", "Geoffrey G. Parker, Marshall W. Van Alstyne, and Sangeet Paul Choudary"),
    ("product", "Monetizing Innovation", "Madhavan Ramanujam and Georg Tacke"),
    ("product", "The Messy Middle", "Scott Belsky"),
    ("product", "Radical Product Thinking", "Radhika Dutt"),
    ("product", "Product Roadmaps Relaunched", "C. Todd Lombardo"),
    ("product", "Outcomes Over Output", "Josh Seiden"),
    ("product", "The Right It", "Alberto Savoia"),
    ("product", "Testing Business Ideas", "David J. Bland and Alexander Osterwalder"),
    ("product", "Business Model Generation", "Alexander Osterwalder and Yves Pigneur"),
    ("product", "The Mythical Man-Month", "Frederick P. Brooks Jr."),
    ("product", "About Face", "Alan Cooper"),
    ("product", "100 Things Every Designer Needs to Know About People", "Susan Weinschenk"),
    ("product", "Universal Principles of Design", "William Lidwell"),
    ("product", "Actionable Gamification", "Yu-kai Chou"),
    ("product", "Purple Cow", "Seth Godin"),
    ("product", "Zag", "Marty Neumeier"),
    ("product", "Different", "Youngme Moon"),
    ("product", "Alchemy", "Rory Sutherland"),
    ("product", "The Experience Economy", "B. Joseph Pine II and James H. Gilmore"),
    # ---------------- SALES ----------------
    ("sales", "Never Split the Difference", "Chris Voss"),
    ("sales", "SPIN Selling", "Neil Rackham"),
    ("sales", "Influence", "Robert B. Cialdini"),
    ("sales", "To Sell Is Human", "Daniel H. Pink"),
    ("sales", "The Challenger Sale", "Matthew Dixon and Brent Adamson"),
    ("sales", "Fanatical Prospecting", "Jeb Blount"),
    ("sales", "New Sales. Simplified.", "Mike Weinberg"),
    ("sales", "The Little Red Book of Selling", "Jeffrey Gitomer"),
    ("sales", "How I Raised Myself from Failure to Success in Selling", "Frank Bettger"),
    ("sales", "Secrets of Closing the Sale", "Zig Ziglar"),
    ("sales", "The Psychology of Selling", "Brian Tracy"),
    ("sales", "Way of the Wolf", "Jordan Belfort"),
    ("sales", "Sell or Be Sold", "Grant Cardone"),
    ("sales", "The 10X Rule", "Grant Cardone"),
    ("sales", "Pitch Anything", "Oren Klaff"),
    ("sales", "Getting to Yes", "Roger Fisher and William Ury"),
    ("sales", "Getting Past No", "William Ury"),
    ("sales", "Never Lose a Customer Again", "Joey Coleman"),
    ("sales", "Pre-Suasion", "Robert Cialdini"),
    ("sales", "Gap Selling", "Keenan"),
    ("sales", "The Sales Acceleration Formula", "Mark Roberge"),
    ("sales", "Predictable Revenue", "Aaron Ross and Marylou Tyler"),
    ("sales", "From Impossible to Inevitable", "Aaron Ross and Jason Lemkin"),
    ("sales", "The Ultimate Sales Machine", "Chet Holmes"),
    ("sales", "Exactly What to Say", "Phil M. Jones"),
    ("sales", "The Transparency Sale", "Todd Caponi"),
    ("sales", "Sell with a Story", "Paul Smith"),
    ("sales", "Building a StoryBrand", "Donald Miller"),
    ("sales", "They Ask, You Answer", "Marcus Sheridan"),
    ("sales", "This Is Marketing", "Seth Godin"),
    ("sales", "Contagious", "Jonah Berger"),
    ("sales", "Made to Stick", "Chip Heath and Dan Heath"),
    ("sales", "The Go-Giver", "Bob Burg and John David Mann"),
    ("sales", "The Greatest Salesman in the World", "Og Mandino"),
    ("sales", "Smart Calling", "Art Sobczak"),
    ("sales", "Insight Selling", "Mike Schultz and John E. Doerr"),
    ("sales", "The Qualified Sales Leader", "John McMahon"),
    ("sales", "Demand-Side Sales 101", "Bob Moesta"),
    ("sales", "$100M Offers", "Alex Hormozi"),
    ("sales", "$100M Leads", "Alex Hormozi"),
    ("sales", "The JOLT Effect", "Matthew Dixon and Ted McKenna"),
    ("sales", "Sell Like Crazy", "Sabri Suby"),
    ("sales", "Founding Sales", "Peter Kazanjy"),
    ("sales", "Yes!: 50 Scientifically Proven Ways to Be Persuasive", "Noah J. Goldstein, Steve J. Martin, and Robert B. Cialdini"),
    ("sales", "Jab, Jab, Jab, Right Hook", "Gary Vaynerchuk"),
    ("sales", "Sales EQ", "Jeb Blount"),
    ("sales", "Selling to Big Companies", "Jill Konrath"),
    ("sales", "The New Strategic Selling", "Robert B. Miller and Stephen E. Heiman"),
    ("sales", "Solution Selling", "Michael T. Bosworth"),
    ("sales", "Eat Their Lunch", "Anthony Iannarino"),
    # ---------------- CAREERS ----------------
    ("careers", "Designing Your Life", "Bill Burnett and Dave Evans"),
    ("careers", "The Squiggly Career", "Helen Tupper and Sarah Ellis"),
    ("careers", "Working Identity", "Herminia Ibarra"),
    ("careers", "Range", "David Epstein"),
    ("careers", "Linchpin", "Seth Godin"),
    ("careers", "The Startup of You", "Reid Hoffman and Ben Casnocha"),
    ("careers", "Never Eat Alone", "Keith Ferrazzi"),
    ("careers", "Give and Take", "Adam Grant"),
    ("careers", "Originals", "Adam Grant"),
    ("careers", "Think Again", "Adam Grant"),
    ("careers", "Ultralearning", "Scott H. Young"),
    ("careers", "What Color Is Your Parachute?", "Richard N. Bolles"),
    ("careers", "StrengthsFinder 2.0", "Tom Rath"),
    ("careers", "Pivot", "Jenny Blake"),
    ("careers", "Body of Work", "Pamela Slim"),
    ("careers", "The Pathless Path", "Paul Millerd"),
    ("careers", "The Long Game", "Dorie Clark"),
    ("careers", "Reinventing You", "Dorie Clark"),
    ("careers", "The Defining Decade", "Meg Jay"),
    ("careers", "Lean In", "Sheryl Sandberg"),
    ("careers", "Nice Girls Don't Get the Corner Office", "Lois P. Frankel"),
    ("careers", "The Unspoken Rules", "Gorick Ng"),
    ("careers", "Steal Like an Artist", "Austin Kleon"),
    ("careers", "Show Your Work!", "Austin Kleon"),
    ("careers", "Big Magic", "Elizabeth Gilbert"),
    ("careers", "The Element", "Ken Robinson"),
    ("careers", "Mastery", "Robert Greene"),
    ("careers", "The Crossroads of Should and Must", "Elle Luna"),
    ("careers", "An Astronaut's Guide to Life on Earth", "Chris Hadfield"),
    ("careers", "The Art of Work", "Jeff Goins"),
    ("careers", "48 Days to the Work You Love", "Dan Miller"),
    ("careers", "The 2-Hour Job Search", "Steve Dalton"),
    ("careers", "The Adventures of Johnny Bunko", "Daniel H. Pink"),
    ("careers", "Do What You Are", "Paul D. Tieger"),
    ("careers", "Great at Work", "Morten T. Hansen"),
    ("careers", "Chop Wood Carry Water", "Joshua Medcalf"),
    ("careers", "The Practice", "Seth Godin"),
    ("careers", "Playing Big", "Tara Mohr"),
    ("careers", "Presence", "Amy Cuddy"),
    ("careers", "Quiet", "Susan Cain"),
    ("careers", "Bullshit Jobs", "David Graeber"),
    ("careers", "The Good Enough Job", "Simone Stolzoff"),
    ("careers", "Out of Office", "Charlie Warzel and Anne Helen Petersen"),
    ("careers", "Remote", "Jason Fried and David Heinemeier Hansson"),
    ("careers", "The New Rules of Work", "Alexandra Cavoulacos and Kathryn Minshew"),
    ("careers", "Designing Your Work Life", "Bill Burnett and Dave Evans"),
    ("careers", "How Will You Measure Your Life?", "Clayton M. Christensen"),
    ("careers", "The Third Door", "Alex Banayan"),
    ("careers", "Taking the Work Out of Networking", "Karen Wickre"),
    ("careers", "The Happiness Equation", "Neil Pasricha"),
]

CATEGORY_ORDER = ["habits", "focus", "priorities", "systems", "leadership", "startup", "product", "sales", "careers"]


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "BookDigest-curation/1.0 (sam@fuzzylabs.ai)"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def resolve_cover(title, author):
    """Return best cover_i for title/author, or None."""
    first_author = author.split(" and ")[0].split(",")[0].strip()
    attempts = [
        {"title": title, "author": first_author},
        {"title": title},
        {"q": f"{title} {first_author}"},
    ]
    for params in attempts:
        params = dict(params, limit="5", fields="cover_i,title,author_name")
        url = "https://openlibrary.org/search.json?" + urllib.parse.urlencode(params)
        for attempt in range(3):
            try:
                data = fetch_json(url)
                covers = [d["cover_i"] for d in data.get("docs", []) if d.get("cover_i")]
                if covers:
                    return covers[0]
                break  # no covers in this attempt's results; try next param set
            except Exception:
                time.sleep(1.5 * (attempt + 1))
    return None


def main():
    cache = {}
    if os.path.exists(CACHE_PATH):
        with open(CACHE_PATH) as f:
            cache = json.load(f)

    todo = [(c, t, a) for (c, t, a) in BOOKS if f"{t}|{a}" not in cache]
    print(f"{len(BOOKS)} books total, {len(todo)} to resolve", flush=True)

    def work(entry):
        c, t, a = entry
        cover = resolve_cover(t, a)
        return (t, a, cover)

    with ThreadPoolExecutor(max_workers=6) as pool:
        for i, (t, a, cover) in enumerate(pool.map(work, todo)):
            cache[f"{t}|{a}"] = cover
            if (i + 1) % 25 == 0:
                print(f"  resolved {i + 1}/{len(todo)}", flush=True)
                with open(CACHE_PATH, "w") as f:
                    json.dump(cache, f)

    with open(CACHE_PATH, "w") as f:
        json.dump(cache, f)

    missing = [(t, a) for (c, t, a) in BOOKS if not cache.get(f"{t}|{a}")]
    print(f"missing covers: {len(missing)}")
    for t, a in missing:
        print(f"  NO COVER: {t} — {a}")

    # Emit Swift
    def swift_str(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = []
    lines.append("import SwiftUI")
    lines.append("")
    lines.append("// Hand-curated category shelves. Cover IDs were resolved against the Open")
    lines.append("// Library search API at curation time so shelves render without any search")
    lines.append("// requests. Regenerate with the curation script if the lists change.")
    lines.append("enum CuratedBooks {")
    lines.append("    static func books(in category: BookCategory) -> [Book] {")
    lines.append("        switch category {")
    for cat in CATEGORY_ORDER:
        lines.append(f"        case .{cat}:")
        lines.append(f"            return {cat}")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    for cat in CATEGORY_ORDER:
        entries = [(t, a) for (c, t, a) in BOOKS if c == cat]
        lines.append(f"    private static let {cat}: [Book] = [")
        for t, a in entries:
            cover = cache.get(f"{t}|{a}")
            cover_str = str(cover) if cover else "nil"
            lines.append(f"        curated({swift_str(t)}, {swift_str(a)}, {cover_str}, .{cat}),")
        lines.append("    ]")
        lines.append("")
    lines.append("    private static func curated(_ title: String, _ author: String, _ coverID: Int?, _ category: BookCategory) -> Book {")
    lines.append("        Book(")
    lines.append("            id: Book.slug(fromTitle: title),")
    lines.append("            title: title,")
    lines.append('            shortTitle: title.count > 30 ? String(title.prefix(27)) + "..." : title,')
    lines.append("            author: author,")
    lines.append('            angle: "A book by \\(author).",')
    lines.append("            category: category,")
    lines.append("            keywords: [],")
    lines.append("            coverColors: [")
    lines.append("                Color(red: 0.14, green: 0.16, blue: 0.20),")
    lines.append("                Color(red: 0.55, green: 0.60, blue: 0.65)")
    lines.append("            ],")
    lines.append('            coverURL: coverID.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\\($0)-L.jpg") }')
    lines.append("        )")
    lines.append("    }")
    lines.append("}")

    with open(SWIFT_OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {SWIFT_OUT}")


if __name__ == "__main__":
    main()
