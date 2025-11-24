# NTHP Protocol – Mainnet Governance Proposals

This document tracks significant governance proposals executed on the
Sei EVM mainnet. For each proposal, we record the on-chain parameters
and a human-readable explanation of its intent and effect.

> Note: This file intentionally does **not** include any private wallet
> addresses. Only contract addresses, proposal IDs, and transaction
> hashes are referenced.

---

## Template

When adding a new proposal, use the following template:

```markdown
## Proposal #X – <Short Title>

- **Network:** Sei EVM mainnet
- **Proposal ID:** `<PROPOSAL_ID>`  (uint256)
- **Status:** `<Executed / Defeated / Canceled / Pending / Queued>`
- **Description (on-chain):**  
  `<EXACT_DESCRIPTION_STRING_USED_ON_CHAIN>`

- **Parameters:**
  - `targets[]`:
    - `<CONTRACT_ADDRESS_1>` – `<WHAT_THIS_CALL_DOES>`
    - ...
  - `values[]`:
    - `0` for pure calls, or the native SEI value if any.
  - `calldatas[]`:
    - ABI-encoded calls (e.g. `transfer(...)`, `setParam(...)`, etc.)
  - `descriptionHash`:
    - `0x...` (keccak256 of the description string)

- **Transactions:**
  - `propose` tx: `<TX_HASH_PROPOSE>`
  - `queue` tx: `<TX_HASH_QUEUE>`
  - `execute` tx: `<TX_HASH_EXECUTE>`

- **Timeline (optional):**
  - `proposalSnapshot`: `<BLOCK_NUMBER>`
  - `proposalDeadline`: `<BLOCK_NUMBER>`
  - `queuedAt` (Timelock timestamp): `<UNIX_TIMESTAMP>`
  - `executedAt` (block timestamp): `<UNIX_TIMESTAMP>`

- **Votes:**
  - `forVotes`: `<VALUE>`
  - `againstVotes`: `<VALUE>`
  - `abstainVotes`: `<VALUE>`

- **Human-readable summary:**
  - What this proposal does.
  - Why it was needed.
  - Any long-term effect on the protocol.
