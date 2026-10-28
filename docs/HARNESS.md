# AI harness delivery

Profile: `public-project`. Canonical shared contract:
[91c4353](https://github.com/altcoinist-com/ai-harness/blob/91c43530225418f7f37858ec23f981f4811d0dda/docs/brain-contract.md). The generated source hashes and projection
owner are in [brain-contract.json](brain-contract.json).

## Ownership

AGENTS.md owns local routing; `.claude/rules/RULES.md` is the common behavior
entry point; `context/README.md` routes to existing factual owners. Existing
domain rules, procedures, plugin payloads and safety gates retain their owners.
Generated shared rules are edited only in the contract source and regenerated.
The company work-routing table remains in company-context, not this document.

## Runtime variant

Native AGENTS.md plus explicit direct read of the local rules index; Claude imports AGENTS.md and loads the index natively. No new hook or machine-global installation is added.

Existing router bodies are retained to preserve their safety scope. A router
above the target context budget is an explicit preservation exception for this
structural PR; reducing or moving unique domain constraints requires its own
owner-reviewed classification, not a mechanical rewrite.

## Lifecycle and verification

Follow the existing destination lifecycle and protected boundaries in AGENTS.md
and its current domain references. Preparing this PR grants no merge, deploy,
external-message, credential, live-data, schedule or plugin-install authority.
No product behavior or service code changes in this structural adoption.

Source layout, local references, generated pack hashes and preservation checks
are structural evidence. Fresh start/resume/update, actual skill selection,
platform support, tool/auth access and owner onboarding remain unverified here
until observed through each declared runtime. A file or loader output is not
proof of delivery. Use the existing native generator/checker for that runtime;
never infer that all skill counts must match.

## Jobs and learning

No live schedule or run is verified by this PR. Existing owning-brain skills,
registries, run evidence and improvement workflows remain authoritative. Record
recurring-job inventory and how failures become owned checks in ALT-2840 before
claiming full adoption. Do not create another scheduler or result store here.
