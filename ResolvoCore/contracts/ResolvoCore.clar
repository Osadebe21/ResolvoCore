;; ResolvoCore
;; A decentralized system for resolving outcomes through multi-source validation,
;; weighted voting, and automated dispute resolution with economic incentives.
;; This contract enables trustless resolution of real-world events using oracle data,
;; community consensus, and stake-based governance.

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-stake (err u104))
(define-constant err-voting-closed (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-already-voted (err u107))
(define-constant err-invalid-outcome (err u108))
(define-constant err-dispute-period-active (err u109))
(define-constant err-resolution-finalized (err u110))

(define-constant min-stake u1000000) ;; Minimum stake in microSTX
(define-constant dispute-period u144) ;; ~24 hours in blocks
(define-constant voting-period u1008) ;; ~7 days in blocks
(define-constant oracle-weight u40) ;; 40% weight for oracle data
(define-constant community-weight u60) ;; 60% weight for community votes

;; Outcome status enumeration
(define-constant status-pending u0)
(define-constant status-voting u1)
(define-constant status-disputed u2)
(define-constant status-resolved u3)
(define-constant status-finalized u4)

;; data maps and vars

;; Tracks outcome proposals with metadata and resolution data
(define-map outcomes
  { outcome-id: uint }
  {
    creator: principal,
    description: (string-ascii 256),
    status: uint,
    created-at: uint,
    voting-ends-at: uint,
    total-stake: uint,
    oracle-result: (optional bool),
    oracle-confidence: uint,
    community-yes-votes: uint,
    community-no-votes: uint,
    final-result: (optional bool),
    resolution-block: uint
  }
)

;; Tracks individual votes with stake amounts
(define-map votes
  { outcome-id: uint, voter: principal }
  {
    vote: bool,
    stake-amount: uint,
    voted-at: uint,
    claimed: bool
  }
)

;; Authorized oracles with reputation scores
(define-map oracles
  { oracle: principal }
  {
    active: bool,
    reputation: uint,
    total-reports: uint,
    accurate-reports: uint
  }
)

;; Dispute records for challenged outcomes
(define-map disputes
  { outcome-id: uint, disputer: principal }
  {
    reason: (string-ascii 256),
    stake: uint,
    disputed-at: uint,
    resolved: bool
  }
)

;; Global state variables
(define-data-var outcome-nonce uint u0)
(define-data-var total-outcomes-resolved uint u0)
(define-data-var protocol-treasury uint u0)

;; private functions

;; Calculate weighted resolution based on oracle and community input
(define-private (calculate-weighted-result (oracle-vote bool) (oracle-conf uint) 
                                           (yes-votes uint) (no-votes uint))
  (let
    (
      (total-community-votes (+ yes-votes no-votes))
      (oracle-score (if oracle-vote 
                       (* oracle-weight oracle-conf)
                       (* oracle-weight (- u100 oracle-conf))))
      (community-score (if (> yes-votes no-votes)
                          (* community-weight (/ (* yes-votes u100) total-community-votes))
                          (* community-weight (/ (* no-votes u100) total-community-votes))))
      (total-score (+ oracle-score community-score))
    )
    (> total-score u5000) ;; Returns true if weighted score > 50%
  )
)

;; Calculate reward distribution based on vote alignment with final result
(define-private (calculate-voter-reward (stake uint) (total-winning-stake uint) 
                                        (total-losing-stake uint))
  (let
    (
      (base-return stake)
      (bonus (/ (* stake total-losing-stake) total-winning-stake))
    )
    (+ base-return bonus)
  )
)

;; Validate outcome status transition
(define-private (is-valid-status-transition (current uint) (new uint))
  (or
    (and (is-eq current status-pending) (is-eq new status-voting))
    (and (is-eq current status-voting) (is-eq new status-disputed))
    (and (is-eq current status-voting) (is-eq new status-resolved))
    (and (is-eq current status-disputed) (is-eq new status-resolved))
    (and (is-eq current status-resolved) (is-eq new status-finalized))
  )
)

;; Update oracle reputation based on accuracy
(define-private (update-oracle-reputation (oracle-addr principal) (was-accurate bool))
  (let
    (
      (oracle-data (unwrap! (map-get? oracles { oracle: oracle-addr }) false))
      (new-total (+ (get total-reports oracle-data) u1))
      (new-accurate (if was-accurate 
                       (+ (get accurate-reports oracle-data) u1)
                       (get accurate-reports oracle-data)))
      (new-reputation (/ (* new-accurate u100) new-total))
    )
    (map-set oracles
      { oracle: oracle-addr }
      (merge oracle-data {
        total-reports: new-total,
        accurate-reports: new-accurate,
        reputation: new-reputation
      })
    )
    true
  )
)

;; public functions

;; Register a new oracle (owner only)
(define-public (register-oracle (oracle-addr principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-none (map-get? oracles { oracle: oracle-addr })) err-already-exists)
    (ok (map-set oracles
      { oracle: oracle-addr }
      {
        active: true,
        reputation: u100,
        total-reports: u0,
        accurate-reports: u0
      }
    ))
  )
)

