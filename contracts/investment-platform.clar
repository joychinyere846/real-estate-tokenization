;; title: investment-platform
;; version: 1.0.0
;; summary: Real Estate Investment Platform and Pool Management Contract
;; description: Manages investment pools, dividend distribution, and governance for real estate assets

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u300))
(define-constant ERR-NOT-AUTHORIZED (err u301))
(define-constant ERR-INVALID-POOL (err u302))
(define-constant ERR-INSUFFICIENT-FUNDS (err u303))
(define-constant ERR-POOL-EXISTS (err u304))
(define-constant ERR-INVALID-AMOUNT (err u305))
(define-constant ERR-NOT-VERIFIED-INVESTOR (err u306))
(define-constant ERR-POOL-CLOSED (err u307))
(define-constant ERR-INVALID-PROPOSAL (err u308))
(define-constant ERR-VOTING-CLOSED (err u309))
(define-constant ERR-ALREADY-VOTED (err u310))
(define-constant ERR-NO-TOKENS (err u311))
(define-constant ERR-DISTRIBUTION-FAILED (err u312))
(define-constant ERR-INVALID-TARGET (err u313))

;; Pool status constants
(define-constant POOL-STATUS-ACTIVE u1)
(define-constant POOL-STATUS-CLOSED u2)
(define-constant POOL-STATUS-PAUSED u3)
(define-constant POOL-STATUS-LIQUIDATING u4)

;; Proposal type constants
(define-constant PROPOSAL-TYPE-INVESTMENT u1)
(define-constant PROPOSAL-TYPE-DIVESTMENT u2)
(define-constant PROPOSAL-TYPE-MAINTENANCE u3)
(define-constant PROPOSAL-TYPE-MANAGEMENT u4)
(define-constant PROPOSAL-TYPE-GOVERNANCE u5)

;; Voting constants
(define-constant VOTING-PERIOD u4320) ;; ~30 days in blocks
(define-constant QUORUM-PERCENTAGE u5000) ;; 50% in basis points
(define-constant APPROVAL-THRESHOLD u6000) ;; 60% in basis points

;; Fee constants (in basis points)
(define-constant PLATFORM-FEE u250) ;; 2.5%
(define-constant MANAGEMENT-FEE u100) ;; 1%
(define-constant PERFORMANCE-FEE u2000) ;; 20%

;; data vars
(define-data-var next-pool-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var total-pools uint u0)
(define-data-var total-invested uint u0)
(define-data-var platform-fee-rate uint PLATFORM-FEE)
(define-data-var fee-collector principal CONTRACT-OWNER)

;; data maps
;; Investment pool information
(define-map investment-pools
  { pool-id: uint }
  {
    property-id: uint,
    pool-manager: principal,
    target-amount: uint,
    current-amount: uint,
    token-count: uint,
    status: uint,
    created-at: uint,
    closed-at: (optional uint),
    fee-rate: uint,
    dividend-balance: uint
  }
)

;; Investor positions in pools
(define-map pool-investments
  { pool-id: uint, investor: principal }
  {
    amount-invested: uint,
    tokens-owned: uint,
    dividends-claimed: uint,
    investment-date: uint,
    last-dividend-claim: uint
  }
)

;; List of investors in each pool
(define-map pool-investors
  { pool-id: uint, investor-index: uint }
  { investor: principal }
)

;; Track number of investors per pool
(define-map pool-investor-count
  { pool-id: uint }
  { count: uint }
)

;; Dividend distribution records
(define-map dividend-distributions
  { pool-id: uint, distribution-id: uint }
  {
    total-amount: uint,
    amount-per-token: uint,
    distributed-at: uint,
    distributed-by: principal,
    total-recipients: uint
  }
)

;; Governance proposals
(define-map governance-proposals
  { proposal-id: uint }
  {
    pool-id: uint,
    proposal-type: uint,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    created-at: uint,
    voting-ends-at: uint,
    votes-for: uint,
    votes-against: uint,
    votes-abstain: uint,
    total-voting-power: uint,
    executed: bool,
    cancelled: bool
  }
)

;; Individual votes on proposals
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  {
    vote: uint, ;; 1=for, 2=against, 3=abstain
    voting-power: uint,
    voted-at: uint
  }
)

;; Pool performance tracking
(define-map pool-performance
  { pool-id: uint, period: uint }
  {
    total-dividends: uint,
    total-fees: uint,
    net-return: uint,
    investor-count: uint,
    period-start: uint,
    period-end: uint
  }
)

