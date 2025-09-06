;; title: asset-tokenization
;; version: 1.0.0
;; summary: Real Estate Asset Tokenization and Fractionalization Contract
;; description: Enables tokenization of real estate assets into fractional ownership tokens

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INVALID-PROPERTY (err u102))
(define-constant ERR-INSUFFICIENT-TOKENS (err u103))
(define-constant ERR-PROPERTY-EXISTS (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-NOT-VERIFIED-INVESTOR (err u106))
(define-constant ERR-TRANSFER-FAILED (err u107))
(define-constant ERR-INVALID-VALUATION (err u108))
(define-constant ERR-ZERO-ADDRESS (err u109))

;; data vars
(define-data-var next-property-id uint u1)
(define-data-var total-properties uint u0)

;; data maps
;; Property registry with comprehensive metadata
(define-map properties
  { property-id: uint }
  {
    owner: principal,
    total-tokens: uint,
    price-per-token: uint,
    tokens-issued: uint,
    created-at: uint,
    status: (string-ascii 20),
    metadata: (string-ascii 256)
  }
)

;; Token balances for each property and holder
(define-map token-balances
  { property-id: uint, holder: principal }
  { balance: uint }
)

;; Token supply tracking per property
(define-map token-supply
  { property-id: uint }
  { total-supply: uint }
)

;; Property valuation history
(define-map valuation-history
  { property-id: uint, timestamp: uint }
  {
    old-price: uint,
    new-price: uint,
    updated-by: principal
  }
)

;; Transfer approvals for token delegation
(define-map transfer-approvals
  { property-id: uint, owner: principal, spender: principal }
  { amount: uint }
)

;; Property metadata updates log
(define-map metadata-updates
  { property-id: uint, update-id: uint }
  {
    old-metadata: (string-ascii 256),
    new-metadata: (string-ascii 256),
    updated-by: principal,
    timestamp: uint
  }
)

;; public functions

;; Register a new real estate property for tokenization
(define-public (register-property (total-tokens uint) (price-per-token uint) (metadata (string-ascii 256)))
  (let (
    (property-id (var-get next-property-id))
    (current-height block-height)
  )
    (asserts! (> total-tokens u0) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-token u0) ERR-INVALID-VALUATION)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    ;; Store property details
    (map-set properties
      { property-id: property-id }
      {
        owner: tx-sender,
        total-tokens: total-tokens,
        price-per-token: price-per-token,
        tokens-issued: u0,
        created-at: current-height,
        status: "active",
        metadata: metadata
      }
    )
    
    ;; Initialize token supply
    (map-set token-supply
      { property-id: property-id }
      { total-supply: u0 }
    )
    
    ;; Update counters
    (var-set next-property-id (+ property-id u1))
    (var-set total-properties (+ (var-get total-properties) u1))
    
    (ok property-id)
  )
)

;; Mint fractional tokens for a property
(define-public (mint-tokens (property-id uint) (recipient principal) (amount uint))
  (let (
    (property-data (unwrap! (map-get? properties { property-id: property-id }) ERR-INVALID-PROPERTY))
    (current-supply-data (unwrap! (map-get? token-supply { property-id: property-id }) ERR-INVALID-PROPERTY))
    (current-balance (default-to u0 (get balance (map-get? token-balances { property-id: property-id, holder: recipient }))))
    (new-supply (+ (get total-supply current-supply-data) amount))
    (new-balance (+ current-balance amount))
    (new-tokens-issued (+ (get tokens-issued property-data) amount))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= new-tokens-issued (get total-tokens property-data)) ERR-INSUFFICIENT-TOKENS)
    (asserts! (not (is-eq recipient (as-contract tx-sender))) ERR-ZERO-ADDRESS)
    
    ;; Check if recipient is verified (placeholder - would integrate with verification contract)
    (asserts! (is-verified-investor recipient) ERR-NOT-VERIFIED-INVESTOR)
    
    ;; Update token balance
    (map-set token-balances
      { property-id: property-id, holder: recipient }
      { balance: new-balance }
    )
    
    ;; Update total supply
    (map-set token-supply
      { property-id: property-id }
      { total-supply: new-supply }
    )
    
    ;; Update property tokens issued
    (map-set properties
      { property-id: property-id }
      (merge property-data { tokens-issued: new-tokens-issued })
    )
    
    (ok amount)
  )
)

