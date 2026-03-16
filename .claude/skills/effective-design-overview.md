---
name: effective-design-overview
description: >
  Strategic software design and architecture decision-making grounded in Domain-Driven Design.
  Use this skill when the user is discussing system design, architecture selection, domain modeling,
  bounded contexts, or when evaluating whether a particular architectural pattern (hexagonal, clean,
  vertical slices, CQRS, event-driven) fits their problem. Also trigger when the user asks about
  DDD concepts, aggregate design, bounded context boundaries, or how to decompose a system.
  This skill is the upstream decision-maker for tactical architecture skills like
  hexagonal-architecture — consult it first when the right architectural approach isn't obvious,
  or when an existing approach feels like it's being stretched. Trigger on phrases like
  "what architecture should I use", "is this the right pattern", "how should I structure this system",
  "domain model", "bounded context", "aggregate", or general software design discussions.
---

# Effective Design Overview

This skill provides the strategic design lens for making architectural decisions. It is grounded
in Domain-Driven Design (DDD) as the conceptual framework and maps DDD concepts to tactical
architectural patterns. It does not replace pattern-specific skills (like hexagonal-architecture)
but informs *when and why* to reach for them.

## Relationship to Other Skills

This skill is upstream of tactical architecture skills. The flow:

1. **Design discussion or new system** → This skill activates to assess the problem space
2. **Pattern selection** → Based on domain analysis, recommend a tactical approach
3. **Tactical skill takes over** → e.g., hexagonal-architecture skill handles the implementation

If the hexagonal-architecture skill (or similar) is already active and the architecture fitness
check raises concerns, this skill provides the broader context to evaluate alternatives.

When this skill recommends hexagonal architecture, hand off to the hexagonal-architecture skill
for implementation details. Don't duplicate its guidance here.

## Domain-Driven Design: The Strategic Foundation

DDD is not an architecture. It's a way of thinking about software that prioritizes understanding
the business domain and letting that understanding drive design decisions. Everything else —
hex, clean, slices, CQRS — are implementation tactics that serve DDD's strategic goals.

### Core DDD Concepts and Their Architectural Implications

**Ubiquitous Language:**
The code should use the same terms the business uses. If the business says "policy," the code
says `Policy`, not `InsuranceProductRecord`. This isn't cosmetic — it's the mechanism that keeps
the model honest. When naming feels awkward, it usually signals a modeling problem. If you
find yourself needing a translation layer between what the business calls things and what the
code calls things *within the same context*, the model has drifted.

Architectural implication: The domain layer's types, methods, and events should read like a
description of the business process. If an architect or product person can't roughly follow
the domain code, something is wrong.

**Bounded Contexts:**
A bounded context is a boundary within which a particular domain model is consistent and
meaningful. The same real-world concept can have different representations in different contexts.
"Customer" in billing is different from "Customer" in shipping — different attributes, different
rules, different lifecycle. Trying to force one unified model creates bloated god-objects.

Architectural implication: Each bounded context is an independent modeling and deployment unit.
It gets its own architecture decision. A billing context with complex pricing rules might use
hex with a rich domain. A notification context that just dispatches messages might be simple
functions. A reporting context might bypass domain modeling entirely and use CQRS read models.

**Context Mapping (how contexts relate):**
Bounded contexts don't exist in isolation — they have relationships that determine how you
build the integration between them. DDD defines several relationship patterns:

- **Anticorruption Layer:** A translation layer that protects your model from another context's
  model. This *is* a hex adapter — it implements an outbound port while translating between
  your domain types and the external context's types. Use when integrating with legacy systems,
  third-party APIs, or contexts with models you don't control.
- **Shared Kernel:** Two contexts share a small, explicitly defined subset of the model.
  Changes require coordination. Use sparingly — it creates coupling. Only appropriate when
  two contexts are tightly aligned and maintained by the same team.
- **Upstream/Downstream:** One context publishes (upstream), another consumes (downstream).
  The downstream context adapts to the upstream's model. Events are the natural implementation
  mechanism. The downstream adapter translates upstream events into its own domain types.
- **Conformist:** The downstream context accepts the upstream's model as-is, without translation.
  Appropriate when the upstream model is good enough and translation adds no value.
- **Open Host Service / Published Language:** The upstream context exposes a well-defined
  API or event schema designed for external consumption. This is the port in hex terms —
  the explicit contract other contexts program against.

