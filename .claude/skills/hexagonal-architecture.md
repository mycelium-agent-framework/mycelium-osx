---
name: hexagonal-architecture
description: >
  Apply Hexagonal Architecture (Ports and Adapters) when building systems, services, or applications.
  Trigger when the user mentions "hex", "hexagonal", "ports and adapters", "clean architecture",
  "onion architecture", or wants separation between business logic and infrastructure. Also trigger
  for refactoring toward better separation of concerns or structuring projects for testability.
  Applies to any language or framework. This skill is downstream of effective-design-overview.
  If uncertain whether hex fits — thin domain logic, mostly CRUD, highly independent features,
  or broad "what architecture" questions — consult effective-design-overview first for strategic
  guidance. If it confirms hex, return here for implementation.
---

# Hexagonal Architecture (Ports & Adapters)

This skill guides building systems using Hexagonal Architecture. The core idea: business logic lives
at the center, completely isolated from infrastructure. The outside world connects through explicitly
defined interfaces (Ports) and their concrete implementations (Adapters).

> **Upstream skill:** The **effective-design-overview** skill provides the strategic context for
> *when and why* to use hex. If the architecture fitness check (below) raises concerns, or if
> you're unsure hex is the right fit, consult that skill for broader design guidance including
> DDD concepts, bounded context analysis, and alternative pattern selection.

## When to Apply

Apply this architecture when:
- Building a new service, API, or application with meaningful business logic
- The system will have multiple integration points (databases, APIs, queues, etc.)
- Testability and long-term maintainability matter
- The user wants framework-agnostic business logic

Scale appropriately — a 50-line script doesn't need full hexagonal treatment. For small utilities,
mention the pattern but keep it lightweight. For anything with multiple entities, use cases, or
integration points, go full hex.

## Core Principles

### Dependency Rule
Dependencies point inward. Always. The domain layer imports nothing from infrastructure.
Infrastructure depends on the domain — never the reverse. This is the single most important
rule and the one most likely to be violated accidentally.

### The Three Layers

**Domain (innermost):**
- Entities with business rules and invariants
- Value Objects for typed, validated concepts
- Domain Events if the business logic publishes them
- NO framework annotations, NO ORM decorators, NO import of anything outside the domain
- Pure language constructs only — this code should compile/run with zero external dependencies

**Application (middle):**
- Use Cases (also called Application Services or Interactors) that orchestrate domain logic
- Port definitions: interfaces/protocols/traits that declare what the application *needs*
  - Inbound Ports: the operations the application exposes (typically 1:1 with use cases)
  - Outbound Ports: what the application requires from the outside world (persistence, messaging, external APIs)
- DTOs for crossing boundaries (command/query objects in, result objects out)
- This layer depends only on the Domain layer

**Infrastructure (outermost):**
- Adapters that implement Outbound Ports (database repos, API clients, message publishers)
- Driving Adapters that translate external input into calls on Inbound Ports (HTTP controllers, CLI handlers, queue consumers, gRPC services)
- Framework configuration, DI wiring, ORM mappings
- This is the only layer that touches frameworks and external libraries

### Port Design

Ports are the contracts. Get them right and everything else follows.

**Outbound Ports (driven):**
- Define from the domain's perspective: what does the business logic *need*?
- Name them by capability, not technology: `OrderRepository`, not `PostgresOrderStore`
- Keep methods focused: `save(order)`, `find_by_id(id)`, `find_by_customer(customer_id)`
- Return domain types, not infrastructure types (no ORM models, no raw SQL rows)

**Inbound Ports (driving):**
- Define the application's public API
- One port per use case keeps things clean, but grouping related operations is fine for smaller systems
- Accept command/query objects, return result types
- This is where input validation lives (business validation stays in the domain)

## Project Structure

Adapt to the language's conventions, but maintain the conceptual separation. Here are patterns
for common languages:

### Python
```
src/
├── domain/
│   ├── entities/          # Business objects with logic
│   ├── value_objects/     # Typed, immutable values
│   ├── events/            # Domain events (optional)
│   └── exceptions.py      # Domain-specific errors
├── application/
│   ├── ports/
│   │   ├── inbound/       # Use case interfaces (ABCs/Protocols)
│   │   └── outbound/      # Repository/service interfaces
│   ├── use_cases/         # Orchestration logic
│   └── dto/               # Command/query/result objects
├── infrastructure/
│   ├── adapters/
│   │   ├── persistence/   # DB implementations of outbound ports
│   │   ├── http_client/   # External API adapters
│   │   └── messaging/     # Queue/event bus adapters
│   ├── driving/
│   │   ├── api/           # FastAPI/Flask controllers
│   │   ├── cli/           # CLI entry points
│   │   └── consumers/     # Queue consumers
│   └── config/            # DI container, settings
└── tests/
    ├── unit/              # Domain + use case tests (no infra)
    ├── integration/       # Adapter tests against real services
    └── fakes/             # In-memory adapter implementations for testing
```

