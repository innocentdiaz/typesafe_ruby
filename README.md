# s1-ruby
![preview](https://github.com/innocentdiaz/s1_ruby/blob/master/preview.png?raw=true)

> AI built for interfacing with code (useful) — not with people (too good to be true).

> The AI race has revealed the operation that computation was missing: `collapse` over meaning.

# Overview

**System One (S1) measurement** — and the *collapse* that follows it — as a **Ruby primitive**.
An S1 model answers a typed question about data with a calibrated probability. It does not
generate, and it does not decide. Code asks; code decides.

 - For the **Ruby on Rails** implementation, see: [s1-rails](https://github.com/innocentdiaz/s1_rails)

**TABLE of CONTENTS**

- [TL;DR](#tldr)
- [The idea: collapse](#the-idea-collapse) · [Why](#why)
- [Install](#install)
- [Grammar: verbs, nouns, shorthands](#grammar-verbs-nouns-shorthands)
- [The three primitives](#the-three-primitives) — noul · choice · score · [Level](#level) · [Batch](#batch-many-questions-one-call) · [Structured state](#structured-state-and-structured-questions) · [Reading answers](#reading-answers)
- [Experimental: making it a Ruby primitive](#experimental-making-it-a-ruby-primitive) — primitives · ψ · pattern matching · `===`
- [Keeping the probability: collapse late](#keeping-the-probability-collapse-late) — `&` `|` `~` · ranges · `undecided?` · `collapse`
- [Collections: judgments as predicates](#collections-judgments-as-predicates) — select / group_by / sort_by / sum / grep · the knob (`given:`)
- [Dictionary and aliases](#dictionary-and-aliases)
- [Errors](#errors) · [Testing](#testing) · [Observing calls](#observing-calls) · [Providers](#providers) · [Development](#development)

## TL;DR

Illustrative code:

```ruby
# Pull from a database:
people = [
  {
    name: "Michael",
    occupations: [
      "owner @ large self-sustaining family homestead",
      "software engineer @ MedicalTech startup ($2M/arr)"
    ]
  },
  {
    name: "Bob",
    occupations: [
      "Exotic beast/animal hunter & trader (pokemon hunter)",
      "Professional Sportsman (office ping pong master)",
      "Front-Counter Point of Sale (POS) Operator (MacDonalds in Hunstville, Alabama)"
    ]
  }
]

(ψ people).choose "the most skilled individual", choices: people.map { _1[:name] }   # => Michael — one call; .ranked lists everyone
people.max_by(&ψ.score("How skilled is this person?", "novice", "competent", "expert", "exceptional"))   # => the Michael hash; one call per person
```

`(ψ people)` makes the list **measurable**: something questions can be asked about, none asked
yet. Measuring it — *choose* the most skilled — is omakase by default: the model's own sense of
"skilled". To calibrate it, hand the model something to judge *against*, with `given` (or
`against`):

```ruby
(ψ people).given(rubric: "skill = breadth of trades").choose "the most skilled, per `rubric`", choices: people.map { _1[:name] }   # => Bob
```

The same list, with the options built from the data, is under [choice](#the-three-primitives).

Another example:

```ruby
class EscalateToHuman < StandardError; end

def handle_chat(chat)
  triage = (ψ chat).measure do |q|                                        # several measurements, one call
    q.judge  :escalate,   "Is the customer asking for a supervisor?"
    q.judge  :new_matter, "Is this a new matter?"
    q.score  :severity,   "How severe is the injury?", "None", "Minor", "Serious", "Catastrophic"
  end

  raise EscalateToHuman if triage.true?(:escalate)                        # ? collapses; a bare answer is always truthy
  create_case(triage[:severity].level) if triage.true?(:new_matter) && triage[:severity].index >= 1
end

chat = { messages: [] }
inbox.each do |message|            # whatever feeds you messages: a queue, a webhook, a socket
  chat[:messages] << message
  handle_chat(chat)                # one call per message; every question answered fresh
rescue EscalateToHuman
  hand_to_person(chat)
end
```

## The idea: collapse

Software is rows and associations. Its input is human: a form, a phone call transcript, a
review, a chat, a résumé. Its output is what a person sees on the other side: a web UI, an
API, an MCP. Between the two sits the one thing computers could never do — read the human
input and *judge* it.

For AI to be useful it has to tap that **stream** of human input — the data, one transcript
or a list of calls, tickets, candidates — and categorize it, sort it, judge it. Not write about
it: decide something about it that code can act on. That operation is the primitive this gem
is built around. It has one name here and three shapes:

> **collapse** — a stream goes in; a category comes out.
> *noul*: true / false. *choice*: one of a set. *score*: a level on a spectrum.

It has three steps, and two of them have a symbol. **ψ makes measurable**: `(ψ chat)` is a
subject with calibrated answers to any question, none yet taken. **The verbs measure**:
`judge`, `choose`, `score` — three kinds of measurement, always one of the three — or several
at once with `measure { |q| q.judge …; q.choose …; q.score … }`. Each returns a distribution,
calibrated and kept. **`?` decides**: the distribution becomes a category. That is Ruby's own
suffix with Ruby's own meaning (`empty?`, `any?`: the decision, not the thing). Between the
two there is nothing new — arithmetic, ranges, `sum`, `case` — because once a judgement is a
number, Ruby already knows what to do with a number.

```
Human stream  +  Preference  ──ψ──▶  measurable  ──judge / choose / score──▶  probabilities  ──?──▶  judgement
                                                                                   │
                                                                            & | ~  ranges  sum  case
```

A prism: light goes in, colors come out, and the colors are what the user sees on the client
side. The physics image is loose on one point: S1 answers are deterministic and repeatable;
the probability is calibrated credence, not a coin waiting to be flipped. "Collapse" names the
code's choice to stop carrying the distribution — and it is a choice; the section *Keeping the
probability* is about not making it too early.

**The preference** is the knob: the human's tuning of what the judgement is *against*. Omakase
(the model's own sense of "angry", "qualified", "urgent") or custom: a firm's acceptance
criteria, a role's requirements, a return policy. It lives on the question (clarifications,
option descriptions, levels) or beside the data (`given:`, a Rails form).

**The judgement** is semantic categorization, with a probability. A regex categorizes by
characters; this categorizes by meaning — the same *kind* of tool (a predicate you filter and
match with), applied where characters run out. And the collapse is *probabilistic*: every
answer carries its distribution, so "need more info / maybe / probably / sure" is as native as
true / false, and a sum of nouls is an expected count.

The thing that changes:

```ruby
name = "Andrew"
male_name = true if ???                       # there was never a way to write this line
preference_color = male_name ? "blue" : "pink"
```

```ruby
male_name = (ψ name).is? "a man's name"       # now there is: ψ measurable, is measures, ? decides
(ψ name).is "a man's name"                    # => 0.97 — the measurement alone, when the number is what you want
```

That is the whole foundation: make the collapse a primitive of the language, then give it
the same surface everything else in Ruby has — filter, group, sort, sum, match, pattern-match,
batch — so a stream can be judged with `Enumerable` the way it is counted with `Enumerable`.
Everything in this README is one of those two moves. The model behind it (jev, today) is what
makes it possible; the primitive is what makes it usable.

## Why

An S1 model does one thing: categorize (collapse, judge). Three operations cover it:
- Choice — group, classify, route (`choose`)
- Score — a level on an ordered scale (`score`)
- Yes / no, with a probability (`judge`)

It is not a free-form assistant for people (an LLM). It interfaces with code.
Code-in-the-loop, not human-in-the-loop.

The most basic usage:

```ruby
chat = { messages: [ "How may I help you?" ... ]}
escalate_to_human if chat.judge? "is the customer asking for a human agent?"    # primitives on (c.primitives = true)
escalate_to_human if (ψ chat).is? "asking for a human agent"                     # the symbol on (c.symbol = true)
```

Under the hood, both are:

```ruby
subject = S1::Subject.new("I have asked three times now. Can I just talk to a real person?")
escalate_to_human if subject.judge?("Is the customer asking for a human agent?")
```

## Install

```ruby
gem "s1"
```

```ruby
# config/initializers/s1.rb (or anywhere at boot)
S1.configure do |c|
  c.provider   = :typesafe                  # default; a name under Providers, or an instance
  c.timeout    = 30                         # seconds per request
  c.threshold  = 0.5                        # a noul at or above this reads as true
  c.logger     = Rails.logger               # optional; debug lines per request, warns on retry
  c.primitives = false                      # true extends String, Hash, Array; see "Experimental"
  c.symbol     = false                      # true defines ψ(x); see "Experimental"

  c.typesafe.api_key     = ENV["TYPESAFE_API_KEY"]   # default: read from the environment
  c.typesafe.model       = "jev-latest"
  c.typesafe.base_url    = "https://api.typesafe.ai"
  c.typesafe.max_retries = 2                         # transient failures before raising

  c.cua.checkpoint = "cua-s1-forms"                  # only when c.provider = :cua
  c.laya.base_url  = "http://127.0.0.1:8765"         # only when c.provider = :laya (self-hosted)
end
```

Every value has a default; an initializer is only needed to change one. Each provider keeps its
own settings under its name (`c.typesafe`, `c.cua`), declared by the provider class. Ruby ≥ 3.2.
No runtime dependencies.

## Grammar: verbs, nouns, shorthands

The vocabulary has three layers, and every method in this README sits in exactly one of them.

**Measurables carry verbs.** A measurable is anything a question can be asked about: an
`S1::Subject`; a String, Hash or Array with primitives on; a Rails record; a `ψ.` predicate. A
verb measures and returns a collapsable.

| verb | asks | returns |
|---|---|---|
| `judge` (`noul`; `is` and `same_as` fill the question in) | "Is this true?" | `Answer::Noul` |
| `choose` | "Which of these?" | `Answer::Choice` |
| `score` | "Which level?" | `Answer::Score` |
| `measure` (`ask`, `batch`, `ask_about`) | several at once | `Result` |

**Collapsables carry nouns.** One contract: `collapse(threshold = S1.config.threshold)`. The
threshold only matters to a noul; the others accept and ignore it, so a `Result` collapses every
answer through one call. Each kind names its collapse and exposes Ruby's own conversions.

| collapsable | `collapse` returns | its own name | Ruby idioms |
|---|---|---|---|
| `Answer::Noul` | `true` / `false` | `true?` (`false?`) | `!` so `!!`, `to_f`, `Comparable`, `&` `\|` `~` |
| `Answer::Choice` | a Symbol | `choice` | `to_sym`, `to_s`, loose `==` |
| `Answer::Score` | an `S1::Level` | `level` | `index`, `to_f` (weighted position), `levels` |
| `Result` | `{ id => collapsed value }` | `to_h` | `deconstruct_keys`, so `case … in` |

**Shorthands are verb + noun in one call**, defined literally as `verb(...).collapse`:

```ruby
def judge?(...) = judge(...).collapse      # noul?, ask?; is? and same_as? fill the question in
def choice(...) = choose(...).collapse
def level(...)  = score(...).collapse
```

So on every measurable the identity holds: `x.noun(args) == x.verb(args).collapse`. And a `?`
method returns a boolean — Ruby's convention — so `?` exists only for a noul: there is no
`choice?` and no `judge?` on a Choice or a Score.

## The three primitives

Every question is one of three shapes. Pick by what the answer *is*. Each shape has two
methods, and one rule names them: **the verb measures, the noun collapses**. `judge` /
`judge?`, `choose` / `choice`, `score` / `level` — the verb returns the distribution, the noun
(or the `?`, for a yes/no) returns the value. The examples use
`subject = S1::Subject.new(text)`; a `# ψ:` line gives the same call with the symbol on. A
`Noul` prints as its probability, so `# => 0.98` below is a `Noul` at 0.98.

**noul — "Is this true?"** Returns a probability, 0 to 1. The probability is the signal. The
methods are `judge` (the probability) and `judge?` (true at or above the threshold); `noul` /
`noul?` are the same methods under the wire name, and `is` / `is?` take a phrase and ask
"Is this …?".

```ruby
subject.judge("Is the customer asking for a human agent?")    # => #<S1::Answer::Noul 0.98>  compares like a number
subject.judge?("Is the customer asking for a human agent?")   # => true  (at or above the threshold)
# ψ: (ψ text).judge "…" / (ψ text).is? "the customer asking for a human agent"

# Optional clarification of what counts as yes / no:
subject.judge("Has the customer contacted support about this before?",
              true:  "mentions a prior attempt, ticket, or having asked before",
              false: "no sign of any previous contact")
```

**choice — "Which of these options?"** An unordered set. `choose` measures — the pick plus a
distribution over all options; `choice` is the pick alone, a Symbol.

```ruby
dept = subject.choose("Which team should handle this?",
                      returns:  "Exchanges, refunds, wrong or damaged items",
                      shipping: "Delivery status, delays, lost packages",
                      billing:  "Charges, invoices, payment problems")
dept.to_sym          # => :returns
dept[:shipping]      # => 0.0
dept.confidence      # => 1.0
subject.choice("Which team should handle this?", returns: "…", shipping: "…", billing: "…")   # => :returns
# ψ: dept = (ψ text).choose "Which team should handle this?", returns: "…", shipping: "…", billing: "…"
```

Options can be built from the state itself. `people` is the list from the [TL;DR](#tldr); that
example asks one question over the whole list, this one shows the four ways to pass the options
(primitives on, so the Array is the receiver):

```ruby
options = people.to_h { |person| [person[:name], "Occupations: #{person[:occupations].join(", ")}"] }

people.choose "The most skilled individual", **options                          # => Michael 0.98
people.choose "The most skilled individual", choices: options                   # same
people.choose "The most skilled individual", choices: people.map { _1[:name] }  # labels only, no descriptions
options.choose "The most skilled individual"                                    # the state IS the options
```

`choices:` (or the wire name, `criteria:`) takes `{ option => description }` or a bare list of
options. With none given, a state of that shape is the options.

**score — "Which level?"** An ordered spectrum, worst → best. `score` measures — the most likely
level, and the probability-weighted position; `level` is the level alone: an `S1::Level`, the
label, that knows its position.

```ruby
sev = subject.score("How severe is the reported issue?",
                    "Cosmetic; no impact to functionality",
                    "Broken or degraded feature, but a workaround exists",
                    "Blocking issue; no workaround exists")
sev.level    # => "Blocking issue; no workaround exists"   an S1::Level
sev.index    # => 2
sev.to_f     # => 1.68   (weighted position across the levels)
subject.level("How severe is the reported issue?", "Cosmetic…", "Broken…", "Blocking…")   # => "Blocking issue; no workaround exists"
# ψ: sev = (ψ text).score "How severe is the reported issue?", "Cosmetic…", "Broken…", "Blocking…"
```

### Level

A score collapses to a `Level`: a String — the label — that knows its position on its scale.
That one fact is what makes a level usable both where code wants a number and where it wants
text.

```ruby
sev = subject.score("How severe is the reported issue?", "Cosmetic…", "Broken…", "Blocking…")
lvl = sev.collapse            # => "Blocking issue; no workaround exists", an S1::Level

lvl >= 1                      # => true    by position, not alphabet
lvl >= "Broken or degraded feature, but a workaround exists"   # => true    a label on the scale, by its position
lvl.to_i                      # => 2
lvl.scale                     # => ["Cosmetic…", "Broken…", "Blocking…"]

case subject.measure { |q| q.score :severity, "How severe?", "Cosmetic", "Broken", "Blocking" }
in { severity: "Blocking" }   then page_someone      # the label matches
in { severity: 1.. }          then open_ticket       # so does an integer range
end

tickets.sort_by(&ψ.score("How severe?", "cosmetic", "broken", "blocking"))   # ordered by position
tickets.max_by(&ψ.score("How severe?", "cosmetic", "broken", "blocking"))
by_level = tickets.group_by(&ψ.score("How severe?", "cosmetic", "broken", "blocking"))
by_level["blocking"]          # keys are the labels; a plain String looks them up

"severity: #{lvl}"            # a String: interpolates
ticket.update!(severity: lvl) # stores as the label
{ severity: lvl }.to_json     # => {"severity":"Blocking issue; no workaround exists"}
```

One caveat. Put the level on the left of a comparison with a label: `lvl >= "Broken…"` is
by position, `"Broken…" <= lvl` is String's own compare, by alphabet. Ranges of integers match
a level; ranges of labels do not.

## Batch: many questions, one call

A measurement is always one of the three kinds — `judge`, `choose`, `score`; the kind is part
of what a measurement is. `measure` is the plural: the same three, several at once.

```
measure  =  judge | choose | score              one measurement, one kind
measure { judge; choose; score; … }             several, one call, independent
```

Two things make the plural more than a loop. **One call**: the state goes over once, and N
questions cost one call. **Independence**: the model answers each question as if it were the
only one — one answer is never hidden context for another. Independence is what makes `&` / `|`
on the results exact, and it is why the batch is the natural unit: several *independent*
measurements of one state. `ask`, `batch` and `ask_about` are aliases of `measure`.

```ruby
result = subject.measure do |q|      # ψ: (ψ text).measure do |q|
  q.judge  :escalate,   "Is the customer asking for a human agent?"
  q.judge  :repeat,     "Has the customer contacted support about this before?",
                        true: "mentions a prior attempt", false: "no sign of one"
  q.choose :department, "Which team should handle this?", returns: "Refunds", shipping: "Delays", billing: "Charges"
  q.score  :severity,   "How severe is the issue?", "Cosmetic", "Degraded, workaround exists", "Blocking"
end

result[:escalate].true?        # => true
result[:department].to_sym     # => :returns
result[:severity].level        # => "Blocking"
result.usage                   # => { input_tokens: 490, output_tokens: 86 }
result.duration_ms             # => 398
```

Ask **speculatively**: include questions whose answers you only need conditionally, then let
your code decide which to use. That keeps it to one call.

```ruby
r = subject.measure do |q|           # ψ: (ψ text).measure do |q|
  q.judge :is_lead,  "Is there a potential new case or matter?"
  q.judge :qualified, "Is this a qualified lead, based on `firm.criteria`?"
  q.judge :prior_rep, "Does the lead already have an attorney?"   # asked regardless,
end                                                               # used only when relevant

if r[:is_lead].true? && r[:qualified] >= 0.85
  flag_conflict if r[:prior_rep].true?
end
```

## Structured state and structured questions

State can be a string, or a hash/array (braced — bare keywords to `Subject.new` are options,
not state). With a hash, instructions can point at fields with backticked paths:

```ruby
subject = S1::Subject.new({
  transcript:   utterances,
  case_details: { date_of_incident: "2026-08-15", sol_deadline: "2027-08-15" }
})

subject.judge?("Judging from `transcript` and `case_details.sol_deadline`, is the claim still within the statute of limitations?")
# ψ: (ψ { transcript: utterances, case_details: {...} }).is? "still within the statute of limitations, judging from `transcript` and `case_details.sol_deadline`"
```

Instructions can be structured too — the verification pattern:

```ruby
subject = S1::Subject.new({ source_text: "Invoice #4471 issued March 3, 2026 to Beaver Dam Logistics for $12,840.00, net 30." })

subject.judge?({ field: { name: "invoice_number", type: "string", description: "The identifier printed on the invoice." },
                 extracted_value: "4471",
                 question: "Does `extracted_value` match the `field` as it appears in `source_text`?" })
# ψ: (ψ { source_text: "…" }).judge?({ field: …, extracted_value: "4471", question: "…" })
```

## Reading answers

All answers carry `probabilities` and `confident?(threshold)`; use it to route — act automatically
when confident, escalate to a person or a reasoning model when not. Choice and score answers
also carry the provider's `confidence`; a noul's confidence is how far its probability sits from
the fence, so `confident?` only discriminates when the threshold is above 0.5.

| answer | reads as |
|---|---|
| `Answer::Noul` | `to_f`, `true?` / `false?`, compares to numbers (`a >= 0.85`) |
| `Answer::Choice` | `to_sym`, `to_s`, `[option]`, `== :returns` |
| `Answer::Score` | `level` (an `S1::Level`), `index`, `to_f`, `levels` |

```ruby
answer = result[:department]
if answer.confident?
  route_to(answer.to_sym)
else
  hold_for_review(answer.probabilities)
end
```

## Experimental: making it a Ruby primitive

Everything above works through `S1::Subject`. The pieces below are opt-in — off by default,
each behind its own config switch — and exist to make asking a question feel native to the
language. Use them where they read better; leave them off where a codebase would rather not
extend core classes.

**Core classes answer for themselves.** `c.primitives = true` extends `String`, `Hash` and
`Array` with `judge` / `judge?` (`noul`, `noul?`, `ask?`), `choose` / `choice`, `score` /
`level` and `ask` (`measure`, `batch`, `ask_about`). A class's own method with one of those names always
wins, since the module is included beneath it. `to_s1` gives the Subject, for per-call options.

```ruby
S1.configure { |c| c.primitives = true }      # String, Hash, Array; or a subset: [String]
require "s1/core_ext"                                # equivalent, require-style

"Can I speak to a person?".judge? "the customer is asking for a human agent"
{ ticket: text }.choose "Which team?", returns: "Refunds", billing: "Charges"
chat.measure { |q| q.judge :escalate, "..." }
chat.to_s1(threshold: 0.9).judge?("...")             # the Subject, for per-call options
```

**No receiver at all.** Naming `Kernel` in the targets — `c.primitives = [String, Hash, Array, Kernel]`
— adds the same verbs as bare calls against an ambient subject. This is the sharpest edge: a
bare `score`, `ask` or `choice` shadows any DSL that resolves those names through
`method_missing` (FactoryBot attributes, for one), which is why it is a separate switch.

```ruby
S1.about(chat) { judge?("...") }           # block-scoped subject, restored after
S1.subject = chat                          # console / long-lived scope
```

**A symbol.** `c.symbol = true` defines **ψ** on `Kernel`, like `Integer()` or `Pathname()`:
anything becomes a Subject. ψ, the wavefunction — a thing that is only probabilities until you
ask it a question. ψ makes a thing measurable; the verbs measure; the `?` on whatever follows
is the collapse. Any identifier works in its place (`c.symbol = "⍣"`). Anything that defines
`to_s1` converts itself — that is how a typesafe-rails record becomes its default form. The
explicit spelling is always `S1::Subject.new(x)`.

Is that just `is?` for the sake of reading like English? No — ψ is the convention the rest of
this section hangs off:

- **any object**, not the three core classes primitives extend: a record, `params`, a `Mail::Message`,
  a Struct, a Time — `(ψ mail).is? "an out-of-office reply"`;
- **options at the point of asking** — `(ψ text, threshold: 0.95)`, `provider:`, `model:`,
  `owner: phone_call` for the ledger;
- **a handle** — `subject = (ψ x)` is built once and asked many times; nothing about `x` is recomputed between questions;
- **the English forms** that live only on `Subject`: `is?`, `is`, `same_as?`, `same_as`;
- **a block** — `ψ chat do … end` makes `chat` the subject for the bare forms inside;
- **no monkeypatching** — one private `Kernel` method; `c.primitives` can stay off and code still
  reads as sentences.

```ruby
(ψ"Michael").is? "a man's name"          # => true
(ψ"Michael").is "a man's name"           # => 0.98
(ψ text).is? "a man's name"              # a variable needs the space: ψtext is one identifier
```

With a block, ψ is `S1.about`: the subject for the bare forms inside (needs `Kernel` in
the primitives).

```ruby
ψ chat do
  escalate_to_human if judge? "Is the customer asking for a human agent?"
  triage = measure { |q| q.judge :new_matter, "Is this a new matter?"; q.score :severity, "…", "None", "Minor", "Serious" }
end
```

**Pattern matching.** A batch `Result` deconstructs: nouls as booleans at the threshold, choices as
symbols, scores as Levels — which match an integer range and a label alike — so Ruby's own
`case … in` is the gate logic.

```ruby
case (ψ chat).measure { |q| q.judge :escalate, "…"; q.choose :department, "…", returns: "…", billing: "…"; q.score :severity, "…", "low", "mid", "high" }
in { escalate: true, severity: 2.. }  then page_someone
in { department: :billing }           then route_to_billing
else                                       hold_for_triage
end
```

**Semantic equality — with the right operator.** `(ψ "Acme Inc").same_as? "ACME, Incorporated"` asks
"Do `this` and `other` describe the same thing?" (`same_as` for the probability). The operator
form is `===`, case equality — Ruby's "does this match?", the one `Range`, `Regexp` and `Proc`
define, called only in explicit matching contexts:

```ruby
case vendor.name
when (ψ "Acme Inc") then merge_into(acme)
end

names.grep(ψ "Acme Inc")            # every name that describes the same company
names.any?(ψ "Acme Inc")
```

Not a regex. A regex (or `similarity()`) compares strings; `same_as?` compares what the strings
are about. Two calls about one accident, transcribed a week apart:

```ruby
transcript = "Caller: Hi, this is Juan, I was rear-ended on Michael Street on the fifteenth, my neck hurts, the other driver ran the light."
recent     = ["Caller: John here, calling back about my accident on Manor Street, August 15th, the guy went through the red light and hit me from behind.",
              "Caller: This is Maria, I slipped at the grocery store on Manor Street last week and hurt my knee.",
              "Caller: Juan Perez, I want to know if you handle wills."]

recent.any?(ψ transcript)                             # => true   (one run: 0.67 / 0.03 / 0.06)
recent.any? { |t| t =~ /Juan.*Michael Street/ }       # => false  — "John", "Manor Street", "August 15th"
```

Juan/John and Michael/Manor are transcription noise; "the fifteenth" and "August 15th" are the same
day; the third caller shares the name and nothing else. No pattern over characters gets that
right, and every regex you tighten toward one case breaks another. One call per candidate, so
narrow with SQL first (same firm, same week, same phone) and ask about the survivors.

Why not `==`? Ruby calls `==` for you — inside `Hash#[]`, `Array#include?`, `uniq`, RSpec's `eq` —
so a model-backed `==` puts a network call, a cost and a non-deterministic answer into every one of
those, and `==` is expected to be reflexive, symmetric and transitive, which a judgment is not.
`===` carries none of that: it is only ever a question about a match. `==` on a Subject is plain Ruby equality — never a model call.

**Aliases.** The batch is `measure`, `ask`, `batch` or `ask_about` — `(ψ chat).ask_about { |q| … }` reads
best when the subject is right there; `ψ chat do … end` is the same idea with the bare forms
inside. Every alias is a plain Ruby `alias`; see the [dictionary](#dictionary-and-aliases).

Typing ψ on macOS: add the *Unicode Hex Input* keyboard (System Settings → Keyboard → Input
Sources → +), switch to it, then hold Option and type `03C8`.

**Explicit vs primitive.** Every form has an explicit spelling; the primitive one is the same call
with the plumbing removed.

| you want | explicit | primitive |
|---|---|---|
| a yes/no | `S1::Subject.new(text).judge?("Is the customer angry?")` | `(ψ text).is? "angry"` · `text.judge? "…"` |
| the probability | `S1::Subject.new(text).judge("…").to_f` | `(ψ text).judge "…"` |
| one of a set | `S1::Subject.new(text).choose("Which team?", returns: "…", billing: "…")` | `text.choose "Which team?", returns: "…", billing: "…"` |
| the option alone | `S1::Subject.new(text).choose("…", **opts).to_sym` | `text.choice "…", **opts` |
| a level on a spectrum | `S1::Subject.new(text).score("…", *levels).level` | `text.level "…", *levels` |
| the best of a list | `S1::Subject.new(list).choose("the best", choices: labels)` | `(ψ list).choose "the best", choices: labels` |
| several at once | `S1::Subject.new(text).measure { \|q\| … }` | `ψ text do … end` · `(ψ text).measure { \|q\| … }` |
| filter a stream | `list.select { \|x\| S1::Subject.new(x).judge?("…") }` | `list.select(&ψ.is("…"))` |
| bucket a stream | `list.group_by { \|x\| S1::Subject.new(x).choose("…", **opts).to_sym }` | `list.group_by(&ψ.choose("…", **opts))` |
| rank a stream | `list.sort_by { \|x\| S1::Subject.new(x).score("…", *levels).index }` | `list.sort_by(&ψ.score("…", *levels))` |
| the same thing? | `S1::Subject.new({ this: a, other: b }).judge?("Do this and other describe the same thing?")` | `(ψ a).same_as? b` · `case b when (ψ a)` |
| against a preference | `S1::Subject.new({ this: x, prefs: p }).judge?("… per prefs")` | `(ψ x).given(prefs: p).is? "… per prefs"` |

**What Ruby will not do.** `ψ"Michael".is? "…"` without parens is one method call whose argument is
`"Michael".is?("…")` — the dot binds before any prefix, symbol or operator — so the parens around the
subject are load-bearing: `(ψ"…")`, `(ψ text)`, `(ψ { … })`. And `is?` (the English form: "Is this …?") lives on `Subject` only, never on
core classes, where it would sit beside equality methods.

## Keeping the probability: collapse late

Collapse is one operation, and it is lossy. The measurement returns a distribution; turning it
into a boolean, a symbol or a level throws the rest away. Both layers are tools, and the
convention that separates them is Ruby's own: **no `?` keeps the probability, `?` collapses.**
`collapse` is the same step with a name, for when you want to see it. There is no second symbol
for it because Ruby already has one — the trailing `?` — and a reader who has never seen this
gem reads `judge` / `judge?`, `is` / `is?` correctly (see [The idea](#the-idea-collapse)).

**What the collapse hides.** Three calls, one question, one boolean each:

```ruby
clear = "I was rear-ended yesterday, the other driver ran a red light and got a ticket, my neck hurts."
murky = "there was a fender bender, not sure who was at fault, I feel a bit sore maybe."
none  = "I want to know your office hours."

(ψ clear).judge "Does the caller have a viable injury claim?"    # => 0.84   collapse → true
(ψ murky).judge "Does the caller have a viable injury claim?"    # => 0.52   collapse → true
(ψ none).judge  "Does the caller have a viable injury claim?"    # => 0.03   collapse → false
```

`clear` and `murky` collapse to the same `true`. What the boolean threw away: that one is a
case and the other is a coin flip — the difference between "call them now" and "have someone
look". `(ψ murky).judge(…).undecided?(0.15)` is `true`; `collapse` cannot say so. Every
downstream count, dashboard and decision built on the booleans inherits that erasure. The
distribution is the information; the collapse is a summary of it — take it last.

**The five conventional ways to use the distribution** — three keep it, and are plain Ruby;
two end it, and are `?`s:

| | you write | what it is |
|---|---|---|
| compose | `r[:is_lead] & r[:qualified] & ~r[:prior_rep]` | probability algebra on independent answers — keeps the distribution |
| route | `case p when 0.85.. then … when 0.5...0.85 then … else … end` | `Comparable` + ranges — keeps it |
| count | `calls.sum(&ψ.judge("…"))` | expected count from calibrated probabilities — keeps it |
| abstain | `p.undecided?(0.1)` → hand off | a `?` whose answer is "not by me" |
| collapse | `p.collapse`, `p.true?`, `judge?`, `is?`, `choice`, `level` (an `S1::Level`), `r.collapse` / `r.to_h`, `case r in { … }` | the decision — ends it |

```ruby
r = (ψ transcript).measure do |q|
  q.judge :is_lead,   "Is this a potential new personal-injury client?"
  q.judge :qualified, "Was the caller not at fault and injured?"
  q.judge :prior_rep, "Does the caller already have an attorney?"
end
```

**Compose before you collapse.** jev documents batched answers as independent — no answer is
context for another — and the gem relies on that, so probability algebra on them is exact: `&`
both, `|` either, `~` not.

```ruby
viable = r[:is_lead] & r[:qualified] & ~r[:prior_rep]     # => 0.84, still a Noul
```

**Route on the number, not the bit.** A Noul compares like a Float, so `case`/`when` with
ranges is the routing table — three outcomes from one probability, where a boolean gives two.

```ruby
case viable
when 0.85..      then call_now        # act automatically
when 0.5...0.85  then queue_review    # a person decides
else                  archive
end
```

**Abstain near the fence.** `undecided?(margin)` is "too close to call": hand off instead of
collapsing. `confident?` is its complement for choices and scores.

```ruby
return hold_for_human if viable.undecided?(0.1)
```

**Count without collapsing.** A sum of calibrated probabilities is an expected count; a count of
collapsed booleans rounds every 0.6 up and every 0.4 down.

```ruby
calls.sum(&ψ.judge("Is the customer angry?"))     # => 37.4 expected angry calls
calls.count(&ψ.is("an angry customer"))           # => 41, with the rounding baked in
```

**Then collapse, explicitly.** `collapse` on an answer or a whole `Result`; `?` on a method;
`!!` on a noul (`!answer` is "not true at the threshold"); `case … in { escalate: true }` on a
batch. All four are the same step. What is *not* a collapse: a bare `if answer` — Ruby's `if`
never calls `!`, so an answer object is always truthy there.

```ruby
viable.collapse            # => true          (threshold from config, or pass one)
viable.collapse(0.9)       # => false
r.collapse                 # => { is_lead: true, qualified: true, prior_rep: false }   (r.to_h is the same)
```

A choice collapses to its Symbol, a score to its `S1::Level` (the label, ordered by position),
and a `Result` to a Hash of all three.

## Collections: judgments as predicates

S1 models are at their best over *streams* — transcripts, tickets, candidates, calls — where
each item gets the same typed question and the answers are calibrated enough to filter, bucket,
rank and count on. This section is the data-science surface: `Enumerable` with judgments in the
blocks.

ψ with no argument is a question not yet bound to a state — a **predicate**, with `to_proc` and
`===`, so it goes wherever Ruby expects a block or a pattern. Applied to an element it returns
what `Enumerable` wants: `is` / `judge?` a boolean, `judge` the probability, `choose` the
symbol, `score` the `S1::Level` — so `sort_by` and `max_by` order by position, and `group_by`
keys by the label (`choice` and `level` the same, already collapsed). `measure(x)` on a
predicate gives the verb's collapsable and the noun's value, as on a Subject.

```ruby
angry = ψ.is("an angry customer")

calls.select(&angry)                                   # filter        (or calls.grep(angry), via ===)
calls.partition(&ψ.is("a new matter"))
calls.count(&ψ.judge?("Was it resolved on the call?"))
inbox.find(&ψ.is("a cancellation request"))

calls.group_by(&ψ.choose("Which team?", returns: "Refunds, exchanges", shipping: "Delivery, damage", billing: "Charges"))
# => { returns: [...], shipping: [...] }               # classify

tickets.sort_by(&ψ.score("How urgent?", "can wait", "today", "right now")).reverse   # rank
tickets.max_by(&ψ.score("How severe?", "cosmetic", "degraded", "blocking"))

calls.sum(&ψ.judge("Is the customer angry?"))          # => 2.0   expected count, no threshold
calls.sum(&ψ.judge("…")) / calls.size                  # share

calls.each_with_object([]) { |c, seen| seen << c unless seen.any?(ψ c) }   # dedupe, via ===
```

**The knob.** A stream is judged *against* something — a firm's acceptance criteria, a role's
requirements, a return policy. That configuration is the user's tuning input, and it has two
homes. On the question: `true:`/`false:` clarification for a noul, the option descriptions of a
choice, the levels of a score. Beside the data: `given` (or `against` — "judged against"), which
puts the element under `this` and the context next to it, so instructions can name both. (In
typesafe-rails a form does the same job: `s1_state(:qualification) { { transcript:, preferences: } }`.)

```ruby
qualifications = { must_have: ["5+ years Ruby", "shipped a Rails app"], disqualifiers: ["cannot work US hours"] }

qualified = ψ.is("qualified for the role, per `qualifications`", given: { qualifications: qualifications })
candidates.select(&qualified)                                                # => Michael, Dana

candidates.group_by(&ψ.choose("Per `qualifications`, which bucket?",
                              qualified: "meets every must_have, no disqualifier",
                              disqualified: "hits a disqualifier",
                              unclear: "not enough information",
                              given: { qualifications: qualifications }))    # => { qualified: [...], disqualified: [Bob] }

S1::Subject.new({ candidates: candidates, qualifications: qualifications })
  .choose("the candidate most qualified per `qualifications`", choices: %w[Michael Bob Dana]).ranked   # one call
```

Same shape for intake: calls stream → the firm's qualification preferences → qualified /
disqualified / unclear, and every other judgment the firm configures.

Two of these deserve a note. **Expected counts**: nouls are calibrated probabilities, so their sum
is the expected number of positives — a fractional headcount with no cutoff bias, where
`count(&ψ.is(…))` would round every 0.6 up and every 0.4 down. **Ranking a set** is one call, not
N: `choose` over the items returns a distribution over all of them, and `ranked` reads it out.

```ruby
S1::Subject.new(calls).choose("the call most likely to become a chargeback").ranked
# => [the angriest one, ...]                            one call for the whole list
candidates.choose("the most qualified for this role", choices: names).ranked.first   # add given: for the role's requirements
```

Cost model: every `&predicate` is one call per element (~400ms, run in parallel where you can —
typesafe-rails' `s1_select` takes `concurrency:`); prefer one `choose` over the items when the
question is "which of these", and reserve per-element predicates for "which of these are".

**One question, one or many.** A predicate is the question as a value, so define it once and
apply it to a single subject with `[]` (the collapsed value, what `Enumerable` sees) or `measure`
(the un-collapsed answer), and to a stream with `&`. No question text is written twice.

```ruby
team  = ψ.choose "Which team?", returns: "Refunds", support: "Product help", billing: "Charges"
angry = ψ.judge  "Is the customer angry?"

team[ticket]                          # => :returns
team.measure(ticket).probabilities    # => { "returns" => 0.91, "support" => 0.09, "billing" => 0.0 }
tickets.group_by(&team)               # => { returns: [...], support: [...] }

angry[ticket]                         # => 0.98
tickets.sum(&angry)                   # => 2.29
```

Predicates are built by `ψ` with no argument, or without the symbol by `S1.predicates`.
Inside `select(…)`, write the predicate with parentheses — `&ψ.is("…")` — Ruby's grammar does not
allow a command call after `&`.

## Dictionary and aliases

The classes, one per idea:

```
ψ(state)     S1::Subject          the measurable — judge · choose · score · measure
             S1::Predicate        a measurement with no measurable yet (ψ.is "…"), for select / group_by / sum
             S1::Question::*      the question on the wire: Noul | Choice | Score
             S1::Providers::*     who measures (TypeSafe's jev, cua-s1-forms, the Stub)

measure →    S1::Collapsable      what comes back: a probabilistic breakdown that can also just collapse
               Answer::Noul         the probability            collapse → true / false   (the `?`)
               Answer::Choice       the distribution           collapse → the symbol
               Answer::Score        the distribution           collapse → the level (S1::Level)
               Result               several, from measure { }  collapse → { id => value }; pattern-matches
             S1::Level            the label, a String that knows its position on the scale
```

A state is made measurable; a measurable is measured in one of three ways; measuring returns a
collapsable; a collapsable is the distribution, and can also just collapse.

| term | meaning | also |
|---|---|---|
| **state** | what the questions are about: a String, or a Hash/Array whose fields instructions can name with backticks | `S1::Subject.new(x)`; `ψ(x)` with `c.symbol = true`; `x.to_s1` with primitives on; the ambient one is `S1.subject` |
| **collapsable** | what a measurement returns: `Answer::Noul` / `Choice` / `Score`, and a `Result` — the distribution, with `#collapse(threshold)`: a boolean, a Symbol, an `S1::Level`, a Hash of them. Carries the nouns (`true?`, `choice`, `level`, `to_h`); the verbs live on the measurable | `S1::Collapsable` |
| **noul** | "Is this true?" — a probability from 0 to 1 (`Answer::Noul`); compares like a Float, composes with `&` `\|` `~` (independent), `undecided?(margin)` near the fence. `judge` measures, `judge?` collapses | `noul` is the wire name; `judge` the verb |
| **collapse** | the primitive, whole: stream in, category out. Three steps — **ψ** makes measurable, the verbs **measure** (a distribution), **`?` decides** (a category) — with plain arithmetic between | `collapse(threshold)` names the deciding step, on every collapsable; the shorthands are `verb(...).collapse` |
| **noul?** | the same, thresholded into `true` / `false` — the collapse; `collapse(threshold)` is its named form, on answers and on a `Result` | `ask?`, `judge?`; `is?("a man's name")` asks "Is this a man's name?", `same_as?(other)` asks whether two states describe the same thing (`===` is the same, for `case`/`when` and `grep`) — on `Subject` only, never on core classes (`is` / `same_as` for the probability) |
| **choice** | "Which of these?" — one option from an unordered set. `choose` measures (`Answer::Choice`, the distribution; `ranked` lists every option, most likely first); `choice` collapses (the option, a Symbol) | — |
| **score** | "Which level?" — a position on an ordered spectrum, worst → best. `score` measures (`Answer::Score`: `index`, `to_f` the weighted position, `levels`); `level` collapses (an `S1::Level`) | — |
| **level** | what a score collapses to: `S1::Level`, the label — a String — that knows its position (`index`, `to_i`, `scale`). Compares by position against an Integer, a Level or a label on its scale; matches integer ranges (`severity: 2..`) and labels (`severity: "Blocking"`); a Hash key interchangeable with its label; interpolates, stores and serializes as text | keep the level on the left of a comparison with a label |
| **ask** | a batch: several specific measurements (`q.judge` / `q.choose` / `q.score`), one call, independent answers (`Result`); a `Result` pattern-matches (`in { escalate: true, severity: 2.. }`) | `measure` (the theory's verb), `batch`, `ask_about` |
| **criteria** | the wire word for a question's shape: `true:`/`false:` clarification on a noul, `{ option => description }` on a choice, the ordered levels on a score | `choices:` on a choice |
| **threshold** | the probability at or above which a noul reads as true (config, per-state, or per-call) | — |
| **confident?** | far enough from the fence to act on without a person | — |
| **provider** | whatever answers a `Request` — `:typesafe` (jev) today, `:cua` locally, the `Stub` in tests, yours tomorrow | — |
| **primitives** | the opt-in core extension: String, Hash and Array answer questions about themselves | `Kernel` adds the bare forms |
| **predicate** | a question with no state yet — `ψ.is("…")`, `ψ.choose(…)`, `ψ.score(…)`, `ψ.judge(…)`, and the nouns `ψ.choice(…)`, `ψ.level(…)` — with `to_proc` and `===`, for `select`, `group_by`, `sort_by`, `sum`, `grep`; `[x]` applies it to one subject (`judge` the probability, the rest collapsed: a Symbol, an `S1::Level`), `measure(x)` gives the answer | `S1.predicates` |
| **given** | the context a judgment is made against — the element becomes `this`, the context sits beside it: `(ψ call).given(preferences: prefs)`, `ψ.is("…", given: { … })` | `against` (the same, read as "judged against"); a Rails form does the same |

Aliases are plain Ruby `alias`es, so a class's own method with the same name always wins.

## Errors

Rescue by intent, not by HTTP code:

```ruby
begin
  result = subject.measure { |q| ... }
rescue S1::TransientError => e     # RateLimitError, ServerError, ConnectionError, TimeoutError — retry later
  retry_later(e)
rescue S1::PermanentError => e     # AuthenticationError, InvalidRequestError, ValidationError — fix the request
  raise
end
```

Transient failures already retry inside the provider (`c.typesafe.max_retries`, honoring `Retry-After`) before surfacing.

## Testing

`Providers::Stub` answers without the network. Give it the answers that matter; everything
else gets a neutral default (noul 0.5, the first option, the first level).

```ruby
S1.configure do |c|
  c.provider = S1::Providers::Stub.new(escalate: 0.9, department: :billing, severity: 2)
end
```

Single-question calls are keyed by the wire name of their kind — `noul` (for `judge`, `judge?`,
`is?`, `same_as?`), `choice`, `score`: `Stub.new(noul: 0.9, choice: :billing, score: 2)`.

A block form receives the request when an answer should depend on the state:

```ruby
S1::Providers::Stub.new { |req| { escalate: req.state.include?("real person") ? 0.95 : 0.1 } }
```

## Observing calls

Hook every completed call for telemetry or a cost ledger. Extra keyword arguments to
`Subject.new` ride along on the request, so you can attribute a call to its owner:

```ruby
S1.on_result do |result, request|
  Ledger.record(owner: request.options[:owner], model: result.model, **result.usage)
end

S1::Subject.new(transcript, owner: phone_call).judge?("...")
# ψ: (ψ transcript, owner: phone_call).is? "…"
```

## Providers

A provider is the code that talks to a model: any object responding to `call(request) → Result`.
The gem owns the shape — `Request`, `Question`, `Answer`, `Result`, the method signatures on
`Subject`, the error taxonomy; a provider owns only translation: how the state and questions go
on the wire, how answers come back as `Answer` objects, how failures map to `TransientError` /
`PermanentError`. A provider declares which question types it answers (`supports?`); the rest
are refused before any call (`UnsupportedError`). Configure by name — `:typesafe` resolves to
`S1::Providers::TypeSafe`, built from its section of the config — or pass an instance.

```ruby
S1.configure { |c| c.provider = :typesafe }
S1::Subject.new(text, provider: MyProvider.new)   # per-state override   ψ: (ψ text, provider: MyProvider.new)
```

Four ship. TypeSafe and Laya share one thing — the System One HTTP contract (`Providers::SystemOneHTTP`,
the `/v1/systemone` JSON that jev defined and Laya adopted) — and are otherwise separate
classes under `Base`, each with its own settings, auth and models; Cua and Stub share nothing
with them but the answers:

| provider | what | primitives | transport |
|---|---|---|---|
| `TypeSafe` | TypeSafe's jev, hosted | noul, choice, score | HTTPS `/v1/systemone` |
| `Cua` | [cua-s1-forms](https://huggingface.co/cua-ai/cua-s1-forms), a 2.8 MB jev-like option scorer for GUI forms | choice | a local Python sidecar over stdin/stdout (`support/cua_s1_sidecar.py`; needs `cua-s1` + torch, checkpoint as safetensors + json) |
| `Laya` | [Laya](https://github.com/NandhaKishorM/laya), self-hosted, Apache-2.0: the same three primitives and the same System One HTTP contract as jev; 322–421M-parameter encoder (English / 100+ languages / typed-decisions checkpoints) | noul, choice, score | HTTP to a server you run — `support/laya_server.py` wraps `pip install laya` in the same `/v1/systemone` contract; no key |
| `Stub` | canned answers for tests | all | none |

```ruby
S1.configure { |c| c.provider = :cua; c.cua.checkpoint = "cua-s1-forms" }
S1.configure { |c| c.provider = :laya; c.laya.base_url = "http://127.0.0.1:8765" }   # python support/laya_server.py
S1::Subject.new('TASK fill the form  ELEMENT Edit "Phone number"').choose("Which entity?", phone: "555-0100", email: "a@b.c", skip: nil)
```

Translation Cua owns, as an example of what a provider decides: the state becomes the
context string (JSON for structured state), option descriptions become `"key: description"`
within the model's byte limits, the argmax is the pick and its probability the confidence,
and noul / score are refused rather than emulated — the model is trained on form elements,
not propositions.

**Writing one.** Subclass `S1::Providers::Base` and do five things: declare `settings` (its
section of `S1.config`, with defaults — `settings :name, key: default` defines `c.name.key`,
handed to `new` when the provider is named); answer `supports?(question)` honestly; implement
`call(request) → Result` by building every answer with `answer(id, question, raw:, **fields)` —
the only constructor, which is what makes every provider's collapsables identical and keeps a
vendor's wire keys out of consumers' hands — and returning `build_result(answers:, model:,
usage:, raw:)`; map failures onto `S1::TransientError` / `S1::PermanentError`; leave `name`
alone. Then run the conformance suite the gem ships:

```ruby
require "s1/rspec"
RSpec.describe MyProvider do
  it_behaves_like "an S1 provider", -> { MyProvider.new(client: fake) }             # all three kinds
  it_behaves_like "an S1 provider", -> { ChoiceOnly.new }, supports: %i[choice]      # or fewer
end
```

It checks the shape, not the wisdom: a `Result` that is a `Collapsable`, every id answered with
the class its type demands, probabilities in [0, 1] summing to 1, choices keyed by option and
scores by level index, `collapse` yielding a boolean / Symbol / `S1::Level`, `supports?` telling the
truth, integer usage. The three providers here pass it; that is the standard.

## Development

`bin/setup`, then `bundle exec rake` runs the specs and rubocop. `bin/console` opens IRB with the
gem loaded. `TYPESAFE_LIVE=1 TYPESAFE_API_KEY=… bundle exec rspec spec/s1/live_spec.rb`
hits the real API.

## License

MIT.