;; Create a new outcome proposal
(define-public (create-outcome (description (string-ascii 256)))
  (let
    (
      (outcome-id (var-get outcome-nonce))
      (current-block block-height)
    )
    (asserts! (is-none (map-get? outcomes { outcome-id: outcome-id })) err-already-exists)
    (map-set outcomes
      { outcome-id: outcome-id }
      {
        creator: tx-sender,
        description: description,
        status: status-pending,
        created-at: current-block,
        voting-ends-at: (+ current-block voting-period),
        total-stake: u0,
        oracle-result: none,
        oracle-confidence: u0,
        community-yes-votes: u0,
        community-no-votes: u0,
        final-result: none,
        resolution-block: u0
      }
    )
    (var-set outcome-nonce (+ outcome-id u1))
    (ok outcome-id)
  )
)

;; Oracle submits outcome data
(define-public (submit-oracle-data (outcome-id uint) (result bool) (confidence uint))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
      (oracle-data (unwrap! (map-get? oracles { oracle: tx-sender }) err-unauthorized))
    )
    (asserts! (get active oracle-data) err-unauthorized)
    (asserts! (is-eq (get status outcome) status-pending) err-invalid-status)
    (asserts! (<= confidence u100) err-invalid-outcome)
    (map-set outcomes
      { outcome-id: outcome-id }
      (merge outcome {
        status: status-voting,
        oracle-result: (some result),
        oracle-confidence: confidence
      })
    )
    (ok true)
  )
)

;; Community member casts vote with stake
(define-public (cast-vote (outcome-id uint) (vote bool) (stake-amount uint))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
      (existing-vote (map-get? votes { outcome-id: outcome-id, voter: tx-sender }))
    )
    (asserts! (is-none existing-vote) err-already-voted)
    (asserts! (is-eq (get status outcome) status-voting) err-voting-closed)
    (asserts! (>= stake-amount min-stake) err-insufficient-stake)
    (asserts! (< block-height (get voting-ends-at outcome)) err-voting-closed)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Record vote
    (map-set votes
      { outcome-id: outcome-id, voter: tx-sender }
      {
        vote: vote,
        stake-amount: stake-amount,
        voted-at: block-height,
        claimed: false
      }
    )
    
    ;; Update outcome vote tallies
    (map-set outcomes
      { outcome-id: outcome-id }
      (merge outcome {
        total-stake: (+ (get total-stake outcome) stake-amount),
        community-yes-votes: (if vote 
                                (+ (get community-yes-votes outcome) stake-amount)
                                (get community-yes-votes outcome)),
        community-no-votes: (if (not vote)
                               (+ (get community-no-votes outcome) stake-amount)
                               (get community-no-votes outcome))
      })
    )
    (ok true)
  )
)