;; Transfer tokens between verified investors
(define-public (transfer-tokens (property-id uint) (sender principal) (recipient principal) (amount uint))
  (let (
    (sender-balance (default-to u0 (get balance (map-get? token-balances { property-id: property-id, holder: sender }))))
    (recipient-balance (default-to u0 (get balance (map-get? token-balances { property-id: property-id, holder: recipient }))))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-TOKENS)
    (asserts! (or (is-eq tx-sender sender) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq sender recipient)) ERR-INVALID-PROPERTY)
    
    ;; Verify both parties are verified investors
    (asserts! (is-verified-investor sender) ERR-NOT-VERIFIED-INVESTOR)
    (asserts! (is-verified-investor recipient) ERR-NOT-VERIFIED-INVESTOR)
    
    ;; Update sender balance
    (map-set token-balances
      { property-id: property-id, holder: sender }
      { balance: (- sender-balance amount) }
    )
    
    ;; Update recipient balance
    (map-set token-balances
      { property-id: property-id, holder: recipient }
      { balance: (+ recipient-balance amount) }
    )
    
    (ok amount)
  )
)

;; Update property valuation
(define-public (update-valuation (property-id uint) (new-price-per-token uint))
  (let (
    (property-data (unwrap! (map-get? properties { property-id: property-id }) ERR-INVALID-PROPERTY))
    (old-price (get price-per-token property-data))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-price-per-token u0) ERR-INVALID-VALUATION)
    
    ;; Record valuation history
    (map-set valuation-history
      { property-id: property-id, timestamp: block-height }
      {
        old-price: old-price,
        new-price: new-price-per-token,
        updated-by: tx-sender
      }
    )
    
    ;; Update property price
    (map-set properties
      { property-id: property-id }
      (merge property-data { price-per-token: new-price-per-token })
    )
    
    (ok new-price-per-token)
  )
)

;; Update property metadata
(define-public (update-metadata (property-id uint) (new-metadata (string-ascii 256)))
  (let (
    (property-data (unwrap! (map-get? properties { property-id: property-id }) ERR-INVALID-PROPERTY))
    (old-metadata (get metadata property-data))
    (update-id (+ property-id block-height))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    ;; Record metadata update
    (map-set metadata-updates
      { property-id: property-id, update-id: update-id }
      {
        old-metadata: old-metadata,
        new-metadata: new-metadata,
        updated-by: tx-sender,
        timestamp: block-height
      }
    )
    
    ;; Update property metadata
    (map-set properties
      { property-id: property-id }
      (merge property-data { metadata: new-metadata })
    )
    
    (ok update-id)
  )
)

;; Burn tokens (for property sales or other scenarios)
(define-public (burn-tokens (property-id uint) (holder principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? token-balances { property-id: property-id, holder: holder }))))
    (supply-data (unwrap! (map-get? token-supply { property-id: property-id }) ERR-INVALID-PROPERTY))
    (new-supply (- (get total-supply supply-data) amount))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= current-balance amount) ERR-INSUFFICIENT-TOKENS)
    
    ;; Update holder balance
    (map-set token-balances
      { property-id: property-id, holder: holder }
      { balance: (- current-balance amount) }
    )
    
    ;; Update total supply
    (map-set token-supply
      { property-id: property-id }
      { total-supply: new-supply }
    )
    
    (ok amount)
  )
)

;; read only functions

;; Get property information
(define-read-only (get-property-info (property-id uint))
  (map-get? properties { property-id: property-id })
)

;; Get token balance for a specific holder and property
(define-read-only (get-token-balance (property-id uint) (holder principal))
  (default-to u0 (get balance (map-get? token-balances { property-id: property-id, holder: holder })))
)

;; Get total supply for a property
(define-read-only (get-total-supply (property-id uint))
  (default-to u0 (get total-supply (map-get? token-supply { property-id: property-id })))
)

;; Get property valuation history
(define-read-only (get-valuation-history (property-id uint) (timestamp uint))
  (map-get? valuation-history { property-id: property-id, timestamp: timestamp })
)

;; Get current property market cap
(define-read-only (get-market-cap (property-id uint))
  (match (map-get? properties { property-id: property-id })
    property-data 
    (let (
      (total-tokens (get total-tokens property-data))
      (price-per-token (get price-per-token property-data))
    )
      (some (* total-tokens price-per-token))
    )
    none
  )
)

;; Get metadata update history
(define-read-only (get-metadata-update (property-id uint) (update-id uint))
  (map-get? metadata-updates { property-id: property-id, update-id: update-id })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-properties: (var-get total-properties),
    next-property-id: (var-get next-property-id),
    contract-owner: CONTRACT-OWNER
  }
)

;; private functions

;; Check if an investor is verified (placeholder for integration)
(define-private (is-verified-investor (investor principal))
  ;; This would integrate with the investor-verification contract
  ;; For now, returning true for basic functionality
  true
)

;; Calculate token value based on current price
(define-private (calculate-token-value (property-id uint) (token-amount uint))
  (match (map-get? properties { property-id: property-id })
    property-data
    (let (
      (price-per-token (get price-per-token property-data))
    )
      (some (* token-amount price-per-token))
    )
    none
  )
)

;; Validate property ownership
(define-private (is-property-owner (property-id uint) (user principal))
  (match (map-get? properties { property-id: property-id })
    property-data
    (is-eq (get owner property-data) user)
    false
  )
)
