# Unknown Finance

## Overview

Unknown Finance is a privacy-preserving index fund protocol built on Ethereum that enables users to invest in a basket of tokens while maintaining complete confidentiality of their positions and transactions. The protocol leverages Fully Homomorphic Encryption (FHE) to provide unprecedented privacy in DeFi index fund investments.

## Key Features

### Privacy-Preserving Operations
- Confidential minting and burning of index fund shares
- Private stablecoin deposits and withdrawals
- Encrypted balance tracking and transfers
- Hidden transaction amounts and user positions

### Advanced Index Fund Management
- Automatic token swaps based on market cap weights
- Support for both index token and stablecoin redemption paths
- Real-time market data integration for accurate pricing
- Dynamic share price calculation based on underlying assets


## Architecture

### Core Components

1. **ConfidentialIndexFund**
   - Main contract managing the index fund operations
   - Handles encrypted deposits, withdrawals, and share management
   - Integrates with Uniswap V4 for token swaps
   - Maintains privacy through FHE implementation

2. **IndexFundToken**
   - Confidential ERC20 token representing index fund shares
   - Implements encrypted balance tracking
   - Supports private transfers and allowances

3. **IndexFundFactory**
   - Creates and manages index fund instances
   - Handles token-stablecoin pair whitelisting
   - Maintains global protocol parameters

4. **SwapsManager**
   - Manages token swaps through Uniswap V4

5. **MarketDataFetcher**
   - Integrates with Chainlink price feeds
   - Calculates market capitalizations
