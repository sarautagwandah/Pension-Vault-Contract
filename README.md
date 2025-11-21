# Pension Vault Contract
A secure and efficient pension vault system built on Stacks blockchain that allows users to save STX for retirement.

## 🌟 Features

- Secure STX deposits with minimum deposit requirement
- Age-based withdrawal restrictions
- Emergency shutdown capability
- Withdrawal request system
- Complete participant tracking

## 🔒 Security Features

- Access control checks for admin functions
- Input validation for all public functions
- Proper error handling
- Withdrawal approval system

## 🚀 Getting Started

1. Install Clarinet
```bash
curl -L https://github.com/hirosystems/clarinet/releases/download/v1.0.0/clarinet-linux-x64.tar.gz | tar -xz
```

2. Initialize project
```bash
clarinet new pension-vault && cd pension-vault
```

3. Run tests
```bash
clarinet test
```

## 💻 UI Requirements

### Dashboard Features:
- Account Overview showing:
  - Current balance
  - Time until retirement
  - Deposit history
- Deposit form with STX amount input
- Withdrawal request interface
- Transaction history

## 🧪 Testing

Run the included test suite:
```bash
clarinet test tests/pension-vault_test.ts