Architectural implication: Context map relationships directly inform adapter design. When you
see "anticorruption layer" in DDD, think "outbound adapter with translation logic" in hex.
When you see "published language," think "inbound port with a stable contract."

**Aggregates:**
An aggregate is a cluster of domain objects treated as a single unit for data consistency.
The aggregate root is the entry point — all external access goes through it. Within the
aggregate boundary, invariants are always consistent. Between aggregates, eventual consistency
is acceptable.

Architectural implications:
- Repository ports align 1:1 with aggregate roots, not with individual entities
- Aggregates should be small — if an aggregate touches 10+ entities, reconsider the boundaries
- Cross-aggregate operations happen through domain events or application services, not by
  reaching into another aggregate's internals
- Each aggregate is a natural unit for transaction boundaries

**Domain Events:**
Something that happened in the domain that other parts of the system care about. "OrderPlaced,"
"PaymentReceived," "PolicyExpired." Events are past-tense, immutable facts.

Architectural implications:
- Events are the natural communication mechanism between bounded contexts
- Within a context, events can trigger side effects through application-layer handlers
- Between contexts, events flow through infrastructure (message brokers, event buses)
- Events are the bridge between hexagonal and event-driven architecture
- An event-sourced system stores events as the source of truth rather than current state

**Value Objects:**
Immutable objects defined by their attributes, not identity. Money(100, "USD"), EmailAddress,
DateRange. They carry validation rules and domain logic.

Architectural implication: Value objects are the workhorses of a rich domain. If your domain
layer is mostly entities with getters/setters and all logic lives in services, you're probably
missing value objects. They eliminate primitive obsession and push validation to the point of
construction.

**Domain Services:**
Operations that don't naturally belong to any single entity or value object. Pricing calculations
that span multiple entities, transfer operations between accounts, matching algorithms.

Architectural implication: Domain services live in the domain layer (not application layer).
They operate on domain types and express business rules. Application services (use cases)
*orchestrate* — they call domain services, repositories, and entities to fulfill a use case.
The distinction matters: if business logic migrates into application services, the domain
becomes anemic.

### Strategic Classification

DDD distinguishes three types of domains. This classification directly drives architecture
investment decisions:

**Core Domain:** Where competitive advantage lives. This is the business logic that
differentiates you. It deserves the most sophisticated modeling, the richest domain layer,
the most careful architectural treatment. Full hex, thorough testing, careful aggregate
design. This is where architecture investment pays off most.

**Supporting Domain:** Necessary for the core to function but not a differentiator. Custom
but not complex. Deserves clean design but doesn't need the full ceremony. Simpler patterns
(clean services with DI, vertical slices) are often appropriate. Don't over-invest.

**Generic Domain:** Commodity functionality that every business needs. Authentication, email,
file storage, payment processing. Buy or use established libraries. Don't build custom
architecture around generic concerns — integrate them as infrastructure adapters.

When evaluating architecture, always ask: "Is this core, supporting, or generic?" The answer
determines how much design investment is warranted.

## Mapping Patterns to Forces

Each architectural pattern optimizes for specific forces. The right choice depends on which
forces dominate in your bounded context.

### Force: Integration Complexity
*"The system connects to many external systems and needs to swap or test them independently."*

**Best fit: Hexagonal Architecture (Ports & Adapters)**

Hex shines when the system has multiple integration points and the domain logic needs
protection from infrastructure churn. The port/adapter model makes external dependencies
explicit and swappable. If you're building a service that talks to 3+ external systems,
hex is almost certainly the right starting point.

Hand off to the **hexagonal-architecture** skill for implementation.

### Force: Domain Complexity
*"The business rules are intricate, with many invariants, state transitions, and edge cases."*

**Best fit: Hex or Onion Architecture with rich domain modeling**

When domain complexity dominates, the architecture needs to protect and highlight the domain
layer. Onion architecture adds an explicit Domain Services ring between entities and application
services, which can help when cross-entity business logic is substantial. In practice, hex and
onion implementations often converge — the important thing is a pure, rich domain layer with
real business logic in entities and value objects, not in services.

### Force: Feature Independence
*"The system is a collection of features that change independently and rarely share logic."*

**Best fit: Vertical Slice Architecture**

