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

(define-constant ERR-POOL-EXISTS (err u420))
(define-constant ERR-POOL-NOT-FOUND (err u421))
(define-constant ERR-NOT-POOL-MEMBER (err u422))
(define-constant ERR-ALREADY-APPROVED (err u423))
(define-constant ERR-INVALID-SPLIT (err u424))
(define-constant ERR-POOL-NOT-READY (err u425))

(define-constant ERR-NOT-DELEGATED (err u430))
(define-constant ERR-ALREADY-DELEGATED (err u431))
(define-constant ERR-DELEGATION-DISABLED (err u432))

(define-data-var pool-counter uint u0)

(define-constant BOOST-MIN-AMOUNT u1)

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


(define-map challenge-boosts
  { challenge-id: uint, booster: principal }
  { amount: uint, timestamp: uint }
)

(define-map total-boosts
  { challenge-id: uint }
  { total-amount: uint, booster-count: uint }
)

(define-public (boost-challenge-bounty (challenge-id uint) (boost-amount uint))
  (let (
    (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-NOT-FOUND))
    (current-boost (default-to u0 (get amount (map-get? challenge-boosts { challenge-id: challenge-id, booster: tx-sender }))))
    (current-totals (default-to { total-amount: u0, booster-count: u0 } (map-get? total-boosts { challenge-id: challenge-id })))
  )
    (asserts! (is-eq (get status challenge) "open") ERR-INVALID-STATUS)
    (asserts! (< stacks-block-height (get deadline challenge)) ERR-EXPIRED)
    (asserts! (>= boost-amount BOOST-MIN-AMOUNT) ERR-INSUFFICIENT-FUNDS)
    (try! (transfer-tokens tx-sender boost-amount))
    (map-set challenge-boosts
      { challenge-id: challenge-id, booster: tx-sender }
      { amount: (+ current-boost boost-amount), timestamp: stacks-block-height }
    )
    (map-set total-boosts
      { challenge-id: challenge-id }
      { 
        total-amount: (+ (get total-amount current-totals) boost-amount),
        booster-count: (if (is-eq current-boost u0) (+ (get booster-count current-totals) u1) (get booster-count current-totals))
      }
    )
    (map-set challenges
      { challenge-id: challenge-id }
      (merge challenge { reward: (+ (get reward challenge) boost-amount) })
    )
    (ok boost-amount)
  )
)

(define-private (refund-boosters (challenge-id uint) (booster principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: booster }))))
  )
    (map-set user-balances
      { user: booster }
      { balance: (+ current-balance amount) }
    )
    (ok true)
  )
)

(define-read-only (get-challenge-boost (challenge-id uint) (booster principal))
  (map-get? challenge-boosts { challenge-id: challenge-id, booster: booster })
)

(define-read-only (get-total-boosts (challenge-id uint))
  (default-to { total-amount: u0, booster-count: u0 } (map-get? total-boosts { challenge-id: challenge-id }))
)

(define-read-only (get-boosted-reward (challenge-id uint))
  (let (
    (challenge (map-get? challenges { challenge-id: challenge-id }))
  )
    (match challenge
      some-challenge (ok (get reward some-challenge))
      ERR-NOT-FOUND
    )
  )
)

(define-map collaboration-pools
  { pool-id: uint }
  {
    challenge-id: uint,
    creator: principal,
    members: (list 5 principal),
    splits: (list 5 uint),
    approvals: (list 5 principal),
    is-active: bool,
    solution-id: (optional uint)
  }
)

(define-map pool-memberships
  { user: principal, challenge-id: uint }
  { pool-id: uint }
)

(define-public (create-collaboration-pool 
  (challenge-id uint) 
  (members (list 5 principal)) 
  (splits (list 5 uint)))
  (let (
    (pool-id (+ (var-get pool-counter) u1))
    (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-NOT-FOUND))
    (total-split (fold + splits u0))
  )
    (asserts! (is-eq (get status challenge) "open") ERR-INVALID-STATUS)
    (asserts! (is-eq total-split u100) ERR-INVALID-SPLIT)
    (asserts! (is-none (map-get? pool-memberships { user: tx-sender, challenge-id: challenge-id })) ERR-POOL-EXISTS)
    (map-set collaboration-pools
      { pool-id: pool-id }
      {
        challenge-id: challenge-id,
        creator: tx-sender,
        members: members,
        splits: splits,
        approvals: (list tx-sender),
        is-active: false,
        solution-id: none
      }
    )
    (map-set pool-memberships { user: tx-sender, challenge-id: challenge-id } { pool-id: pool-id })
    (var-set pool-counter pool-id)
    (ok pool-id)
  )
)

