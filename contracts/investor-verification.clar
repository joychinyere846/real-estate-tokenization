;; title: investor-verification
;; version: 1.0.0
;; summary: Investor Verification and Compliance Management Contract
;; description: Manages KYC/AML verification, accreditation levels, and compliance for real estate investors

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-AUTHORIZED (err u201))
(define-constant ERR-INVESTOR-NOT-FOUND (err u202))
(define-constant ERR-INVALID-STATUS (err u203))
(define-constant ERR-INVALID-LEVEL (err u204))
(define-constant ERR-ALREADY-VERIFIED (err u205))
(define-constant ERR-NOT-VERIFIED (err u206))
(define-constant ERR-EXPIRED-VERIFICATION (err u207))
(define-constant ERR-INVALID-EXPIRY (err u208))
(define-constant ERR-COMPLIANCE-VIOLATION (err u209))
(define-constant ERR-ZERO-ADDRESS (err u210))

;; Verification status constants
(define-constant STATUS-UNVERIFIED u0)
(define-constant STATUS-PENDING u1)
(define-constant STATUS-VERIFIED u2)
(define-constant STATUS-SUSPENDED u3)
(define-constant STATUS-REJECTED u4)

;; Accreditation level constants
(define-constant ACCREDITATION-NONE u0)
(define-constant ACCREDITATION-RETAIL u1)
(define-constant ACCREDITATION-QUALIFIED u2)
(define-constant ACCREDITATION-INSTITUTIONAL u3)
(define-constant ACCREDITATION-SOPHISTICATED u4)

;; Time constants (in blocks)
(define-constant VERIFICATION-VALIDITY-PERIOD u52560) ;; ~1 year in blocks
(define-constant COMPLIANCE-CHECK-PERIOD u2628)       ;; ~1 month in blocks

;; data vars
(define-data-var total-verified-investors uint u0)
(define-data-var verification-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var compliance-manager principal CONTRACT-OWNER)

;; data maps
;; Primary investor verification data
(define-map investor-verification
  { investor: principal }
  {
    kyc-status: uint,
    accreditation-level: uint,
    verified-at: uint,
    expires-at: uint,
    verified-by: principal,
    country-code: (string-ascii 3),
    risk-score: uint
  }
)

;; Detailed investor profile for compliance
(define-map investor-profile
  { investor: principal }
  {
    full-name: (string-ascii 100),
    date-of-birth: (string-ascii 10),
    nationality: (string-ascii 3),
    address-hash: (string-ascii 64),
    phone-hash: (string-ascii 64),
    email-hash: (string-ascii 64),
    id-document-hash: (string-ascii 64)
  }
)

;; Verification history and audit trail
(define-map verification-history
  { investor: principal, record-id: uint }
  {
    action: (string-ascii 20),
    old-status: uint,
    new-status: uint,
    reason: (string-ascii 256),
    performed-by: principal,
    timestamp: uint
  }
)

;; Compliance flags and monitoring
(define-map compliance-flags
  { investor: principal }
  {
    sanctions-check: bool,
    pep-check: bool,
    adverse-media: bool,
    high-risk-jurisdiction: bool,
    last-check: uint,
    flags-count: uint
  }
)

;; Investment limits based on accreditation
(define-map investment-limits
  { investor: principal }
  {
    max-investment: uint,
    current-investment: uint,
    limit-period: uint,
    last-updated: uint
  }
)

;; Authorized compliance officers
(define-map compliance-officers
  { officer: principal }
  {
    authorized: bool,
    permissions: uint,
    assigned-at: uint,
    assigned-by: principal
  }
)

;; Transaction monitoring for suspicious activity
(define-map transaction-monitoring
  { investor: principal, period: uint }
  {
    transaction-count: uint,
    transaction-volume: uint,
    suspicious-activity: bool,
    last-transaction: uint
  }
)

;; Whitelist for pre-approved investors
(define-map investor-whitelist
  { investor: principal }
  {
    whitelisted: bool,
    whitelisted-by: principal,
    whitelisted-at: uint,
    notes: (string-ascii 256)
  }
)

;; public functions

