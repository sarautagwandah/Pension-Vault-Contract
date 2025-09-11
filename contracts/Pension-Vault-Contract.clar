(define-constant contract-owner tx-sender)
(define-constant retirement-age u65)
(define-constant min-deposit u1000)
(define-constant early-withdrawal-fee u10)
(define-constant contract-version "1.0.0")

(define-data-var total-deposits uint u0)
(define-data-var total-participants uint u0)
(define-data-var vault-active bool true)
(define-data-var yield-rate uint u5)
(define-data-var last-yield-distribution uint u0)

(define-map participant-data
    { participant: principal }
    {
        birth-year: uint,
        total-balance: uint,
        last-deposit: uint,
        withdrawal-enabled: bool,
        stx-balance: uint,
        btc-balance: uint,
        yield-earned: uint,
        last-yield-claim: uint,
    }
)

(define-map withdrawal-requests
    { participant: principal }
    {
        amount: uint,
        request_height: uint,
        status: (string-ascii 20),
        is_early: bool,
    }
)

(define-map beneficiary-data
    {
        participant: principal,
        beneficiary-index: uint,
    }
    {
        beneficiary: principal,
        allocation: uint,
        is-active: bool,
    }
)

(define-map participant-beneficiary-count
    { participant: principal }
    { count: uint }
)

(define-read-only (get-participant-data (participant principal))
    (map-get? participant-data { participant: participant })
)

(define-read-only (get-total-deposits)
    (var-get total-deposits)
)

(define-read-only (get-total-participants)
    (var-get total-participants)
)

(define-read-only (can-withdraw (participant principal))
    (match (map-get? participant-data { participant: participant })
        data (get withdrawal-enabled data)
        false
    )
)

(define-public (register-participant (birth-year uint))
    (let ((current-year (/ stacks-block-height u525600)))
        (asserts! (>= (- current-year birth-year) u18) (err u1))
        (asserts! (< (- current-year birth-year) u100) (err u2))
        (asserts!
            (is-none (map-get? participant-data { participant: tx-sender }))
            (err u3)
        )
        (map-set participant-data { participant: tx-sender } {
            birth-year: birth-year,
            total-balance: u0,
            last-deposit: u0,
            withdrawal-enabled: false,
            stx-balance: u0,
            btc-balance: u0,
            yield-earned: u0,
            last-yield-claim: u0,
        })
        (var-set total-participants (+ (var-get total-participants) u1))
        (ok true)
    )
)

(define-public (deposit-stx (amount uint))
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: tx-sender })
                (err u4)
            ))
            (current-height stacks-block-height)
        )
        (asserts! (>= amount min-deposit) (err u5))
        (asserts!
            (is-eq (stx-transfer? amount tx-sender (as-contract tx-sender))
                (ok true)
            )
            (err u6)
        )
        (map-set participant-data { participant: tx-sender }
            (merge participant-info {
                total-balance: (+ (get total-balance participant-info) amount),
                last-deposit: current-height,
                stx-balance: (+ (get stx-balance participant-info) amount),
            })
        )
        (var-set total-deposits (+ (var-get total-deposits) amount))
        (ok true)
    )
)

(define-public (request-withdrawal (amount uint))
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: tx-sender })
                (err u7)
            ))
            (is-enabled (get withdrawal-enabled participant-info))
            (current-height stacks-block-height)
        )
        (asserts! (>= (get total-balance participant-info) amount) (err u8))
        (map-set withdrawal-requests { participant: tx-sender } {
            amount: amount,
            request_height: current-height,
            status: "pending",
            is_early: (not is-enabled),
        })
        (ok true)
    )
)

(define-public (process-withdrawal (participant principal))
    (let (
            (withdrawal-info (unwrap! (map-get? withdrawal-requests { participant: participant })
                (err u10)
            ))
            (participant-info (unwrap! (map-get? participant-data { participant: participant })
                (err u11)
            ))
        )
        (asserts! (is-eq tx-sender contract-owner) (err u12))
        (asserts! (is-eq (get status withdrawal-info) "pending") (err u13))
        (let (
                (full-amount (get amount withdrawal-info))
                (is-early (get is_early withdrawal-info))
                (transfer-amount (if is-early
                    (/ (* full-amount u90) u100)
                    full-amount
                ))
            )
            (map-set participant-data { participant: participant }
                (merge participant-info {
                    total-balance: (- (get total-balance participant-info) full-amount),
                    stx-balance: (- (get stx-balance participant-info) full-amount),
                })
            )
            (map-set withdrawal-requests { participant: participant }
                (merge withdrawal-info { status: "processed" })
            )
            (as-contract (stx-transfer? transfer-amount tx-sender participant))
        )
    )
)

(define-public (enable-withdrawals (participant principal))
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: participant })
                (err u14)
            ))
            (current-year (/ stacks-block-height u525600))
        )
        (asserts! (is-eq tx-sender contract-owner) (err u15))
        (asserts!
            (>= (- current-year (get birth-year participant-info)) retirement-age)
            (err u16)
        )
        (map-set participant-data { participant: participant }
            (merge participant-info { withdrawal-enabled: true })
        )
        (ok true)
    )
)

(define-read-only (calculate-yield (participant principal))
    (match (map-get? participant-data { participant: participant })
        data (let (
                (deposit-duration (- stacks-block-height (get last-deposit data)))
                (balance-scaled (* (get stx-balance data) u1000))
                (base-yield (/ (* balance-scaled (var-get yield-rate)) u100000))
                (duration-bonus (/ (* base-yield deposit-duration) u52560))
            )
            (ok (+ base-yield duration-bonus))
        )
        (err u18)
    )
)

