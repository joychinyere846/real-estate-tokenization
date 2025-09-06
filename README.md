# Real Estate Investment Platform

A comprehensive blockchain-based platform for real estate asset tokenization and fractionalized investment management built on the Stacks blockchain using Clarity smart contracts.

## Overview

This platform enables the tokenization of real estate assets, allowing for fractional ownership and creating new investment opportunities. The system ensures compliance through investor verification and provides a secure environment for managing real estate investments.

## Architecture

The platform consists of three core smart contracts:

### 1. Asset Tokenization Contract (`asset-tokenization.clar`)
- **Property Registration**: Register real estate assets with metadata and valuations
- **Fractional Token Minting**: Create fungible tokens representing fractional ownership
- **Valuation Management**: Update property valuations and calculate token prices
- **Transfer Restrictions**: Ensure only verified investors can trade tokens

### 2. Investor Verification Contract (`investor-verification.clar`)
- **KYC Management**: Handle Know Your Customer verification status
- **Accreditation Levels**: Manage different investor accreditation types
- **Compliance Tracking**: Maintain verification timestamps and status
- **Access Control**: Provide verification checks for other contracts

### 3. Investment Platform Contract (`investment-platform.clar`)
- **Investment Pools**: Manage collective investment pools for properties
- **Dividend Distribution**: Handle rental income and profit sharing
- **Voting Mechanism**: Enable token-based governance for investment decisions
- **Fee Management**: Collect and manage platform fees

## Features

- ✅ **Asset Tokenization**: Convert real estate into tradeable tokens
- ✅ **Fractional Ownership**: Enable small investors to participate in real estate
- ✅ **Compliance Management**: Ensure regulatory compliance through KYC/AML
- ✅ **Investment Pools**: Create collective investment opportunities
- ✅ **Dividend Distribution**: Automate rental income sharing
- ✅ **Governance**: Token-based voting on property decisions
- ✅ **Transfer Restrictions**: Maintain compliance with securities regulations

## Development Setup

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) - Clarity development environment
- Node.js and npm
- Git

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd real-estate-tokenization

# Install dependencies
npm install

# Check contract syntax
clarinet check
```

## Contract APIs

### Asset Tokenization Contract

#### Public Functions
- `register-property(property-id, total-tokens, price-per-token, metadata)` - Register a new property
- `mint-tokens(property-id, recipient, amount)` - Mint fractional tokens
- `transfer-tokens(property-id, sender, recipient, amount)` - Transfer tokens between verified investors
- `update-valuation(property-id, new-price-per-token)` - Update property valuation

#### Read-Only Functions
- `get-property-info(property-id)` - Get property details
- `get-token-balance(property-id, owner)` - Get user's token balance
- `get-total-supply(property-id)` - Get total token supply for property

### Investor Verification Contract

#### Public Functions
- `set-verification-status(investor, kyc-status, accreditation-level)` - Set investor verification
- `clear-verification(investor)` - Remove investor verification
- `update-accreditation(investor, new-level)` - Update accreditation level

#### Read-Only Functions
- `is-verified(investor)` - Check if investor is verified
- `get-verification-info(investor)` - Get complete verification details
- `get-accreditation-level(investor)` - Get investor accreditation level

### Investment Platform Contract

#### Public Functions
- `create-investment-pool(property-id, target-amount)` - Create new investment pool
- `invest-in-pool(property-id, amount)` - Invest in a property pool
- `distribute-dividends(property-id, total-amount)` - Distribute rental income
- `create-proposal(property-id, proposal-type, description)` - Create governance proposal
- `vote-on-proposal(proposal-id, vote)` - Vote on proposals

#### Read-Only Functions
- `get-pool-info(property-id)` - Get investment pool details
- `get-investor-share(property-id, investor)` - Get investor's pool share
- `get-proposal-info(proposal-id)` - Get proposal details

## Development Workflow

### Branch Structure
- **main**: Production-ready code with documentation
- **development**: Active development branch for new features

### Development Process
1. Switch to development branch: `git checkout development`
2. Create feature branches from development
3. Implement and test changes
4. Submit pull requests to development
5. Merge to main after review

### Testing
```bash
# Run contract syntax check
clarinet check

# Run unit tests (if implemented)
npm test

# Check specific contract
clarinet check contracts/asset-tokenization.clar
```

## Compliance Features

- **KYC Integration**: Mandatory investor verification before token purchases
- **Accreditation Levels**: Support for different investor categories
- **Transfer Restrictions**: Securities law compliance through verified-only transfers
- **Audit Trail**: Complete transaction and verification history on-chain

## Security Considerations

- **Access Control**: Contract owner permissions for sensitive operations
- **Input Validation**: Comprehensive parameter validation in all functions
- **Safe Math**: Protection against overflow/underflow in calculations
- **Reentrancy Protection**: Safe external call patterns

## Contributing

1. Fork the repository
2. Create a feature branch from `development`
3. Make your changes following Clarity best practices
4. Test thoroughly using `clarinet check`
5. Submit a pull request with detailed description

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions, issues, or contributions, please create an issue in the GitHub repository.
