# 🧠 Crowdsourced Problem-Solving Challenges

## 📋 Overview

A decentralized platform for posting science and technology challenges where solvers earn tokens through on-chain validation and community voting.

## 🚀 Features

- **Challenge Creation**: 📝 Post science/tech challenges with rewards
- **Solution Submission**: 💡 Submit solutions to earn tokens
- **Community Voting**: 🗳️ Vote on the best solutions
- **Token Distribution**: 💰 Automatic reward distribution to winners
- **Deadline Management**: ⏰ Time-bound challenges with expiration

## 🛠️ Contract Functions

### Public Functions

#### `create-challenge`
Create a new challenge with title, description, reward amount, and duration.
```clarity
(contract-call? .contract create-challenge "AI Ethics" "How can we ensure AI fairness?" u1000 u144)
```

#### `submit-solution`
Submit a solution to an existing challenge.
```clarity
(contract-call? .contract submit-solution u1 "Implement bias detection algorithms...")
```

#### `vote-solution`
Vote for a solution (one vote per user per solution).
```clarity
(contract-call? .contract vote-solution u1)
```

#### `finalize-challenge`
Finalize a challenge after deadline (only by creator).
```clarity
(contract-call? .contract finalize-challenge u1)
```

### Read-Only Functions

#### `get-challenge`
Get challenge details by ID.
```clarity
(contract-call? .contract get-challenge u1)
```

#### `get-solution`
Get solution details by ID.
```clarity
(contract-call? .contract get-solution u1)
```

#### `get-user-balance`
Check user's token balance.
```clarity
(contract-call? .contract get-user-balance 'SP1ABC...)
```

## 📊 Data Structure

### Challenges
- `challenge-id`: Unique identifier
- `creator`: Challenge creator's principal
- `title`: Challenge title (max 100 chars)
- `description`: Challenge description (max 500 chars)
- `reward`: Token reward amount
- `deadline`: Block height deadline
- `status`: "open", "completed", or "expired"
- `winner`: Winning solver (optional)
- `solution-count`: Number of solutions

### Solutions
- `solution-id`: Unique identifier
- `challenge-id`: Associated challenge
- `solver`: Solution submitter's principal
- `content`: Solution content (max 1000 chars)
- `votes`: Number of community votes
- `submitted-at`: Submission block height

## 🎯 Usage Flow

1. **Create Challenge**: 📝 User creates a challenge with reward
2. **Submit Solutions**: 💡 Solvers submit their solutions
3. **Vote**: 🗳️ Community votes on best solutions
4. **Finalize**: ⏰ Creator finalizes after deadline
5. **Distribute**: 💰 Tokens automatically distributed to winner

## 🔧 Development

### Prerequisites
- Clarinet CLI
- Stacks blockchain

### Testing
```bash
clarinet test
```

### Deployment
```bash
clarinet deploy
```

## 🏆 Rewards System

- Winners receive the full challenge reward
- If no solutions, creator gets refund
- Voting determines the winning solution
- Automatic token distribution on finalization

## 🔐 Security Features

- Deadline enforcement
- One vote per user per solution
- Creator-only finalization
- Insufficient funds protection
- Status validation

## 📈 Future Enhancements

- Multi-winner challenges
- Reputation system
- Solution categories
- Advanced voting mechanisms
- Integration with external oracles

---

*Built with ❤️ on Stacks blockchain*