;; Set investor verification status with comprehensive data
(define-public (set-verification-status 
    (investor principal) 
    (kyc-status uint) 
    (accreditation-level uint)
    (country-code (string-ascii 3))
    (risk-score uint)
    (validity-period uint))
  (let (
    (record-id (+ block-height u1))
    (current-verification (map-get? investor-verification { investor: investor }))
    (expires-at (+ block-height validity-period))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= kyc-status u4) ERR-INVALID-STATUS)
    (asserts! (<= accreditation-level u4) ERR-INVALID-LEVEL)
    (asserts! (> validity-period u0) ERR-INVALID-EXPIRY)
    (asserts! (<= risk-score u10) ERR-INVALID-STATUS)
    (asserts! (not (is-eq investor (as-contract tx-sender))) ERR-ZERO-ADDRESS)
    
    ;; Record verification history
    (map-set verification-history
      { investor: investor, record-id: record-id }
      {
        action: "status-update",
        old-status: (default-to u0 (get kyc-status current-verification)),
        new-status: kyc-status,
        reason: "Manual verification update",
        performed-by: tx-sender,
        timestamp: block-height
      }
    )
    
    ;; Set verification data
    (map-set investor-verification
      { investor: investor }
      {
        kyc-status: kyc-status,
        accreditation-level: accreditation-level,
        verified-at: block-height,
        expires-at: expires-at,
        verified-by: tx-sender,
        country-code: country-code,
        risk-score: risk-score
      }
    )
    
    ;; Update investment limits based on accreditation
    (try! (set-investment-limits investor accreditation-level))
    
    ;; Update verified investors count if newly verified
    (if (and (is-eq kyc-status STATUS-VERIFIED) 
             (is-none current-verification))
      (var-set total-verified-investors (+ (var-get total-verified-investors) u1))
      true
    )
    
    (ok record-id)
  )
)

;; Clear investor verification (suspend or revoke)
(define-public (clear-verification (investor principal) (reason (string-ascii 256)))
  (let (
    (current-verification (unwrap! (map-get? investor-verification { investor: investor }) ERR-INVESTOR-NOT-FOUND))
    (record-id (+ block-height u1))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Record the action
    (map-set verification-history
      { investor: investor, record-id: record-id }
      {
        action: "verification-cleared",
        old-status: (get kyc-status current-verification),
        new-status: STATUS-SUSPENDED,
        reason: reason,
        performed-by: tx-sender,
        timestamp: block-height
      }
    )
    
    ;; Update verification status
    (map-set investor-verification
      { investor: investor }
      (merge current-verification {
        kyc-status: STATUS-SUSPENDED,
        verified-by: tx-sender
      })
    )
    
    ;; Clear investment limits
    (map-delete investment-limits { investor: investor })
    
    (ok record-id)
  )
)

;; Update investor profile with PII hashes
(define-public (update-investor-profile
    (investor principal)
    (full-name (string-ascii 100))
    (date-of-birth (string-ascii 10))
    (nationality (string-ascii 3))
    (address-hash (string-ascii 64))
    (phone-hash (string-ascii 64))
    (email-hash (string-ascii 64))
    (id-document-hash (string-ascii 64)))
  (begin
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? investor-verification { investor: investor })) ERR-INVESTOR-NOT-FOUND)
    
    (map-set investor-profile
      { investor: investor }
      {
        full-name: full-name,
        date-of-birth: date-of-birth,
        nationality: nationality,
        address-hash: address-hash,
        phone-hash: phone-hash,
        email-hash: email-hash,
        id-document-hash: id-document-hash
      }
    )
    
    (ok true)
  )
)

;; Set compliance flags based on screening results
(define-public (set-compliance-flags
    (investor principal)
    (sanctions-check bool)
    (pep-check bool)
    (adverse-media bool)
    (high-risk-jurisdiction bool))
  (let (
    (flags-count (+ (if sanctions-check u1 u0)
                   (+ (if pep-check u1 u0)
                     (+ (if adverse-media u1 u0)
                        (if high-risk-jurisdiction u1 u0)))))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set compliance-flags
      { investor: investor }
      {
        sanctions-check: sanctions-check,
        pep-check: pep-check,
        adverse-media: adverse-media,
        high-risk-jurisdiction: high-risk-jurisdiction,
        last-check: block-height,
        flags-count: flags-count
      }
    )
    
    ;; Auto-suspend if high-risk flags are present
    (if (or sanctions-check (or pep-check adverse-media))
      (begin
        (try! (clear-verification investor "Compliance flags detected"))
        true
      )
      true
    )
    
    (ok flags-count)
  )
)

;; Add investor to whitelist for expedited processing
(define-public (whitelist-investor (investor principal) (notes (string-ascii 256)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set investor-whitelist
      { investor: investor }
      {
        whitelisted: true,
        whitelisted-by: tx-sender,
        whitelisted-at: block-height,
        notes: notes
      }
    )
    
    (ok true)
  )
)

;; Authorize compliance officer with specific permissions
(define-public (authorize-compliance-officer (officer principal) (permissions uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (is-eq officer (as-contract tx-sender))) ERR-ZERO-ADDRESS)
    
    (map-set compliance-officers
      { officer: officer }
      {
        authorized: true,
        permissions: permissions,
        assigned-at: block-height,
        assigned-by: tx-sender
      }
    )
    
    (ok true)
  )
)

