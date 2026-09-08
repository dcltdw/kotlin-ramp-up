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

**Stack.** Kotlin 2.4.10 · Spring Boot 4.1.1 · Java 21 LTS · Gradle 9.7.1 Kotlin
DSL · ktlint/Detekt/Kover · deployed to EC2 (`t4g.small`).

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

## Building

```sh
./gradlew build          # compile, ktlint, detekt, test, coverage
./gradlew bootRun        # http://localhost:8080/api/ping
```

The Gradle daemon is pinned to **Java 21** in
`gradle/gradle-daemon-jvm.properties`, and Gradle downloads that JDK on first
run if it is not installed. The pin is not cosmetic: detekt 1.23.8 runs
in-process in the daemon and its bundled compiler throws on a JDK 25 runtime.
There is no detekt release that supports Kotlin 2.4 yet, so its analysis
classpath is also pinned back — see the comments in `build.gradle.kts`.

## Container

The image copies a pre-built jar rather than compiling; a 2 GiB `t4g.small` is
the wrong place to run a Gradle build. Because a JVM jar is
architecture-neutral, targeting Graviton from an x86 laptop is a plain layer
copy with no emulation.

```sh
./gradlew build
docker buildx build --platform linux/arm64 -t catalog-personalization:arm64 .
```

## Deploy

One `t4g.small` on a public subnet, running the arm64 container out of ECR.
No NAT Gateway, no load balancer, no SSH — shell access is SSM Session Manager.
Roughly **$0.53/day**.

```sh
cp infra/terraform.tfvars.example infra/terraform.tfvars   # set your alert email
terraform -chdir=infra init
terraform -chdir=infra apply

scripts/deploy.sh          # build, push to ECR, restart, verify reachable
scripts/teardown.sh        # destroy everything, then prove it is gone
```

Both scripts are meant to be read before they are run — that is the plan's rule
for deployment work from Day 2 onward. Full runbook, cost breakdown and the
state-file warnings: [infra/README.md](infra/README.md).

## Contentful

Catalog content lives in Contentful. See [contentful/README.md](contentful/README.md)
for the content model, the seed, and how to reset the space.