### TypeScript / Node
```
src/
├── domain/
│   ├── entities/
│   ├── value-objects/
│   ├── events/
│   └── errors.ts
├── application/
│   ├── ports/
│   │   ├── inbound/
│   │   └── outbound/
│   ├── use-cases/
│   └── dto/
├── infrastructure/
│   ├── adapters/
│   │   ├── persistence/
│   │   ├── http-client/
│   │   └── messaging/
│   ├── driving/
│   │   ├── rest/          # Express/Fastify controllers
│   │   ├── graphql/
│   │   └── cli/
│   └── config/            # DI, env config
└── tests/
```

### Go
```
internal/
├── domain/
│   ├── entity/
│   └── valueobject/
├── application/
│   ├── port/              # Interface definitions
│   ├── usecase/
│   └── dto/
├── infrastructure/
│   ├── adapter/
│   │   ├── postgres/
│   │   ├── redis/
│   │   └── httpclient/
│   └── driving/
│       ├── httphandler/
│       └── grpc/
cmd/
├── server/
│   └── main.go            # Wiring
└── worker/
    └── main.go
```

### Java / Kotlin (Spring)
```
src/main/java/com/example/
├── domain/
│   ├── model/             # Entities, Value Objects — NO @Entity annotations
│   ├── event/
│   └── exception/
├── application/
│   ├── port/
│   │   ├── in/            # Use case interfaces
│   │   └── out/           # Persistence/service interfaces
│   ├── service/           # Use case implementations
│   └── dto/
├── infrastructure/
│   ├── adapter/
│   │   ├── persistence/
│   │   │   ├── entity/    # JPA @Entity classes live HERE, not in domain
│   │   │   ├── mapper/    # Domain <-> JPA entity mappers
│   │   │   └── repository/
│   │   └── client/
│   ├── driving/
│   │   └── web/           # @RestController classes
│   └── config/            # @Configuration, @Bean definitions
```

## Build Sequence

When generating code, follow this order. This prevents the common failure mode where
infrastructure concerns leak into domain design.

1. **Domain entities and value objects first.** Get the business rules right with zero dependencies.
2. **Define outbound ports.** What does the domain need from the outside world? Write the interfaces.
3. **Write use cases.** Orchestrate domain logic, depending only on ports.
4. **Define inbound ports** (if distinct from use cases — in many cases the use case *is* the inbound port).
5. **Build adapters.** Implement the outbound ports with real infrastructure.
6. **Build driving adapters.** Controllers, CLI handlers, etc. that call inbound ports.
7. **Wire it up.** DI configuration that assembles the pieces.

If the user asks for "just the API endpoint" or similar partial request, still structure
the code this way — just generate fewer files. A single use case with one port and one
adapter is still hexagonal, just small.

## Testing Strategy

The architecture directly enables a clean testing pyramid:

- **Unit tests** for domain entities and use cases: inject fake/stub implementations of outbound ports.
  These tests are fast, have no external dependencies, and validate business rules.
- **Integration tests** for adapters: test that the PostgresOrderRepository actually talks to Postgres correctly.
  These tests validate the mapping between domain types and infrastructure types.
- **End-to-end tests** (sparingly): test through driving adapters to verify wiring.

Always generate at least stub test files that demonstrate the testing pattern, especially
the use-case-with-fake-adapter pattern. This is one of the architecture's biggest selling points.

## Read Path Optimization (CQRS Shortcut)

One of hex architecture's legitimate pain points is that read operations get forced through the
same domain model as writes — constructing entities, validating invariants, mapping through
ports — when the read path often just needs to return shaped data. This is wasted ceremony.

Borrow from CQRS: separate the command (write) path from the query (read) path.

**When to apply this:**
- The system is read-heavy or has read patterns that differ significantly from the write model
- Read operations return different shapes than the domain entities (dashboards, lists, search results, aggregations)
- Performance matters on the read side and domain object construction is measurable overhead

**How it works within hex:**
- The write path goes through the full hex stack: driving adapter → use case → domain → outbound port → adapter
- The read path gets a dedicated query port in the application layer that returns DTOs directly,
  bypassing domain entity construction entirely
- Query port implementations in infrastructure can use optimized queries, denormalized views,
  or even a separate read store
- The query port interface still lives in the application layer (not infrastructure), preserving
  the dependency rule

**Structure addition:**
```
application/
├── command/              # Write path (use cases that mutate state)
│   ├── dto/
│   ├── ports/            # Outbound ports for write path (repositories, services)
│   └── use_cases/
└── query/                # Read path (bypasses domain)
    ├── dto/              # Read-specific response shapes
    └── ports/            # Query interfaces (return DTOs, not entities)
```

**When NOT to apply this:** If reads and writes operate on the same shapes and there's no
performance concern, skip the split. A unified model is simpler. Introducing CQRS just because
you can adds surface area without payoff. The trigger is divergence between read and write
concerns — if you don't have it, you don't need it.

## Common Mistakes to Avoid

**Leaking annotations into domain:**
Framework annotations (@Entity, @Table, @Column, decorators) do NOT belong on domain objects.
Create separate persistence models in the infrastructure layer and map between them.

