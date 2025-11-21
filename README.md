**ResolvoCore**
---------------

A decentralized system for resolving real-world event outcomes through multi-source validation, weighted governance, and economic incentives, built using **Clarity Smart Contracts**.

* * * * *

🛡️ Trustless Resolution Engine Overview
----------------------------------------

This contract implements a decentralized, robust, and economically-incentivized mechanism for determining the outcome of real-world events. It combines data reported by authorized **Oracles** with weighted votes from the **Community** (staked votes) to achieve a high-confidence final result. The **ResolvoCore** system incorporates features like adaptive weights, **oracle reputation scoring**, dispute resolution, and automated reward distribution to ensure accuracy and prevent manipulation.

* * * * *

🛠️ Contract Architecture & Data Structures
-------------------------------------------

The core functionality of the **ResolvoCore** is structured around key data maps and variables:

### 1\. Data Maps

| Map | Description | Key Fields |
| --- | --- | --- |
| `outcomes` | Tracks each outcome proposal, its current status, voting details, and final resolution. | `outcome-id`, `status`, `voting-ends-at`, `oracle-result`, `community-yes-votes`, `final-result` |
| `votes` | Records individual community votes, including the staked amount. | `outcome-id`, `voter`, `vote`, `stake-amount`, `claimed` |
| `oracles` | Stores data for authorized oracles, including their activity status and reputation score. | `oracle`, `active`, `reputation`, `total-reports`, `accurate-reports` |
| `disputes` | Logs any formal challenges against an outcome, including the reason and the disputer's stake. | `outcome-id`, `disputer`, `reason`, `stake`, `resolved` |

### 2\. Global State Variables

| Variable | Description | Type |
| --- | --- | --- |
| `outcome-nonce` | Global counter for generating unique `outcome-id`s. | `uint` |
| `total-outcomes-resolved` | Global count of finalized outcomes. | `uint` |
| `protocol-treasury` | Placeholder for capturing protocol fees (currently unused in reward distribution logic). | `uint` |

* * * * *

⚙️ Core Constants
-----------------

The **ResolvoCore** system's behavior is governed by fixed parameters defining economic incentives, time periods, and weighted influence:

### 1\. Economic and Time Constants

| Constant | Value | Description |
| --- | --- | --- |
| `min-stake` | u1000000 microSTX | The minimum stake required for a community member to cast a vote. |
| `voting-period` | u1008 blocks | The duration for community voting after an oracle submits initial data (approx. 7 days). |
| `dispute-period` | u144 blocks | The duration after an outcome is resolved during which a dispute can be raised (approx. 24 hours). |

### 2\. Weighting Constants

| Constant | Value | Description |
| --- | --- | --- |
| `oracle-weight` | u40 (40%) | The base weighting for oracle input in the final resolution score. |
| `community-weight` | u60 (60%) | The base weighting for community vote consensus in the final resolution score. |

* * * * *

🧠 Private Functions
--------------------

These functions handle core logic, calculations, and internal state validation, and are not callable by external users.

| Function | Purpose | Key Calculation / Logic |
| --- | --- | --- |
| `(calculate-weighted-result ...)` | Determines the final outcome using a **static weighted algorithm** (40% Oracle, 60% Community) based on staked votes and oracle confidence. | Total Score=Oracle Score+Community Score. Result is true if Total Score>5000. |
| `(calculate-voter-reward ...)` | Calculates the final reward (original stake + bonus) for successful voters. | Reward=Stake+Bonus. Bonus is derived from proportionally sharing the losing stakeholders' funds. |
| `(is-valid-status-transition ...)` | Ensures the outcome lifecycle transitions follow the correct, defined path (e.g., `pending` → `voting`, `resolved` → `finalized`). | Boolean validation check for status changes. |
| `(update-oracle-reputation ...)` | Updates an oracle's **reputation score** and accuracy metrics based on their alignment with the final resolution. | Calculates new reputation: Reputation=Total ReportsAccurate Reports×100​. |

* * * * *

🚦 Outcome Status Lifecycle
---------------------------

The lifecycle of an outcome progresses through a defined set of states, managed by the contract:

