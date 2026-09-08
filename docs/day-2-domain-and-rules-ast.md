# Day 2 — Domain and rules AST

A working guide for the hand-written day: the sealed hierarchies, the evaluator,
and the tests that carry both.

**[Issue #3](https://github.com/dcltdw/kotlin-ramp-up/issues/3) is authoritative
for whether Day 2 is done.** The acceptance criteria are restated below for
readability, but if the two ever disagree, the issue wins. Two checklists that
both claim to be canonical is how they drift.

Background and constraints: [kotlin-5-day-plan.pdf](kotlin-5-day-plan.pdf), §2
and the Day 2 entry.

---

## The shape of the service

Frontends send a product catalog request together with a **customer context**.
The service returns that catalog *filtered* and *decorated* for the customer.
Those two verbs are the whole design, and they map exactly onto the four
decisions:

| Half | Decisions | Acts on |
|:--|:--|:--|
| **Filter** — which products may this customer see? | `Include`, `Exclude` | a product |
| **Decorate** — what should we say to them? | `ShowCta(id, variant)`, `HideCta(id)` | the response |

## What "CTA" means

**Call to action** — the prompt a storefront shows a shopper: a banner, a badge,
a button. *"Free shipping on orders over $100."* *"VIP early access."*

A **variant** is one wording of the same CTA, the unit an A/B test compares. The
plan's requisition table lists *"CTA / experimentation frameworks"* as **partially
closed via CTA decisions and variants** — variants are what make this a
personalization service rather than a catalog filter.

The vocabulary already exists, hand-built in Contentful and captured in
[`contentful/seed.json`](../contentful/seed.json):

| Type | Fields | Seeded values |
|:--|:--|:--|
| `cta` | `ctaId`, `name`, `variants` (≥1 link) | `free-shipping`, `vip-early-access` |
| `ctaVariant` | `variantKey`, `label`, `headline`, `body`, `buttonLabel` | `control`/`urgency`, `control`/`personalized` |
| `segment` | `segmentId`, `name`, `description` | `vip`, `newsletter`, `firstTimeBuyer` |

So `ShowCta(CtaId("free-shipping"), VariantKey("urgency"))` reads as: *show the
free-shipping banner, in the urgency wording.*

**Day 2 needs only the identifiers.** Resolving `urgency` to its actual headline
text is the Day 3 Contentful client ([#4](https://github.com/dcltdw/kotlin-ramp-up/issues/4)). That is the first seam: the AST
*names* content, it does not *contain* content.

## The customer context

One job: the **read-only input to evaluation**, and the thing you vary to make
rules produce different answers. Nothing mutates it, nothing persists it. That
is why it is a value object rather than an entity.

Three facts, derived from the plan's own example rule —
`Segment("vip") and (CartValue gte 100.usd) and not Region("EU")`:

| Fact | The only operation performed on it | What that implies |
|:--|:--|:--|
| Segments the customer is in | membership — "is `vip` in here?" | Order and duplication are meaningless, so a `Set`. You need `contains` and nothing else. |
| Cart value | compare against a threshold **of the same currency** | Two steps: currency equality, *then* magnitude. See below. |
| Region | equality against a literal | A single value, `==` only. No collection needed. |

Work out the operation before choosing the type. `Segment("vip")` never
iterates, never sorts, never asks "how many" — it asks one question. A `List`
would work and would also let you write meaningless code.

### Why `Money` must not implement `Comparable`

`CartValue gte 100.usd` looks like a simple comparison, but
[`contentful/README.md`](../contentful/README.md) already commits to the rule:
**a currency mismatch does not match — no conversion, no exception.**

`Comparable` promises a *total* order: that any two values can be ranked. Under
that rule, EUR 200 and USD 100 have no ordering at all. Implementing
`Comparable` forces you to invent an answer — throw? return `0`? compare the raw
amounts? — and every one of those is wrong.

What you want is a comparison whose result can say **"not comparable"** as a
first-class outcome, which the evaluator then turns into "predicate false". This
is the plan's point about the type system encoding what you would otherwise
handle "with a docstring and a prayer": the docstring version says *callers must
check the currency first*, and the type version makes not checking impossible.

### Context versus ruleset

Easy to conflate, and they have different lifecycles:

- **Ruleset** — authored, stored, versioned. This is what needs
  `kotlinx.serialization` round-tripping.
- **Context** — constructed fresh per request, never stored.

So on Day 2 the context needs **no serialization at all**. It becomes JSON later,
when an endpoint exists to receive it.

---

## What the evaluator does

The evaluator has **two** inputs, not one:

```
evaluate(ruleset, context) → decisions
         ▲        ▲           ▲
         │        │           └─ Include / Exclude / ShowCta / HideCta
         │        └───────────── facts about this customer
         └────────────────────── the policy someone authored
```

The context is the easy half to picture. The **ruleset** is the half that makes
the evaluator look like it has nothing to do if you have not met it yet.

### A rule is an if-then pair

> **if** `Segment("vip") AND CartValue >= 100.usd AND NOT Region("EU")`
> **then** `ShowCta("free-shipping", "urgency")`

The left side is an **expression**: it answers *does this rule apply to this
customer?* and evaluates to a `Boolean`. The right side is the **decisions** to
emit when it does. A ruleset is a list of those pairs.

So the evaluator's job, per rule: evaluate the expression against the context,
and if it is true, emit that rule's decisions. Collect everything emitted. That
is the whole mechanism.

### Worked through with the seeded data

The same rule, against two customers:

**Customer A** — `segments={vip}`, cart `$129 USD`, `region=US`

| Predicate | Reads | Result |
|:--|:--|:--|
| `Segment("vip")` | is `vip` in `{vip}`? | true |
| `CartValue gte 100.usd` | same currency, `12900 >= 10000` | true |
| `NOT Region("EU")` | `US ≠ EU` | true |
| `AND` of the three | | **true** |

Emits `ShowCta(free-shipping, urgency)`.

**Customer B** — `segments={newsletter}`, cart `$59 USD`, `region=EU`

`Segment("vip")` is false, so the `AND` is false. Emits **nothing**.

Same ruleset, same evaluator, different answers — because the context differed.
That is what "the context is the independent variable" means in practice, and
why the seeded catalog was built with values either side of every threshold.

### Why it recurses

The expression is not flat. It is a tree:

```
And
├── Segment(vip)                 ← leaf: reads the context
├── CartValueAtLeast(100 USD)    ← leaf: reads the context
└── Not
    └── Region(EU)               ← leaf: reads the context
```

Evaluating it means walking that tree:

- `And` — evaluate each child, combine with `&&`
- `Or` — evaluate each child, combine with `||`
- `Not` — evaluate the child, negate it
- a leaf — read the relevant fact from the context and compare

The composite nodes **recurse**; only the leaves touch the context. This is the
classic **tree-walking interpreter**, which is the term to search for if you want
the literature.

That is also why the hierarchy is sealed. The evaluator is one `when` with a
branch per node type, so adding a fifth predicate later stops the build until it
has been handled — in the evaluator, in the serializer, everywhere. The plan's
line about the compiler walking you through every evaluator, serializer and
explainer that needs updating is describing exactly this.

### Why rules are data instead of `if` statements

This is the question underneath the whole design, and it is worth being explicit
about.

You could hardcode `if (customer.isVip && cart >= 100) showFreeShippingBanner()`.
But that policy changes weekly, and every change would mean editing Kotlin,
running CI and redeploying.

Making rules **data** means the policy can be authored, stored, versioned and
swapped without touching the engine. The evaluator gets written once. That is
what a rules engine *is* — and it is why the ruleset needs serialization while
the context does not: a ruleset is saved and reloaded, a context is discarded
after one request.

## Rulesets

### Does `Ruleset` need to be a type?

`List<Rule>` might be enough, and a wrapper earns its place only if it carries
something more. One argument settles it: **a bare list serializes to a JSON
array, which leaves nowhere to put a schema version.** Wrap it and there is room
to grow.

```json
{ "version": 1, "rules": [ ... ] }
```

That single field is the difference between being able to change the rule format
later and not, and it is cheaper to add now than to retrofit once rulesets are
stored anywhere.

### As data: JSON, and specifically polymorphic JSON

Not Markdown — that is for documents people read, not machine-readable policy.
The acceptance criteria commit to `kotlinx.serialization`, so JSON is settled.

The structural question that matters is **how each node declares which variant it
is**. A sealed hierarchy serialized polymorphically needs a *discriminator*;
`kotlinx.serialization` writes a `"type"` key by default, adjustable through
`@SerialName` and `classDiscriminator`. That mechanic **is** the serialization
exercise, not an incidental detail of it.

Roughly what a ruleset looks like on the wire — illustrative shape only, **not a
prescribed AST**:

```json
{
  "version": 1,
  "rules": [
    {
      "expression": {
        "type": "And",
        "operands": [
          { "type": "Segment", "segmentId": "vip" },
          { "type": "CartValueAtLeast", "amountMinor": 10000, "currency": "USD" },
          { "type": "Not", "operand": { "type": "Region", "region": "EU" } }
        ]
      },
      "decisions": [
        { "type": "ShowCta", "ctaId": "free-shipping", "variantKey": "urgency" }
      ]
    }
  ]
}
```

Note how the nesting mirrors the tree exactly. That correspondence is what makes
"serialize → deserialize → `assertEquals`" a meaningful assertion rather than a
formality.

**Do not define `Ruleset` during the Python-shaped pass.** In step 2 below the
"ruleset" is a `List<Map<String, Any?>>` and nothing more. A typed ruleset in v1
defeats the comparison the exercise exists for; `Ruleset` becomes a real type in
step 4.

### Formats met in the wild

Worth recognising by name, since a Java/Kotlin eCommerce shop will have opinions
about at least two of them:

| Format | Where it shows up |
|:--|:--|
| JSON | The default for rules-as-data, and this project's choice |
| YAML | Human-authored rules; common in feature flagging |
| Decision tables (CSV, spreadsheet) | Genuinely widespread in eCommerce and insurance |
| Drools `.drl` | Its own text language, with its own engine |
| A DSL over a typed tree | Day 3 here — authoring ergonomics without giving up the types |

---

## Where to start

The plan already answers this, in a line that reads like a footnote:

> *Deliberate exercise: write the evaluator once the way you would in Python
> (dicts and string tags), then again with sealed classes, then delete the
> first.*

**"The way you would in Python" is about idiom, not language.** Version one is
Kotlin written Python-shaped — `Map<String, Any?>` for rules, string tags for
types, `when (rule["type"] as String)` for dispatch. Deliberately bad Kotlin.
There is no Python in this project.

That distinction is why the exercise works: same language and the same test
suite on both sides means the only variable is how rules are represented, so the
difference you feel is attributable to sealed classes. Write actual Python and
you are comparing ecosystems instead.

The plan leaves one thing implicit, and it is the load-bearing part: **the tests
survive both implementations.**

1. **Write the customer context first.** The evaluator's input. Smallest
   possible type, no behaviour. Everything depends on it; it depends on nothing.
   This step is safe to do before settling anything in
   [Decisions the plan does not make](#decisions-the-plan-does-not-make) — the
   context holds customer facts either way.
2. **Write the Python-shaped evaluator.** Fast, because it demands no design
   decisions of its own — but read decisions 1 and 2 in that section first,
   because they fix the signature you are about to write twice.
3. **Write the tests against it** — the full set, using real seeded values
   (`vip`, `free-shipping`, `EU`, a $129 product against a $59 one). This is the
   hard part and the part that pays twice.
4. **Now the sealed version, against those same tests.** No new test-writing, so
   all attention goes to the types. Where the string-tag version needed a runtime
   check, the compiler now demands a branch — note each instance as you hit it,
   because that gap is the lesson.
5. **Serialization last.** Bolting `kotlinx.serialization` onto a finished sealed
   hierarchy teaches the polymorphic-registration mechanics cleanly; doing it
   first entangles wire format with modelling.
6. **Delete the Python-shaped version.** Write up the comparison *before* you
   delete it, not after — "I deleted it" with no notes loses the only deliverable
   of that step.

Keep the **context fixed** across both evaluators. Vary only the rule
representation. If both change, you cannot attribute the difference to either.

---

## Where the seams are

Four boundaries, outermost to innermost. Each is a place you can stop with
something that compiles and passes tests.

- **Identity vs content.** The AST holds `CtaId` and a variant key — never a
  headline, price, or product name. Consequence: Day 2 needs no Contentful access
  and is entirely unit-testable with no network. Wanting a product's *name* in a
  decision means the seam has been crossed.
- **Expression vs decision.** Two sealed hierarchies, not one. An expression
  answers *does this apply?* (`Boolean`); a decision says *then do this*.
  Conflating them is the standard mistake and it makes `Or` incoherent. A ruleset
  is then a list of `Rule(expression, decisions)`.
- **Filtering vs decorating.** Same hierarchy, different targets — so the
  evaluator's signature is a real decision. See the arity problem below.
- **AST vs authoring syntax.** Day 2 builds the tree; Day 3 builds the pleasant
  way to write it. The plan's own example is written in Day 3's syntax, which is
  what makes this confusing — read `Segment("vip") and ...` as *what the DSL will
  produce*, and build the thing it produces.

### The arity problem

```
request: catalog + CustomerContext
                │
                ├─ Include / Exclude ──→ decided PER PRODUCT   (12 products → 12 evaluations)
                └─ ShowCta / HideCta ──→ decided PER REQUEST   (1 answer, not 12)
```

Both families live in one sealed hierarchy but they do not share an arity.
Evaluate one ruleset per product and the CTA decisions come back twelve times;
evaluate once and you cannot filter products. So you need one of:

- two passes over two rule sets, split by what they decide
- one pass per product, deduplicating CTA decisions afterwards
- the type system keeping them apart, so the mismatch cannot be written

---

## Decisions the plan does not make

Four questions the plan, #3 and this guide all leave open. They are gathered
here rather than scattered, because a decision you cannot find is a decision you
make twice.

The first two shape the evaluator's signature, so they are worth settling before
writing it. The last two only bite on the second rule, but they bite hard.

### 1. What does a predicate read?

The plan's example mixes sources without comment: `Segment("vip")` and
`CartValue gte 100.usd` are facts about the *customer*, while `Region("EU")`
could be either — the customer's region, or a product's `regions` availability
array. The seed supports both readings (products carry `US`, `EU`, `UK`,
`APAC`).

1. Predicates read the context only; product availability is filtered
   separately, outside the rules engine.
2. Predicates read `(context, product)` together, so `Region` means "is this
   product available in the customer's region".
3. Two predicate hierarchies, one per input, kept apart by the type system.

Option 2 is the smallest thing that makes the plan's example work as written.

### 2. Do all matching rules fire, or only the first?

Drools fires every match; feature-flag evaluators usually stop at the first.

The two decision families may want different answers, which is the interesting
part: accumulating CTA decisions is sensible, whereas a single `Exclude`
arguably ought to veto a product regardless of what else matched. If they do
differ, that is evidence for the "two passes over two rule sets" resolution of
the arity problem above.

### 3. What happens when two rules disagree?

One rule emits `ShowCta("free-shipping", "urgency")`; another emits
`HideCta("free-shipping")`. Which wins?

Real engines answer with priority or salience, first-match-wins, or
last-write-wins. Any of those is defensible; having no answer is not, because
the behaviour then depends on list order by accident rather than by decision.

This one also determines a type: whether `evaluate` returns a raw
`List<Decision>` or something that has already resolved conflicts.

### 4. What is the default when nothing matches?

Is a product included unless excluded, or excluded unless included?

That choice silently decides whether an empty ruleset shows the entire catalog
or none of it — and "empty ruleset" is exactly the state the first test runs
against.

---

## Acceptance criteria

Restated from [#3](https://github.com/dcltdw/kotlin-ramp-up/issues/3), which
remains authoritative.

**Types**
- Two *separate* sealed hierarchies: rule **expressions**, and **decisions**.
- Decisions are exactly `Include`, `Exclude`, `ShowCta(id, variant)`, `HideCta(id)`.
- Value classes for `SegmentId`, `Sku`, `CtaId` (`@JvmInline`), so a raw `String`
  cannot be passed where an id belongs.
- At least three predicates: `Segment(...)`, `CartValue gte ...`, `Region(...)`,
  plus `And` / `Or` / `Not`. The cut list permits dropping "more than three rule
  operators", so three is the floor, not the target.
- Money carries a currency. Products store `priceMinor` + `currency`, and `USD`,
  `GBP`, `EUR` all appear in the seed.

**Evaluator**
- Every `when` over a sealed type is exhaustive with **no `else` branch**. An
  `else` silently defeats the entire point of the day.
- A currency mismatch **does not match** — no conversion, no exception.
- Evaluating the same ruleset twice against the same input gives the same answer.

**Serialization**
- `kotlinx.serialization` round-trips a ruleset: serialize → deserialize → equal.
  Sealed hierarchies need polymorphic registration, which is the actual exercise.

**Tests** — hand-written, per the day's whole premise
- Both branches of every predicate. The seed catalog was built for this: 6
  products either side of $100, 5 available in `EU` against 7 not, 4 tagged `vip`
  spanning $129–$499.
- At least one test per decision type.
- A round-trip test for the serialized form.
- `./gradlew build` green.

**The deliberate exercise**
- The Python-shaped evaluator written, compared, and **deleted**.
- The comparison written down — a comment on #3 or a commit message.

**Out of scope — other days, do not build them here**
- No DSL. `Segment("vip") and (CartValue gte 100.usd)` is Day 3 ([#4](https://github.com/dcltdw/kotlin-ramp-up/issues/4)). Day 2
  writes `And(Segment(SegmentId("vip")), ...)` with plain constructors.
- No Contentful client, no HTTP, no caching, no coroutines — Day 3.
- No Spring wiring, no new endpoint. Day 2 is pure domain with unit tests.
- No persistence. Cut-listed outright.

---

## Testing

### Where tests live

Mirror the main package under `src/test/kotlin`:

```
src/main/kotlin/dev/dcltdw/catalog/domain/CustomerContext.kt
src/test/kotlin/dev/dcltdw/catalog/domain/CustomerContextTest.kt
```

Mirroring is not cosmetic: the same package means tests see `internal`
declarations and need no imports for the types under test, and Kover's per-class
reports line up with the source tree. Note that package segments are
**directories** on disk (`dev/dcltdw/catalog/domain`); the dots appear only in
the `package` declaration. IntelliJ's Project view flattens them into one row,
which is misleading.

### Do not use `@SpringBootTest` for domain tests

Both pre-existing tests are annotated with it because they need a real servlet
container. Domain tests are pure functions over value objects — a plain class
with `@Test` methods, no Spring context. The difference is milliseconds versus
seconds, and these run constantly. Copying `PingControllerTest` as a template
inherits `@SpringBootTest` by accident and boots the whole application to test a
`Set` membership check.

### Do not test compiler-generated getters

IntelliJ's *Create Test* dialog offers a stub per member, including the JVM
getters Kotlin generates for `val` properties (`getSegment()`,
`getPriceInPennies()`, …). Delete those. A test that constructs with
`setOf(VIP)` and asserts `segment == setOf(VIP)` tests the Kotlin compiler, and
stays green while your rules are broken.

Note also that `TODO()` in a generated `@BeforeEach` **throws**
`NotImplementedError`, failing every test in the class for reasons unrelated to
your code.

### The fixture habit

Arrange, act, assert — and give yourself a factory with defaults so each test
states only what it varies:

```kotlin
private fun context(
    segments: Set<Segment> = emptySet(),
    cartMinor: Int = 5_000,
    currency: Currency = Currency.USD,
    region: Region = Region.US,
) = CustomerContext(segments, cartMinor, currency, region)
```

```kotlin
val c = context(currency = Currency.GBP)   // this test is about currency
val c = context(cartMinor = 9_900)         // this test is about the threshold
```

A good test names its one variable and hides everything else. Use **named
arguments** at call sites — with four parameters, two of them enums, positional
arguments are how a region ends up where a currency belongs.

`@ParameterizedTest` with `@MethodSource` is available and suits the "both
branches of every predicate" criterion: one test, a table of contexts and
expected outcomes.

There is no `java-test-fixtures` source set, so shared fixtures simply live in
the test tree.

### Property-based testing

`kotest-property` 5.9.1 is on the test classpath — the property module only, so
it runs inside a plain JUnit `@Test` without bringing Kotest's spec style:

```kotlin
runBlocking {
    checkAll(Arb.int(1..100), Arb.int(1..100)) { a, b -> /* assert */ }
}
```

Two traps, each worth one compile cycle if unknown:

- `checkAll` is a **suspend** function, so it needs `runBlocking`.
  `kotlinx-coroutines-core` is declared for exactly that reason —
  kotest-property does not put coroutines on the compile classpath itself, and
  the error reads `Unresolved reference 'coroutines'` rather than naming the real
  cause.
- Use a **block body**, not `= runBlocking { checkAll(..) }`. The expression form
  returns `PropertyContext`, and JUnit 5 requires test methods to return `Unit`.

`src/test/kotlin/dev/dcltdw/catalog/PropertyTestingToolchainTest.kt` is a working
example of both forms. It is a toolchain smoke test with no domain content —
**delete it** once real property tests exist here.

**Where it earns its place on this day:** the `Money` comparison is a *partial*
order. "For any two amounts in different currencies, neither is greater" is a
property; example-based tests can only sample it. Same for "evaluating the same
ruleset twice gives the same answer".

### Running them

```sh
./gradlew test                                    # tests only — use this while iterating
./gradlew test --tests '*CustomerContextTest*'    # one class, fast loop
./gradlew build                                   # + ktlint, detekt, Kover
```

**Prefer `./gradlew test` while writing code.** `koverVerify` enforces a 80%
line-coverage floor and runs only under `check`/`build`, so adding code before
its tests will fail `build` — which is the normal first move of a session. Run
the full `build` when you are ready to commit.

There is deliberately **no branch-coverage bound yet**, because the codebase had
no branches when the floor was set. The sealed `when` blocks on this day are
almost entirely branches, so this is the natural point to add one.

### Style

ktlint and detekt both run in `build`, so style is enforced rather than
remembered. Conventions worth knowing up front: PascalCase for types, camelCase
for functions and properties, `SCREAMING_SNAKE_CASE` only for `const val` and
(optionally) enum entries, backtick-quoted names with spaces for test functions,
trailing commas on multi-line parameter lists, one enum entry per line, and a
120-character line limit.

The repo uses **AssertJ** (`assertThat`) rather than JUnit's `Assertions`, and
ktlint rejects wildcard imports.