;; Initiate dispute for an outcome
(define-public (dispute-outcome (outcome-id uint) (reason (string-ascii 256)))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
      (dispute-stake (* min-stake u5)) ;; 5x minimum stake required
    )
    (asserts! (is-eq (get status outcome) status-voting) err-invalid-status)
    (asserts! (is-none (map-get? disputes { outcome-id: outcome-id, disputer: tx-sender })) 
              err-already-exists)
    
    ;; Transfer dispute stake
    (try! (stx-transfer? dispute-stake tx-sender (as-contract tx-sender)))
    
    ;; Record dispute
    (map-set disputes
      { outcome-id: outcome-id, disputer: tx-sender }
      {
        reason: reason,
        stake: dispute-stake,
        disputed-at: block-height,
        resolved: false
      }
    )
    
    ;; Update outcome status
    (map-set outcomes
      { outcome-id: outcome-id }
      (merge outcome { status: status-disputed })
    )
    (ok true)
  )
)

;; Resolve outcome using weighted algorithm
(define-public (resolve-outcome (outcome-id uint))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
      (oracle-result (unwrap! (get oracle-result outcome) err-not-found))
      (oracle-conf (get oracle-confidence outcome))
      (yes-votes (get community-yes-votes outcome))
      (no-votes (get community-no-votes outcome))
    )
    (asserts! (or (is-eq (get status outcome) status-voting)
                  (is-eq (get status outcome) status-disputed)) err-invalid-status)
    (asserts! (>= block-height (get voting-ends-at outcome)) err-voting-closed)
    
    ;; Calculate final result using weighted algorithm
    (let
      (
        (final-result (calculate-weighted-result oracle-result oracle-conf yes-votes no-votes))
      )
      (map-set outcomes
        { outcome-id: outcome-id }
        (merge outcome {
          status: status-resolved,
          final-result: (some final-result),
          resolution-block: block-height
        })
      )
      (var-set total-outcomes-resolved (+ (var-get total-outcomes-resolved) u1))
      (ok final-result)
    )
  )
)

;; Claim rewards for correct vote
(define-public (claim-vote-reward (outcome-id uint))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
      (vote-data (unwrap! (map-get? votes { outcome-id: outcome-id, voter: tx-sender }) 
                          err-not-found))
      (final-result (unwrap! (get final-result outcome) err-invalid-status))
    )
    (asserts! (is-eq (get status outcome) status-finalized) err-resolution-finalized)
    (asserts! (not (get claimed vote-data)) err-already-exists)
    (asserts! (is-eq (get vote vote-data) final-result) err-invalid-outcome)
    
    (let
      (
        (winning-stake (if final-result 
                          (get community-yes-votes outcome)
                          (get community-no-votes outcome)))
        (losing-stake (if final-result
                         (get community-no-votes outcome)
                         (get community-yes-votes outcome)))
        (reward (calculate-voter-reward (get stake-amount vote-data) winning-stake losing-stake))
      )
      ;; Mark as claimed
      (map-set votes
        { outcome-id: outcome-id, voter: tx-sender }
        (merge vote-data { claimed: true })
      )
      
      ;; Transfer reward
      (try! (as-contract (stx-transfer? reward tx-sender tx-sender)))
      (ok reward)
    )
  )
)

;; Finalize outcome after dispute period
(define-public (finalize-outcome (outcome-id uint))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
    )
    (asserts! (is-eq (get status outcome) status-resolved) err-invalid-status)
    (asserts! (>= block-height (+ (get resolution-block outcome) dispute-period)) 
              err-dispute-period-active)
    
    (map-set outcomes
      { outcome-id: outcome-id }
      (merge outcome { status: status-finalized })
    )
    (ok true)
  )
)