**Anemic domain:**
If entities are just data holders and all logic lives in use cases, the domain is anemic.
Push business rules into entities. Use cases should orchestrate, not compute.

**Port explosion:**
Not every method needs its own interface. Group related operations into coherent ports.
A `UserRepository` with save/find/delete is fine — you don't need `SaveUser`, `FindUser`, `DeleteUser` as separate ports unless there's a real reason.

**Skipping the mapping layer:**
It's tempting to pass ORM entities directly through ports. Don't. The mapping between domain
objects and persistence models is the firewall that keeps the architecture honest. The cost
is some boilerplate; the payoff is that your domain never knows about your database.

**Over-engineering small projects:**
A CRUD app with no business logic doesn't benefit from full hexagonal. Recognize when
the pattern adds cost without value, and say so. You can still use the principles
(dependency inversion, port interfaces) without the full folder structure.

## Error Flow Across Layers

Errors should respect the same dependency rule as everything else — inner layers don't know
about outer layers' error types.

**Domain exceptions** express business rule violations: `InsufficientFunds`, `OrderAlreadyClosed`,
`InvalidEmailFormat`. These are defined in the domain layer using plain language types. They
carry business meaning and are part of the ubiquitous language.

**Application exceptions** express use case failures: `OrderNotFound`, `UnauthorizedAccess`,
`DuplicateRequest`. Defined in the application layer. Use cases catch domain exceptions when
they need to translate or enrich them, but often let domain exceptions propagate through.

**Infrastructure exceptions** (database timeouts, HTTP errors, serialization failures) must
NOT leak into the domain or application layers. Adapters catch infrastructure-specific
exceptions and either translate them into domain/application exceptions or wrap them in a
generic infrastructure failure type defined at the port level (e.g., `PersistenceError`).

The driving adapter (controller, CLI handler) is responsible for the final translation —
mapping domain and application exceptions into the appropriate external representation
(HTTP status codes, CLI exit codes, error response bodies). The domain never knows about
HTTP 404.

## Adapting to User Context

- **If the user specifies a framework** (FastAPI, Spring Boot, NestJS, etc.): use it for the
  infrastructure layer, but keep the domain clean. Show how the framework plugs in as an adapter.
- **If the user doesn't specify a language**: ask. The folder structure and idioms vary significantly.
- **If working with an existing codebase**: identify the current architecture, propose incremental
  refactoring toward hex, and start with extracting the domain layer. Don't try to restructure everything at once.
- **If the user asks for a "quick prototype"**: still use the structure but minimize ceremony.
  A single-file domain + port + adapter is valid hexagonal if the dependencies point the right way.

## Architecture Fitness Check

Hex is not always the right tool. Before applying it — and during development if things feel
forced — evaluate these signals. If multiple red flags are present, suggest an alternative.

### Signals that hex is a good fit
- Rich domain logic with business rules, invariants, and state transitions
- Multiple integration points (2+ external systems, databases, message brokers)
- The team needs to swap or test infrastructure independently
- Long-lived system where maintainability and testability compound over time
- Multiple driving adapters (REST + CLI + queue consumer for the same logic)

### Signals that hex is being stretched
- **Mostly CRUD with thin logic:** If most use cases are "receive DTO, validate fields, persist"
  with no real business rules, hex adds layers without adding value. The domain layer becomes
  anemic wrappers. Consider a simpler layered approach or vertical slices.
- **Feature-heavy with low cross-feature coupling:** If the system is a collection of mostly
  independent features that rarely share domain logic, organizing by layer scatters related
  code across the codebase. Vertical Slice Architecture (organizing by feature/capability
  instead of by layer) keeps related code together and reduces the blast radius of changes.
- **Read/write patterns diverge heavily:** If the system has complex write logic but its read
  patterns look nothing like the domain model (dashboards, search, reporting), full hex on
  both paths is painful. Apply CQRS — use hex for the write path and let reads bypass the
  domain (see Read Path Optimization above).
- **Event-driven / reactive core:** If the system is fundamentally about reacting to events
  and orchestrating workflows across services, hex's port/adapter model can feel awkward.
  Event-Driven Architecture with explicit event contracts and handlers may be more natural.
  Hex can still structure individual handlers internally, but shouldn't be the top-level
  organizing principle.
- **Rapid prototyping / MVP:** If the goal is to validate an idea fast and the code might
  be thrown away, the upfront structure of hex slows you down without payoff. Build the
  simplest thing that works. You can always refactor toward hex later once you know which
  parts have real domain complexity.
- **Single integration point, single adapter:** If there's one database, one API surface,
  and no realistic chance of swapping either, the port abstraction buys little. You're
  paying for indirection you won't use. A clean service layer with dependency injection
  gives you most of the testability benefits without the ceremony.

### Finding alternatives

When the fitness check signals hex is being stretched, consult the **effective-design-overview**
skill for pattern comparison, force analysis, and composition guidance. That skill maps
dominant forces (integration complexity, domain complexity, feature independence, read/write
divergence, reactive patterns, team independence) to the patterns that best address them
and covers how patterns combine in real systems.