;; Update investment limits based on accreditation level
(define-public (set-investment-limits (investor principal) (accreditation-level uint))
  (let (
    (max-investment (get-max-investment-by-level accreditation-level))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set investment-limits
      { investor: investor }
      {
        max-investment: max-investment,
        current-investment: u0,
        limit-period: COMPLIANCE-CHECK-PERIOD,
        last-updated: block-height
      }
    )
    
    (ok max-investment)
  )
)

;; read only functions

;; Check if investor is verified and not expired
(define-read-only (is-verified (investor principal))
  (match (map-get? investor-verification { investor: investor })
    verification-data
    (and
      (is-eq (get kyc-status verification-data) STATUS-VERIFIED)
      (< block-height (get expires-at verification-data))
    )
    false
  )
)

;; Get comprehensive verification information
(define-read-only (get-verification-info (investor principal))
  (map-get? investor-verification { investor: investor })
)

;; Get investor's accreditation level
(define-read-only (get-accreditation-level (investor principal))
  (default-to ACCREDITATION-NONE
    (get accreditation-level (map-get? investor-verification { investor: investor })))
)

;; Check if both parties in a transaction are verified
(define-read-only (both-parties-verified (sender principal) (recipient principal))
  (and (is-verified sender) (is-verified recipient))
)

;; Get compliance flags for an investor
(define-read-only (get-compliance-flags (investor principal))
  (map-get? compliance-flags { investor: investor })
)

;; Check if investor has any compliance red flags
(define-read-only (has-compliance-issues (investor principal))
  (match (map-get? compliance-flags { investor: investor })
    flags-data
    (> (get flags-count flags-data) u0)
    false
  )
)

;; Get investment limits for an investor
(define-read-only (get-investment-limits (investor principal))
  (map-get? investment-limits { investor: investor })
)

;; Check if investment amount is within limits
(define-read-only (is-within-investment-limits (investor principal) (amount uint))
  (match (map-get? investment-limits { investor: investor })
    limits-data
    (and
      (<= amount (get max-investment limits-data))
      (<= (+ (get current-investment limits-data) amount) (get max-investment limits-data))
    )
    false
  )
)

;; Get verification history record
(define-read-only (get-verification-history (investor principal) (record-id uint))
  (map-get? verification-history { investor: investor, record-id: record-id })
)

;; Check if investor is whitelisted
(define-read-only (is-whitelisted (investor principal))
  (default-to false
    (get whitelisted (map-get? investor-whitelist { investor: investor })))
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-verified-investors: (var-get total-verified-investors),
    verification-fee: (var-get verification-fee),
    compliance-manager: (var-get compliance-manager),
    contract-owner: CONTRACT-OWNER
  }
)

;; private functions

;; Check if caller is authorized compliance officer
(define-private (is-authorized-officer (caller principal))
  (or
    (is-eq caller CONTRACT-OWNER)
    (is-eq caller (var-get compliance-manager))
    (default-to false (get authorized (map-get? compliance-officers { officer: caller })))
  )
)

;; Get maximum investment amount based on accreditation level
(define-private (get-max-investment-by-level (level uint))
  (if (is-eq level ACCREDITATION-INSTITUTIONAL)
    u1000000000000 ;; 1M STX for institutional
    (if (is-eq level ACCREDITATION-SOPHISTICATED)
      u100000000000  ;; 100K STX for sophisticated
      (if (is-eq level ACCREDITATION-QUALIFIED)
        u10000000000   ;; 10K STX for qualified
        (if (is-eq level ACCREDITATION-RETAIL)
          u1000000000    ;; 1K STX for retail
          u100000000     ;; 100 STX for none/default
        )
      )
    )
  )
)

;; Calculate risk score based on various factors
(define-private (calculate-risk-score (investor principal))
  (let (
    (flags-data (default-to 
      { sanctions-check: false, pep-check: false, adverse-media: false, 
        high-risk-jurisdiction: false, last-check: u0, flags-count: u0 }
      (map-get? compliance-flags { investor: investor })))
    (base-score u0)
  )
    (+ base-score
      (if (get sanctions-check flags-data) u5 u0)
      (if (get pep-check flags-data) u3 u0)
      (if (get adverse-media flags-data) u2 u0)
      (if (get high-risk-jurisdiction flags-data) u2 u0)
    )
  )
)

;; Validate verification expiry
(define-private (is-verification-expired (investor principal))
  (match (map-get? investor-verification { investor: investor })
    verification-data
    (>= block-height (get expires-at verification-data))
    true
  )
)