;; Fee collection tracking
(define-map fee-collections
  { pool-id: uint, fee-type: uint, period: uint }
  {
    amount-collected: uint,
    collected-at: uint,
    collected-by: principal
  }
)

;; public functions

;; Create a new investment pool for a property
(define-public (create-investment-pool (property-id uint) (target-amount uint) (fee-rate uint))
  (let (
    (pool-id (var-get next-pool-id))
  )
    (asserts! (> target-amount u0) ERR-INVALID-TARGET)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= fee-rate u1000) ERR-INVALID-AMOUNT) ;; Max 10% fee
    
    ;; Create the pool
    (map-set investment-pools
      { pool-id: pool-id }
      {
        property-id: property-id,
        pool-manager: tx-sender,
        target-amount: target-amount,
        current-amount: u0,
        token-count: u0,
        status: POOL-STATUS-ACTIVE,
        created-at: block-height,
        closed-at: none,
        fee-rate: fee-rate,
        dividend-balance: u0
      }
    )
    
    ;; Initialize investor count
    (map-set pool-investor-count
      { pool-id: pool-id }
      { count: u0 }
    )
    
    ;; Update counters
    (var-set next-pool-id (+ pool-id u1))
    (var-set total-pools (+ (var-get total-pools) u1))
    
    (ok pool-id)
  )
)

;; Invest in a property pool
(define-public (invest-in-pool (pool-id uint) (amount uint))
  (let (
    (pool-data (unwrap! (map-get? investment-pools { pool-id: pool-id }) ERR-INVALID-POOL))
    (current-investment (default-to 
      { amount-invested: u0, tokens-owned: u0, dividends-claimed: u0, 
        investment-date: u0, last-dividend-claim: u0 }
      (map-get? pool-investments { pool-id: pool-id, investor: tx-sender })))
    (investor-count-data (unwrap! (map-get? pool-investor-count { pool-id: pool-id }) ERR-INVALID-POOL))
    (is-new-investor (is-eq (get amount-invested current-investment) u0))
    (new-current-amount (+ (get current-amount pool-data) amount))
    (tokens-to-issue (calculate-tokens-for-investment pool-id amount))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get status pool-data) POOL-STATUS-ACTIVE) ERR-POOL-CLOSED)
    (asserts! (<= new-current-amount (get target-amount pool-data)) ERR-INSUFFICIENT-FUNDS)
    (asserts! (is-verified-investor tx-sender) ERR-NOT-VERIFIED-INVESTOR)
    
    ;; Update pool data
    (map-set investment-pools
      { pool-id: pool-id }
      (merge pool-data {
        current-amount: new-current-amount,
        token-count: (+ (get token-count pool-data) tokens-to-issue)
      })
    )
    
    ;; Update investor position
    (map-set pool-investments
      { pool-id: pool-id, investor: tx-sender }
      {
        amount-invested: (+ (get amount-invested current-investment) amount),
        tokens-owned: (+ (get tokens-owned current-investment) tokens-to-issue),
        dividends-claimed: (get dividends-claimed current-investment),
        investment-date: (if is-new-investor block-height (get investment-date current-investment)),
        last-dividend-claim: (get last-dividend-claim current-investment)
      }
    )
    
    ;; Add to investor list if new investor
    (if is-new-investor
      (begin
        (map-set pool-investors
          { pool-id: pool-id, investor-index: (get count investor-count-data) }
          { investor: tx-sender }
        )
        (map-set pool-investor-count
          { pool-id: pool-id }
          { count: (+ (get count investor-count-data) u1) }
        )
      )
      true
    )
    
    ;; Update global stats
    (var-set total-invested (+ (var-get total-invested) amount))
    
    (ok tokens-to-issue)
  )
)