When features are independent and the team wants to minimize cross-cutting changes, vertical
slices keep related code together. Each feature owns its full stack — handler, validation,
persistence, response mapping. There's high coupling within a slice and low coupling between
slices. Each slice can decide its own internal approach (some might have rich domain logic,
others might be simple transaction scripts).

Key signals: adding a feature doesn't require changing shared abstractions; most changes
touch one feature at a time; the team is organized by feature rather than by layer.

### Force: Read/Write Divergence
*"Reads and writes have fundamentally different shapes, performance needs, or scaling requirements."*

**Best fit: CQRS (as complement to any of the above)**

CQRS is not a standalone architecture — it's a split that can be applied within any pattern.
The write path uses the full domain model (entities, aggregates, invariants). The read path
bypasses the domain and returns DTOs optimized for the consumer. This avoids forcing read
operations through domain object construction that adds no value.

Apply when: read models differ significantly from write models, the system is read-heavy,
or reads need different performance characteristics. Don't apply when reads and writes
operate on the same shapes — the unified model is simpler.

### Force: Decoupling Through Time
*"Components need to react to things that happen without direct coupling to the producer."*

**Best fit: Event-Driven Architecture**

When the system is fundamentally reactive — things happen, and other parts of the system
need to respond — events are the natural organizing principle. Producers publish events
without knowing who consumes them. This provides the strongest form of decoupling but
introduces eventual consistency and operational complexity (event ordering, idempotency,
dead letters).

Events work at two scales:
- Within a bounded context: domain events trigger side effects (send confirmation email
  after order placed). These can be synchronous or async.
- Between bounded contexts: integration events are the communication mechanism. These
  should always be async and must be designed for eventual consistency.

### Force: Team/Module Independence
*"Multiple teams or modules need to evolve independently without stepping on each other."*

**Best fit: Modular Monolith**

A modular monolith defines bounded contexts as independent modules with explicit public APIs
between them, deployed as a single unit. Each module owns its data and exposes only what
other modules need. Internally, each module picks its own architecture. The discipline is
at the module boundary: no reaching into another module's internals, no shared database
tables, no implicit coupling.

This is often the right starting architecture before microservices. It forces you to get
the boundaries right while avoiding distributed systems complexity. If a module later needs
independent deployment, it can be extracted into a service because the boundary is already clean.

## Patterns Compose

Real systems use multiple patterns together. Common compositions:

- **Modular monolith + hex per module:** Module boundaries enforce context isolation,
  hex within each module protects domain logic from infrastructure. This is a strong
  default for systems with multiple rich domains.

- **Hex + CQRS:** Write path through full hex stack, read path through dedicated query
  ports that bypass domain construction. Good when the system has rich write logic
  but read patterns diverge. The **hexagonal-architecture** skill includes a concrete
  structural guide for this split (see its "Read Path Optimization" section).

- **Vertical slices + hex for complex slices:** Most features are simple slices with
  minimal ceremony. The few features with complex domain logic use hex internally.
  Avoids over-investing in architecture for simple features.

- **Hex + event-driven between contexts:** Each bounded context is structured with hex
  internally. Contexts communicate through domain events published via outbound ports
  and consumed by driving adapters in other contexts.

- **CQRS + event sourcing:** Events are the write model (source of truth). Read models
  are projections built from the event stream. This is the most complex composition
  and should only be used when the business genuinely needs full audit history and
  temporal queries.

## Decision Framework

When helping the user choose an architecture, work through these questions:

1. **What are the bounded contexts?** Help identify the distinct models in the system.
   Don't assume one architecture for everything.

2. **For each context, what's the strategic classification?** Core, supporting, or generic?
   This sets the investment level.

3. **What forces dominate in each context?** Integration complexity, domain complexity,
   feature independence, read/write divergence, reactive patterns, team independence?

4. **Match forces to patterns.** Use the mappings above. Multiple forces present → patterns compose.

5. **Start simple, evolve.** If unsure, start with the simplest approach that respects the
   dependency rule (domain doesn't depend on infrastructure). Add architectural ceremony
   only when the forces demand it. You can always refactor toward hex or CQRS later when
   the pain points become concrete.

If the analysis points toward hexagonal architecture, hand off to the **hexagonal-architecture**
skill for implementation guidance. This skill provides the *why*; that skill provides the *how*.
