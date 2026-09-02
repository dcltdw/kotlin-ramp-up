# kotlin-ramp-up

A five-day Kotlin ramp-up ahead of a Java/Kotlin eCommerce contract: learn the
language properly, close the largest gaps in the job requisition, and get real
practice deploying a JVM service to AWS.

**Constraints.** All Kotlin is hand-written; agents are used for infrastructure
only (Days 1, 4, 5) and for *describing* deployment steps on Days 2–3. AWS spend
is capped at $100 and expected under $50.

**The project** is a catalog personalization service: a rules engine authored in
a Kotlin DSL and compiled to a sealed-class AST, a Contentful content source
with caching and concurrent bulk fetch, and a hand-made "legacy Magento-shaped"
JSON export migrated into the Contentful content model.

**Stack.** Kotlin 2.4 · Spring Boot 4.1.1 · Java 21/25 LTS · Gradle Kotlin DSL ·
ktlint/Detekt/Kover · deployed to EC2 (`t4g.small`).

| Day | Focus | Mode |
|:---|:---|:---|
| 1 | Project skeleton, one endpoint, containerized and deployed; Contentful model | agent-assisted |
| 2 | Domain and rules AST — sealed hierarchy, evaluator, serialization | hand-written |
| 3 | The type-safe builder DSL and the CMS client | hand-written |
| 4 | Migration and Java interop — the legacy adapter | mixed |
| 5 | CI, health endpoints, observability, load test | agent-assisted |

**Protected if behind:** the sealed AST, the DSL, the evaluator, and at least
three deployments.

Full plan, including the requisition mapping, scope cut-list and cost
guardrails: [docs/kotlin-5-day-plan.pdf](docs/kotlin-5-day-plan.pdf).