;; Distribute dividends to pool investors
(define-public (distribute-dividends (pool-id uint) (total-amount uint))
  (let (
    (pool-data (unwrap! (map-get? investment-pools { pool-id: pool-id }) ERR-INVALID-POOL))
    (distribution-id (+ pool-id block-height))
    (total-tokens (get token-count pool-data))
    (amount-per-token (if (> total-tokens u0) (/ total-amount total-tokens) u0))
    (investor-count-data (unwrap! (map-get? pool-investor-count { pool-id: pool-id }) ERR-INVALID-POOL))
  )
    (asserts! (is-eq tx-sender (get pool-manager pool-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> total-tokens u0) ERR-NO-TOKENS)
    
    ;; Record the distribution
    (map-set dividend-distributions
      { pool-id: pool-id, distribution-id: distribution-id }
      {
        total-amount: total-amount,
        amount-per-token: amount-per-token,
        distributed-at: block-height,
        distributed-by: tx-sender,
        total-recipients: (get count investor-count-data)
      }
    )
    
    ;; Update pool dividend balance
    (map-set investment-pools
      { pool-id: pool-id }
      (merge pool-data {
        dividend-balance: (+ (get dividend-balance pool-data) total-amount)
      })
    )
    
    (ok distribution-id)
  )
)

;; Claim dividends for an investor
(define-public (claim-dividends (pool-id uint) (distribution-id uint))
  (let (
    (investment-data (unwrap! (map-get? pool-investments { pool-id: pool-id, investor: tx-sender }) ERR-INVALID-POOL))
    (distribution-data (unwrap! (map-get? dividend-distributions { pool-id: pool-id, distribution-id: distribution-id }) ERR-INVALID-POOL))
    (dividend-amount (* (get tokens-owned investment-data) (get amount-per-token distribution-data)))
  )
    (asserts! (> dividend-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> (get tokens-owned investment-data) u0) ERR-NO-TOKENS)
    
    ;; Update investor's dividend claim record
    (map-set pool-investments
      { pool-id: pool-id, investor: tx-sender }
      (merge investment-data {
        dividends-claimed: (+ (get dividends-claimed investment-data) dividend-amount),
        last-dividend-claim: block-height
      })
    )
    
    (ok dividend-amount)
  )
)

;; Create a governance proposal
(define-public (create-proposal 
    (pool-id uint) 
    (proposal-type uint) 
    (title (string-ascii 100))
    (description (string-ascii 500)))
  (let (
    (proposal-id (var-get next-proposal-id))
    (pool-data (unwrap! (map-get? investment-pools { pool-id: pool-id }) ERR-INVALID-POOL))
    (investor-data (map-get? pool-investments { pool-id: pool-id, investor: tx-sender }))
    (voting-ends-at (+ block-height VOTING-PERIOD))
  )
    (asserts! (<= proposal-type PROPOSAL-TYPE-GOVERNANCE) ERR-INVALID-PROPOSAL)
    (asserts! (is-some investor-data) ERR-NOT-AUTHORIZED)
    (asserts! (> (get tokens-owned (unwrap-panic investor-data)) u0) ERR-NO-TOKENS)
    
    ;; Create proposal
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        pool-id: pool-id,
        proposal-type: proposal-type,
        title: title,
        description: description,
        proposer: tx-sender,
        created-at: block-height,
        voting-ends-at: voting-ends-at,
        votes-for: u0,
        votes-against: u0,
        votes-abstain: u0,
        total-voting-power: (get token-count pool-data),
        executed: false,
        cancelled: false
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Vote on a governance proposal
(define-public (vote-on-proposal (proposal-id uint) (vote uint))
  (let (
    (proposal-data (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR-INVALID-PROPOSAL))
    (pool-id (get pool-id proposal-data))
    (investor-data (unwrap! (map-get? pool-investments { pool-id: pool-id, investor: tx-sender }) ERR-NOT-AUTHORIZED))
    (voting-power (get tokens-owned investor-data))
    (existing-vote (map-get? proposal-votes { proposal-id: proposal-id, voter: tx-sender }))
  )
    (asserts! (<= vote u3) ERR-INVALID-PROPOSAL) ;; 1=for, 2=against, 3=abstain
    (asserts! (> vote u0) ERR-INVALID-PROPOSAL)
    (asserts! (<= block-height (get voting-ends-at proposal-data)) ERR-VOTING-CLOSED)
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (> voting-power u0) ERR-NO-TOKENS)
    (asserts! (not (get cancelled proposal-data)) ERR-VOTING-CLOSED)
    
    ;; Record the vote
    (map-set proposal-votes
      { proposal-id: proposal-id, voter: tx-sender }
      {
        vote: vote,
        voting-power: voting-power,
        voted-at: block-height
      }
    )
    
    ;; Update proposal vote counts
    (map-set governance-proposals
      { proposal-id: proposal-id }
      (merge proposal-data {
        votes-for: (if (is-eq vote u1) (+ (get votes-for proposal-data) voting-power) (get votes-for proposal-data)),
        votes-against: (if (is-eq vote u2) (+ (get votes-against proposal-data) voting-power) (get votes-against proposal-data)),
        votes-abstain: (if (is-eq vote u3) (+ (get votes-abstain proposal-data) voting-power) (get votes-abstain proposal-data))
      })
    )
    
    (ok voting-power)
  )
)

;; Collect platform and management fees
(define-public (collect-fees (pool-id uint) (fee-type uint))
  (let (
    (pool-data (unwrap! (map-get? investment-pools { pool-id: pool-id }) ERR-INVALID-POOL))
    (fee-amount (calculate-fees pool-id fee-type))
    (period (/ block-height u4320)) ;; Monthly periods
  )
    (asserts! (or (is-eq tx-sender (get pool-manager pool-data)) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (> fee-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Record fee collection
    (map-set fee-collections
      { pool-id: pool-id, fee-type: fee-type, period: period }
      {
        amount-collected: fee-amount,
        collected-at: block-height,
        collected-by: tx-sender
      }
    )
    
    (ok fee-amount)
  )
)

;; read only functions

;; Get pool information
(define-read-only (get-pool-info (pool-id uint))
  (map-get? investment-pools { pool-id: pool-id })
)

;; Get investor's position in a pool
(define-read-only (get-investor-share (pool-id uint) (investor principal))
  (map-get? pool-investments { pool-id: pool-id, investor: investor })
)

;; Get proposal information
(define-read-only (get-proposal-info (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Get vote information
(define-read-only (get-vote-info (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

;; Get dividend distribution info
(define-read-only (get-distribution-info (pool-id uint) (distribution-id uint))
  (map-get? dividend-distributions { pool-id: pool-id, distribution-id: distribution-id })
)

;; Calculate pending dividends for an investor
(define-read-only (get-pending-dividends (pool-id uint) (investor principal) (distribution-id uint))
  (match (map-get? pool-investments { pool-id: pool-id, investor: investor })
    investment-data
    (match (map-get? dividend-distributions { pool-id: pool-id, distribution-id: distribution-id })
      distribution-data
      (some (* (get tokens-owned investment-data) (get amount-per-token distribution-data)))
      none
    )
    none
  )
)

;; Check if proposal meets quorum and approval threshold
(define-read-only (is-proposal-approved (proposal-id uint))
  (match (map-get? governance-proposals { proposal-id: proposal-id })
    proposal-data
    (let (
      (total-votes (+ (get votes-for proposal-data) (+ (get votes-against proposal-data) (get votes-abstain proposal-data))))
      (total-power (get total-voting-power proposal-data))
      (quorum-met (>= (* total-votes u10000) (* total-power QUORUM-PERCENTAGE)))
      (approval-met (>= (* (get votes-for proposal-data) u10000) (* total-votes APPROVAL-THRESHOLD)))
    )
      (and quorum-met approval-met)
    )
    false
  )
)

;; Get pool performance metrics
(define-read-only (get-pool-performance (pool-id uint) (period uint))
  (map-get? pool-performance { pool-id: pool-id, period: period })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-pools: (var-get total-pools),
    total-invested: (var-get total-invested),
    next-pool-id: (var-get next-pool-id),
    next-proposal-id: (var-get next-proposal-id),
    platform-fee-rate: (var-get platform-fee-rate),
    contract-owner: CONTRACT-OWNER
  }
)

;; private functions

;; Calculate tokens to issue for investment amount
(define-private (calculate-tokens-for-investment (pool-id uint) (amount uint))
  ;; Simple 1:1 ratio for now - could be more sophisticated
  amount
)

;; Calculate fees for a pool
(define-private (calculate-fees (pool-id uint) (fee-type uint))
  (match (map-get? investment-pools { pool-id: pool-id })
    pool-data
    (let (
      (current-amount (get current-amount pool-data))
      (dividend-balance (get dividend-balance pool-data))
    )
      (if (is-eq fee-type u1) ;; Platform fee
        (/ (* current-amount (var-get platform-fee-rate)) u10000)
        (if (is-eq fee-type u2) ;; Management fee
          (/ (* current-amount MANAGEMENT-FEE) u10000)
          (if (is-eq fee-type u3) ;; Performance fee
            (/ (* dividend-balance PERFORMANCE-FEE) u10000)
            u0
          )
        )
      )
    )
    u0
  )
)

;; Check if investor is verified (integration point)
(define-private (is-verified-investor (investor principal))
  ;; This would integrate with the investor-verification contract
  ;; For now, returning true for basic functionality
  true
)

;; Calculate voting power based on token ownership
(define-private (get-voting-power (pool-id uint) (investor principal))
  (default-to u0
    (get tokens-owned (map-get? pool-investments { pool-id: pool-id, investor: investor })))
)

;; Validate pool manager permissions
(define-private (is-pool-manager (pool-id uint) (user principal))
  (match (map-get? investment-pools { pool-id: pool-id })
    pool-data
    (is-eq (get pool-manager pool-data) user)
    false
  )
)