| Constant | Value | Description |
| --- | --- | --- |
| `status-pending` | u0 | Outcome created, awaiting initial oracle data submission. |
| `status-voting` | u1 | Oracle data submitted, community staking and voting period is active. |
| `status-disputed` | u2 | A formal dispute has been initiated against the outcome's pending resolution. |
| `status-resolved` | u3 | Voting period ended, the final result has been calculated (dispute window open). |
| `status-finalized` | u4 | Dispute window closed, the final result is locked and rewards can be claimed. |

* * * * *

🚀 Public Functions Reference
-----------------------------

### 1\. Core Functions

| Function | Purpose | Authorization & Status |
| --- | --- | --- |
| `(register-oracle ...)` | Adds a new principal as an authorized oracle. | `contract-owner` only. |
| `(create-outcome ...)` | Initiates a new outcome proposal. | Any principal. Sets status to `status-pending`. |
| `(submit-oracle-data ...)` | Submits initial oracle data and confidence level. | Must be an **active oracle**. Sets status to `status-voting`. |
| `(cast-vote ...)` | Allows community members to lock STX stake and vote. | Status must be `status-voting`. Stake ≥ `min-stake`. |
| `(dispute-outcome ...)` | Initiates a formal challenge against the outcome. | Status must be `status-voting`. Requires 5x `min-stake`. |
| `(finalize-outcome ...)` | Locks the final result and allows reward claiming. | Status must be `status-resolved`, and `dispute-period` must have expired. |
| `(claim-vote-reward ...)` | Allows correct voters to withdraw their principal stake plus the reward bonus. | Status must be `status-finalized`. Voter must have voted for the correct result. |

### 2\. Resolution Functions

The **ResolvoCore** contract offers two methods for resolving outcomes:

| Function | Description | Key Feature |
| --- | --- | --- |
| `(resolve-outcome ...)` | Calculates the final outcome using the **static weighted algorithm** (40/60 split). | Simple, based on fixed constants. |
| `(resolve-outcome-advanced ...)` | Calculates the outcome using an **adaptive algorithm** that dynamically adjusts weights based on **Oracle Reputation** and **Community Participation** rate. | Enhanced security and resilience. Updates the oracle's reputation based on consensus alignment. |

* * * * *

🔒 Error Codes
--------------

The contract uses the following error codes for explicit failure states:

| Error Code | Constant | Description |
| --- | --- | --- |
| `u100` | `err-owner-only` | Transaction sender is not the contract owner. |
| `u104` | `err-insufficient-stake` | Vote stake amount is less than `min-stake`. |
| `u105` | `err-voting-closed` | Voting period has expired or is not active. |
| `u106` | `err-unauthorized` | Sender is not an authorized principal (e.g., non-oracle submitting data). |
| `u107` | `err-already-voted` | Community member has already cast a vote. |
| `u109` | `err-dispute-period-active` | The mandatory dispute window is still open. |
| `u110` | `err-resolution-finalized` | The outcome is already finalized and locked. |
| *Other codes* | `u101`, `u102`, `u103`, `u108` | *Not found*, *already exists*, *invalid status*, *invalid outcome*. |

* * * * *

📜 MIT License
--------------

```
MIT License

Copyright (c) 2025 ResolvoCore

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,

OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

* * * * *

🤝 Contribution Guidelines
--------------------------

We welcome contributions to the **ResolvoCore** Engine. Please adhere to the following guidelines:

-   **Clarity Language:** All contributions must be written in **Clarity**.

-   **Testing:** All new features or bug fixes must include comprehensive unit tests.

-   **Style:** Follow standard Clarity conventions, including the use of meaningful variable names and detailed inline comments.

-   **Security:** Prioritize security and gas efficiency. Ensure all possible failure modes are handled via `asserts!` and appropriate error codes.

-   **Pull Requests:** Submit all changes as Pull Requests (PRs) targeting the `main` branch with a clear description of the change.

**Focus Areas for Development:**

-   Implementation of the stake redistribution logic following a **dispute resolution**.

-   Code to correctly collect and manage fees in the `protocol-treasury`.

* * * * *

🔗 Related Resources
--------------------

-   [Stacks Documentation](https://docs.stacks.co/)

-   [Clarity Book](https://book.clarity-lang.org/)

-   [Staking Pools and Economic Design in Prediction Markets](https://www.google.com/search?q=https://research.stx.com/latest)

* * * * *

👤 Contact
----------

For security-related inquiries or critical bugs, please contact the contract owner directly. For general questions and feature discussions, please use the project's public discussion channels.
