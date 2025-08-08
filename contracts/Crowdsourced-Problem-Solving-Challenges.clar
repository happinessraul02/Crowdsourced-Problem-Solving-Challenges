(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-EXPIRED (err u410))
(define-constant ERR-ALREADY-VOTED (err u409))
(define-constant ERR-INSUFFICIENT-FUNDS (err u402))
(define-constant ERR-INVALID-STATUS (err u400))

(define-constant REPUTATION-SOLUTION-SUBMIT u10)
(define-constant REPUTATION-VOTE-RECEIVED u5)
(define-constant REPUTATION-CHALLENGE-COMPLETE u25)
(define-constant REPUTATION-SOLUTION-ACCEPT u50)

(define-data-var challenge-counter uint u0)
(define-data-var solution-counter uint u0)

(define-map challenges
  { challenge-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    reward: uint,
    deadline: uint,
    status: (string-ascii 20),
    winner: (optional principal),
    solution-count: uint
  }
) 

(define-map solutions
  { solution-id: uint }
  {
    challenge-id: uint,
    solver: principal,
    content: (string-ascii 1000),
    votes: uint,
    submitted-at: uint
  }
)

(define-map votes
  { voter: principal, solution-id: uint }
  { voted: bool }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)


(define-public (create-challenge (title (string-ascii 100)) (description (string-ascii 500)) (reward uint) (duration uint))
  (let (
    (challenge-id (+ (var-get challenge-counter) u1))
    (deadline (+ stacks-block-height duration))
  )
    (asserts! (> reward u0) ERR-INSUFFICIENT-FUNDS)
    (try! (transfer-tokens tx-sender reward))
    (map-set challenges
      { challenge-id: challenge-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        reward: reward,
        deadline: deadline,
        status: "open",
        winner: none,
        solution-count: u0
      }
    )
    (var-set challenge-counter challenge-id)
    (ok challenge-id)
  )
)

(define-public (submit-solution (challenge-id uint) (content (string-ascii 1000)))
  (let (
    (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-NOT-FOUND))
    (solution-id (+ (var-get solution-counter) u1))
  )
    (asserts! (< stacks-block-height (get deadline challenge)) ERR-EXPIRED)
    (asserts! (is-eq (get status challenge) "open") ERR-INVALID-STATUS)
    (map-set solutions
      { solution-id: solution-id }
      {
        challenge-id: challenge-id,
        solver: tx-sender,
        content: content,
        votes: u0,
        submitted-at: stacks-block-height
      }
    )
    (map-set challenges
      { challenge-id: challenge-id }
      (merge challenge { solution-count: (+ (get solution-count challenge) u1) })
    )
    (var-set solution-counter solution-id)
    (ok solution-id)
  )
)

(define-public (vote-solution (solution-id uint))
  (let (
    (solution (unwrap! (map-get? solutions { solution-id: solution-id }) ERR-NOT-FOUND))
    (challenge (unwrap! (map-get? challenges { challenge-id: (get challenge-id solution) }) ERR-NOT-FOUND))
  )
    (asserts! (< stacks-block-height (get deadline challenge)) ERR-EXPIRED)
    (asserts! (is-eq (get status challenge) "open") ERR-INVALID-STATUS)
    (asserts! (is-none (map-get? votes { voter: tx-sender, solution-id: solution-id })) ERR-ALREADY-VOTED)
    (map-set votes
      { voter: tx-sender, solution-id: solution-id }
      { voted: true }
    )
    (map-set solutions
      { solution-id: solution-id }
      (merge solution { votes: (+ (get votes solution) u1) })
    )
    (ok true)
  )
)

(define-public (finalize-challenge (challenge-id uint))
  (let (
    (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get creator challenge)) ERR-UNAUTHORIZED)
    (asserts! (> stacks-block-height (get deadline challenge)) ERR-INVALID-STATUS)
    (asserts! (is-eq (get status challenge) "open") ERR-INVALID-STATUS)
    (if (> (get solution-count challenge) u0)
      (begin
        (map-set challenges
          { challenge-id: challenge-id }
          (merge challenge { 
            status: "completed",
            winner: (some tx-sender)
          })
        )
        (ok tx-sender)
      )
      (let (
        (refund-result (refund-creator (get creator challenge) (get reward challenge)))
      )
        (map-set challenges
          { challenge-id: challenge-id }
          (merge challenge { status: "expired" })
        ) 
        (ok tx-sender)
      )
    )
  )
)


(define-private (transfer-tokens (from principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: from }))))
  )
    (asserts! (>= current-balance amount) ERR-INSUFFICIENT-FUNDS)
    (map-set user-balances
      { user: from }
      { balance: (- current-balance amount) }
    )
    (ok true)
  )
)

