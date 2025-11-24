# NTHP Protocol

NTHP Protocol is a decentralized governance and utility protocol based on the NTHP token. The protocol is designed to support a community-driven ecosystem with staking, vesting, and privacy-preserving features.

## Features:
- **Decentralized Governance** with DAO
- **Staking** and **Vesting** for long-term token holders
- **Privacy-Preserving Mixer** for token transfers
- **Timelock** to ensure transparent and secure contract interactions

## Token Info:
- **Token Name**: NthPower
- **Symbol**: NTHP
- **Total Supply**: 66,660,000 NTHP
- **Decimals**: 18

## Token Logo:
![Logo](https://github.com/gm891273/nthp-protocol-mainnet/raw/main/clearing.png)

## How to Participate:
1. Stake your NTHP to earn rewards.
2. Participate in governance by voting on proposals.
3. Use the privacy mixer to anonymize transfers.

## License:
MIT License


## Governance

NTHP Protocol is governed entirely on-chain through a standard
**ERC20Votes + Governor + Timelock** architecture.  
After deployment, all privileged roles were handed over to the governance
system, and no externally owned account (EOA) retains upgrade or
admin control over core contracts.

### Governance Architecture

The main components are:

- **NTHP Token (ERC20Votes)**  
  - ERC-20 compatible governance token with voting power based on
    delegated balances.
  - Voting power follows the standard ERC20Votes checkpoint mechanism.

- **NTHP Governor**  
  - Implements the full governance flow (proposal → voting → queue → execute).
  - Controls the Timelock as the sole proposer and canceller.

- **TimelockController**  
  - Holds ownership of all core protocol contracts.  
  - Enforces a minimum delay between proposal approval and execution.  
  - Only accepts calls that originate from the Governor.

- **Auxiliary Modules**  
  - StakingVault, VestingVault, ParamStore, TreasuryExecutor, KeeperRouter,
    LightMixer and other modules are owned by the Timelock and therefore
    indirectly controlled by governance.

The full list of contract addresses and deployment parameters is provided in
the `deployment/mainnet` documentation (or equivalent JSON/markdown file).

---

### Voting Parameters

The Governor is configured with the following core parameters:

| Parameter           | Description                                                |
|---------------------|------------------------------------------------------------|
| `votingDelay`       | Number of blocks between proposal creation and voting start. |
| `votingPeriod`      | Number of blocks during which votes can be cast.          |
| `proposalThreshold` | Minimum voting power required to create a proposal.       |
| `quorumPercent`     | Percentage of total voting power required for quorum.     |

These values are chosen to balance responsiveness with safety and to give
token holders sufficient time to review and vote on proposals.

Voting power is determined as follows:

- Token holders may **self-delegate** or delegate to another address.
- A user’s voting power at a given block is the delegated NTHP balance
  at or before that block (using ERC20Votes checkpoints).
- Only voting power at the proposal’s snapshot block is considered.

---

### Timelock Configuration

All governance actions are executed via the TimelockController:

- **Ownership:**  
  Ownership of core protocol contracts is transferred to the Timelock.  
  No EOA retains `owner` privileges on these contracts.

- **Roles:**  
  - `PROPOSER_ROLE`: Governor  
  - `CANCELLER_ROLE`: Governor  
  - `EXECUTOR_ROLE`: `address(0)` (open execution, subject to timelock rules)

- **Minimum Delay (`minDelay`):**  
  A non-zero delay is enforced between queuing and executing any operation.
  This gives token holders and external observers time to react to
  potentially harmful proposals before they are executed.

As a result, **all privileged actions** (e.g. parameter changes, treasury
operations, module configuration) must pass through:

> Governor proposal → token holder vote → Timelock delay → execution.

---

### Proposal Lifecycle

The on-chain lifecycle of a governance proposal is:

1. **Creation (`propose`)**  
   - A proposer with voting power >= `proposalThreshold` submits:
     - `targets[]` (contracts to call)  
     - `values[]` (native token values, usually zero)  
     - `calldatas[]` (encoded function calls)  
     - `description` (human-readable text)  

2. **Pending → Active**  
   - After `votingDelay` blocks, the proposal becomes **Active** and voting opens.

3. **Voting (`castVote` / `castVoteWithReason`)**  
   - Token holders vote **For**, **Against**, or **Abstain**.  
   - Voting is open for `votingPeriod` blocks.  
   - The proposal **succeeds** if:
     - Quorum is reached (enough total votes), and  
     - `forVotes > againstVotes`.

4. **Queued (`queue`)**  
   - Successful proposals are queued in the Timelock with the same
     `targets`, `values`, `calldatas` and `descriptionHash`.  
   - The Timelock schedules an operation ID and timestamp.

5. **Executable → Executed (`execute`)**  
   - After `minDelay` has elapsed, the Governor can execute the proposal.  
   - The Timelock performs the queued calls against the target contracts.  
   - Once executed, the proposal is permanently marked as **Executed**.

The full state machine typically includes:
`Pending → Active → Succeeded/Defeated → Queued → Executed`
(with optional `Canceled` / `Expired` states).

---

### Security and Decentralization Guarantees

- **No admin backdoors**  
  Core contracts are owned by the Timelock, not by any EOA. Changes to
  protocol behavior can only occur through governance proposals.

- **Transparent and auditable**  
  - All proposals, votes, queues and executions are recorded on-chain
    and can be inspected via block explorers.  
  - Contract source code is verified and publicly available.

- **Censorship-resistant execution**  
  With `EXECUTOR_ROLE` set to `address(0)`, any address may execute a
  ready proposal once the timelock delay has passed, preventing a
  single party from blocking execution.

---

### Proposal Registry

For ease of auditing and external integrations, the project maintains a
human-readable registry of key proposals (e.g. parameter changes, treasury
actions, module upgrades).  

Each entry should contain:

- Proposal ID  
- Description (exact text used on-chain)  
- `targets[]`, `values[]`, `calldatas[]`, `descriptionHash`  
- Transaction hashes for `propose`, `queue`, and `execute`  
- Final state (`Executed`, `Defeated`, `Canceled`, etc.)  
- A short explanation of the proposal’s intent and effect

This registry can be kept as a markdown or JSON file in the repository
(e.g. `governance/proposals-mainnet.md`), and updated as new proposals
are executed on mainnet.


## Contracts (Sei EVM Mainnet)

The following contracts are deployed on the Sei EVM mainnet:

- **NTHP Token (ERC20Votes)**  
  Main governance token of the protocol.  
  - Contract: `0x1430eB4D5865eC9a8b1D6f58BF7657d78CeCf458`

- **StakingVault**  
  Staking vault for NTHP, used to distribute rewards to long-term holders.  
  - Contract: `0xA265AcDE0631Cb5EC017d540477e6863D9C9Eb40`

- **VestingVault**  
  Linear vesting vault for long-term allocations.  
  - Contract: `0x8c2dD943047Dba99D52de3aFF7D566D028aEaA52`

- **TimelockController**  
  Owns all core contracts and enforces a minimum delay on privileged actions.  
  - Contract: `0x380fBfF5e2bf53cf2F747463e3081222B1958E88B`

- **NTHPGovernor**  
  On-chain governance contract controlling the Timelock.  
  - Contract: `0x3457444B3729cF7389AE297Cb242a6F247D5bDe8`

Additional modules (e.g. ParamStore, TreasuryExecutor, KeeperRouter, LightMixer)
are also deployed and owned by the Timelock; they can be added here as the
deployment documentation is finalized.
