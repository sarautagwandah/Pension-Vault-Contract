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
        request-height: uint,
        status: (string-ascii 20),
    }
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
            (current-height stacks-block-height)
        )
        (asserts! (>= (get total-balance participant-info) amount) (err u8))
        (asserts! (get withdrawal-enabled participant-info) (err u9))
        (map-set withdrawal-requests { participant: tx-sender } {
            amount: amount,
            request-height: current-height,
            status: "pending",
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
        (map-set participant-data { participant: participant }
            (merge participant-info {
                total-balance: (- (get total-balance participant-info)
                    (get amount withdrawal-info)
                ),
                stx-balance: (- (get stx-balance participant-info)
                    (get amount withdrawal-info)
                ),
            })
        )
        (map-set withdrawal-requests { participant: participant }
            (merge withdrawal-info { status: "processed" })
        )
        (as-contract (stx-transfer? (get amount withdrawal-info) tx-sender participant))
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
                (base-yield (/ (* (get stx-balance data) (var-get yield-rate)) u100))
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
        )
        (asserts! (is-eq tx-sender contract-owner) (err u21))
        (asserts!
            (> current-height (+ (get last-yield-claim participant-info) u2016))
            (err u22)
        )
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

(define-public (emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err u17))
        (var-set vault-active false)
        (ok true)
    )
)