;; Advanced multi-criteria outcome resolution with adaptive weighting
;; This function implements an intelligent resolution mechanism that dynamically
;; adjusts weights based on oracle reputation, vote participation, and historical accuracy.
;; It provides enhanced security against manipulation and improves resolution accuracy.
(define-public (resolve-outcome-advanced (outcome-id uint) (oracle-addr principal))
  (let
    (
      (outcome (unwrap! (map-get? outcomes { outcome-id: outcome-id }) err-not-found))
      (oracle-data (unwrap! (map-get? oracles { oracle: oracle-addr }) err-unauthorized))
      (oracle-result (unwrap! (get oracle-result outcome) err-not-found))
      (oracle-conf (get oracle-confidence outcome))
      (yes-votes (get community-yes-votes outcome))
      (no-votes (get community-no-votes outcome))
      (total-stake (get total-stake outcome))
      (oracle-rep (get reputation oracle-data))
    )
    (asserts! (or (is-eq (get status outcome) status-voting)
                  (is-eq (get status outcome) status-disputed)) err-invalid-status)
    (asserts! (>= block-height (get voting-ends-at outcome)) err-voting-closed)
    (asserts! (get active oracle-data) err-unauthorized)
    
    ;; Calculate adaptive weights based on oracle reputation and participation
    (let
      (
        ;; Adjust oracle weight based on reputation (50-90% of base weight)
        (adjusted-oracle-weight (+ (/ oracle-weight u2) 
                                   (/ (* oracle-weight oracle-rep) u200)))
        ;; Community weight is inverse of oracle weight
        (adjusted-community-weight (- u100 adjusted-oracle-weight))
        
        ;; Calculate participation rate (affects confidence)
        (participation-rate (if (> total-stake u0)
                              (/ (* total-stake u100) (* min-stake u100))
                              u0))
        
        ;; Confidence multiplier based on participation (0.5x to 1.5x)
        (confidence-multiplier (if (> participation-rate u50)
                                 (+ u100 (/ participation-rate u2))
                                 (+ u50 participation-rate)))
        
        ;; Calculate oracle score with reputation weighting
        (oracle-score (if oracle-result
                         (/ (* adjusted-oracle-weight oracle-conf confidence-multiplier) u10000)
                         (/ (* adjusted-oracle-weight (- u100 oracle-conf) confidence-multiplier) u10000)))
        
        ;; Calculate community consensus strength
        (community-total (+ yes-votes no-votes))
        (community-consensus (if (> community-total u0)
                               (if (> yes-votes no-votes)
                                 (/ (* yes-votes u100) community-total)
                                 (/ (* no-votes u100) community-total))
                               u50))
        
        ;; Calculate community score with adaptive weighting
        (community-score (/ (* adjusted-community-weight community-consensus) u100))
        
        ;; Combined weighted score
        (total-score (+ oracle-score community-score))
        
        ;; Determine final result with threshold
        (final-result (> total-score u50))
        
        ;; Calculate confidence level for the resolution
        (resolution-confidence (if (> total-score u75) u3
                                 (if (> total-score u60) u2 u1)))
      )
      
      ;; Update outcome with advanced resolution data
      (map-set outcomes
        { outcome-id: outcome-id }
        (merge outcome {
          status: status-resolved,
          final-result: (some final-result),
          resolution-block: block-height
        })
      )
      
      ;; Update oracle reputation based on community alignment
      (let
        (
          (community-agrees (is-eq (> yes-votes no-votes) oracle-result))
          (strong-consensus (or (> community-consensus u75) (< community-consensus u25)))
        )
        (if (and strong-consensus community-agrees)
          (update-oracle-reputation oracle-addr true)
          (if (and strong-consensus (not community-agrees))
            (update-oracle-reputation oracle-addr false)
            true))
      )
      
      ;; Increment resolution counter
      (var-set total-outcomes-resolved (+ (var-get total-outcomes-resolved) u1))
      
      ;; Return result with confidence level
      (ok { result: final-result, confidence: resolution-confidence, score: total-score })
    )
  )
)