(define-public (approve-pool (pool-id uint))
  (let (
    (pool (unwrap! (map-get? collaboration-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
    (is-member (is-some (index-of (get members pool) tx-sender)))
    (already-approved (is-some (index-of (get approvals pool) tx-sender)))
  )
    (asserts! is-member ERR-NOT-POOL-MEMBER)
    (asserts! (not already-approved) ERR-ALREADY-APPROVED)
    (let (
      (new-approvals (unwrap-panic (as-max-len? (append (get approvals pool) tx-sender) u5)))
      (all-approved (is-eq (len new-approvals) (len (get members pool))))
    )
      (map-set collaboration-pools
        { pool-id: pool-id }
        (merge pool { approvals: new-approvals, is-active: all-approved })
      )
      (ok all-approved)
    )
  )
)

(define-read-only (get-collaboration-pool (pool-id uint))
  (map-get? collaboration-pools { pool-id: pool-id })
)

(define-read-only (get-user-pool (user principal) (challenge-id uint))
  (map-get? pool-memberships { user: user, challenge-id: challenge-id })
)

(define-map challenge-delegations
  { challenge-id: uint }
  { enabled: bool, delegatees: (list 10 principal) }
)

(define-map user-delegation-status
  { challenge-id: uint, delegatee: principal }
  { delegated: bool, delegated-at: uint }
)

(define-public (enable-delegation (challenge-id uint))
  (let (
    (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get creator challenge)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status challenge) "open") ERR-INVALID-STATUS)
    (map-set challenge-delegations
      { challenge-id: challenge-id }
      { enabled: true, delegatees: (list) }
    )
    (ok true)
  )
)

(define-public (delegate-challenge (challenge-id uint) (delegatee principal))
  (let (
    (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR-NOT-FOUND))
    (delegation (unwrap! (map-get? challenge-delegations { challenge-id: challenge-id }) ERR-DELEGATION-DISABLED))
    (already-delegated (is-some (index-of (get delegatees delegation) delegatee)))
  )
    (asserts! (is-eq tx-sender (get creator challenge)) ERR-UNAUTHORIZED)
    (asserts! (get enabled delegation) ERR-DELEGATION-DISABLED)
    (asserts! (not already-delegated) ERR-ALREADY-DELEGATED)
    (let (
      (new-delegatees (unwrap-panic (as-max-len? (append (get delegatees delegation) delegatee) u10)))
    )
      (map-set challenge-delegations
        { challenge-id: challenge-id }
        (merge delegation { delegatees: new-delegatees })
      )
      (map-set user-delegation-status
        { challenge-id: challenge-id, delegatee: delegatee }
        { delegated: true, delegated-at: stacks-block-height }
      )
      (ok true)
    )
  )
)

(define-public (submit-delegated-solution (challenge-id uint) (content (string-ascii 1000)))
  (let (
    (delegation (map-get? challenge-delegations { challenge-id: challenge-id }))
    (is-delegated (map-get? user-delegation-status { challenge-id: challenge-id, delegatee: tx-sender }))
  )
    (match delegation
      some-delegation
        (if (get enabled some-delegation)
          (begin
            (asserts! (is-some is-delegated) ERR-NOT-DELEGATED)
            (submit-solution challenge-id content)
          )
          (submit-solution challenge-id content)
        )
      (submit-solution challenge-id content)
    )
  )
)

(define-read-only (get-delegation-info (challenge-id uint))
  (map-get? challenge-delegations { challenge-id: challenge-id })
)

(define-read-only (is-delegated (challenge-id uint) (delegatee principal))
  (is-some (map-get? user-delegation-status { challenge-id: challenge-id, delegatee: delegatee }))
)