(define-private (distribute-reward (winner principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: winner }))))
  )
    (map-set user-balances
      { user: winner }
      { balance: (+ current-balance amount) }
    )
    (ok true)
  )
)

(define-private (refund-creator (creator principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: creator }))))
  )
    (map-set user-balances
      { user: creator }
      { balance: (+ current-balance amount) }
    )
    (ok true)
  )
)

(define-read-only (get-challenge (challenge-id uint))
  (map-get? challenges { challenge-id: challenge-id })
)

(define-read-only (get-solution (solution-id uint))
  (map-get? solutions { solution-id: solution-id })
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

(define-read-only (get-challenge-count)
  (var-get challenge-counter)
)

(define-read-only (get-solution-count)
  (var-get solution-counter)
)

(define-read-only (has-voted (voter principal) (solution-id uint))
  (is-some (map-get? votes { voter: voter, solution-id: solution-id }))
)

(define-map user-reputation
  { user: principal }
  { 
    score: uint,
    solutions-submitted: uint,
    solutions-accepted: uint,
    votes-received: uint,
    challenges-created: uint
  }
)

(define-map reputation-milestones
  { user: principal, milestone: uint }
  { achieved: bool, timestamp: uint }
)

(define-public (update-reputation-submit (solver principal))
  (let (
    (current-rep (default-to 
      { score: u0, solutions-submitted: u0, solutions-accepted: u0, votes-received: u0, challenges-created: u0 }
      (map-get? user-reputation { user: solver })
    ))
  )
    (begin
      (map-set user-reputation
        { user: solver }
        (merge current-rep {
          score: (+ (get score current-rep) REPUTATION-SOLUTION-SUBMIT),
          solutions-submitted: (+ (get solutions-submitted current-rep) u1)
        })
      )
      (check-milestones solver (+ (get score current-rep) REPUTATION-SOLUTION-SUBMIT))
    )
  )
)

(define-public (update-reputation-vote (solver principal))
  (let (
    (current-rep (default-to 
      { score: u0, solutions-submitted: u0, solutions-accepted: u0, votes-received: u0, challenges-created: u0 }
      (map-get? user-reputation { user: solver })
    ))
  )
    (begin
      (map-set user-reputation
        { user: solver }
        (merge current-rep {
          score: (+ (get score current-rep) REPUTATION-VOTE-RECEIVED),
          votes-received: (+ (get votes-received current-rep) u1)
        })
      )
      (check-milestones solver (+ (get score current-rep) REPUTATION-VOTE-RECEIVED))
    )
  )
)

(define-public (update-reputation-accept (solver principal))
  (let (
    (current-rep (default-to 
      { score: u0, solutions-submitted: u0, solutions-accepted: u0, votes-received: u0, challenges-created: u0 }
      (map-get? user-reputation { user: solver })
    ))
  )
    (begin
      (map-set user-reputation
        { user: solver }
        (merge current-rep {
          score: (+ (get score current-rep) REPUTATION-SOLUTION-ACCEPT),
          solutions-accepted: (+ (get solutions-accepted current-rep) u1)
        })
      )
      (check-milestones solver (+ (get score current-rep) REPUTATION-SOLUTION-ACCEPT))
    )
  )
)

(define-private (check-milestones (user principal) (new-score uint))
  (begin
    (if (and (>= new-score u100) (is-none (map-get? reputation-milestones { user: user, milestone: u100 })))
      (map-set reputation-milestones { user: user, milestone: u100 } { achieved: true, timestamp: stacks-block-height })
      false
    )
    (if (and (>= new-score u500) (is-none (map-get? reputation-milestones { user: user, milestone: u500 })))
      (map-set reputation-milestones { user: user, milestone: u500 } { achieved: true, timestamp: stacks-block-height })
      false
    )
    (if (and (>= new-score u1000) (is-none (map-get? reputation-milestones { user: user, milestone: u1000 })))
      (map-set reputation-milestones { user: user, milestone: u1000 } { achieved: true, timestamp: stacks-block-height })
      false
    )
    (ok true)
  )
)

(define-read-only (get-user-reputation (user principal))
  (default-to 
    { score: u0, solutions-submitted: u0, solutions-accepted: u0, votes-received: u0, challenges-created: u0 }
    (map-get? user-reputation { user: user })
  )
)

(define-read-only (get-reputation-score (user principal))
  (get score (get-user-reputation user))
)

(define-read-only (has-milestone (user principal) (milestone uint))
  (is-some (map-get? reputation-milestones { user: user, milestone: milestone }))
)