(define-public (distribute-yield (participant principal))
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: participant })
                (err u19)
            ))
            (current-height stacks-block-height)
            (yield-amount (unwrap! (calculate-yield participant) (err u20)))
            (contract-balance (stx-get-balance (as-contract tx-sender)))
        )
        (asserts! (is-eq tx-sender contract-owner) (err u21))
        (asserts!
            (> current-height (+ (get last-yield-claim participant-info) u2016))
            (err u22)
        )
        (asserts! (>= contract-balance yield-amount) (err u25))
        (map-set participant-data { participant: participant }
            (merge participant-info {
                yield-earned: (+ (get yield-earned participant-info) yield-amount),
                last-yield-claim: current-height,
            })
        )
        (var-set last-yield-distribution current-height)
        (ok yield-amount)
    )
)

(define-public (claim-yield)
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: tx-sender })
                (err u23)
            ))
            (yield-amount (get yield-earned participant-info))
        )
        (asserts! (> yield-amount u0) (err u24))
        (map-set participant-data { participant: tx-sender }
            (merge participant-info {
                yield-earned: u0,
                total-balance: (+ (get total-balance participant-info) yield-amount),
                stx-balance: (+ (get stx-balance participant-info) yield-amount),
            })
        )
        (ok yield-amount)
    )
)

(define-public (update-yield-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err u26))
        (asserts! (<= new-rate u20) (err u27))
        (var-set yield-rate new-rate)
        (ok true)
    )
)

(define-read-only (get-beneficiary-data
        (participant principal)
        (beneficiary-index uint)
    )
    (map-get? beneficiary-data {
        participant: participant,
        beneficiary-index: beneficiary-index,
    })
)

(define-read-only (get-beneficiary-count (participant principal))
    (default-to u0
        (get count
            (map-get? participant-beneficiary-count { participant: participant })
        ))
)

(define-public (set-beneficiary
        (beneficiary principal)
        (allocation uint)
    )
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: tx-sender })
                (err u28)
            ))
            (current-count (get-beneficiary-count tx-sender))
            (new-count (+ current-count u1))
        )
        (asserts! (> allocation u0) (err u29))
        (asserts! (<= allocation u100) (err u30))
        (asserts! (<= new-count u5) (err u31))
        (asserts! (not (is-eq beneficiary tx-sender)) (err u32))
        (map-set beneficiary-data {
            participant: tx-sender,
            beneficiary-index: current-count,
        } {
            beneficiary: beneficiary,
            allocation: allocation,
            is-active: true,
        })
        (map-set participant-beneficiary-count { participant: tx-sender } { count: new-count })
        (ok new-count)
    )
)

(define-public (update-beneficiary
        (beneficiary-index uint)
        (beneficiary principal)
        (allocation uint)
    )
    (let (
            (participant-info (unwrap! (map-get? participant-data { participant: tx-sender })
                (err u33)
            ))
            (beneficiary-info (unwrap!
                (map-get? beneficiary-data {
                    participant: tx-sender,
                    beneficiary-index: beneficiary-index,
                })
                (err u34)
            ))
        )
        (asserts! (> allocation u0) (err u35))
        (asserts! (<= allocation u100) (err u36))
        (asserts! (not (is-eq beneficiary tx-sender)) (err u37))
        (map-set beneficiary-data {
            participant: tx-sender,
            beneficiary-index: beneficiary-index,
        } {
            beneficiary: beneficiary,
            allocation: allocation,
            is-active: true,
        })
        (ok true)
    )
)

(define-public (claim-inheritance (deceased-participant principal))
    (let (
            (participant-info (unwrap!
                (map-get? participant-data { participant: deceased-participant })
                (err u38)
            ))
            (current-height stacks-block-height)
            (inactive-period (- current-height (get last-deposit participant-info)))
            (beneficiary-count (get-beneficiary-count deceased-participant))
        )
        (asserts! (> inactive-period u105120) (err u39))
        (asserts! (> beneficiary-count u0) (err u40))
        (let ((claimer-allocation (fold check-beneficiary-allocation (list u0 u1 u2 u3 u4) {
                participant: deceased-participant,
                claimer: tx-sender,
                found-allocation: u0,
            })))
            (asserts! (> (get found-allocation claimer-allocation) u0) (err u41))
            (let (
                    (total-balance (get total-balance participant-info))
                    (inheritance-amount (/
                        (* total-balance
                            (get found-allocation claimer-allocation)
                        )
                        u100
                    ))
                )
                (map-set participant-data { participant: deceased-participant }
                    (merge participant-info {
                        total-balance: (- total-balance inheritance-amount),
                        stx-balance: (- (get stx-balance participant-info) inheritance-amount),
                    })
                )
                (as-contract (stx-transfer? inheritance-amount tx-sender tx-sender))
            )
        )
    )
)

(define-private (check-beneficiary-allocation
        (index uint)
        (data {
            participant: principal,
            claimer: principal,
            found-allocation: uint,
        })
    )
    (match (map-get? beneficiary-data {
        participant: (get participant data),
        beneficiary-index: index,
    })
        beneficiary-info (if (and (is-eq (get beneficiary beneficiary-info) (get claimer data)) (get is-active beneficiary-info))
            (merge data { found-allocation: (get allocation beneficiary-info) })
            data
        )
        data
    )
)

(define-public (emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err u17))
        (var-set vault-active false)
        (ok true)
    )
)
