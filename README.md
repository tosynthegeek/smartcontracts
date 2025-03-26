# BQLabs Testnet Contracts v1

Forked from [BQ contracts](https://github.com/bitquid-labs/smartcontract) integrated with Aave for yield aggregration for user deposits and Eigenlayer for AVS configured to be deployed on Base.

## Overview

BQ Labs is pioneering the first Bitcoin Risk Management Layer, aiming to secure the Bitcoin ecosystem through a decentralized insurance infrastructure. The BQ Protocol provides a robust technical, operational, and legal framework that enables members to underwrite and trade risk as a liquid asset, purchase coverage, and efficiently assess claims. This protocol is designed to bring transparency, trust, and efficiency to the Bitcoin financial landscape.

## System Architecture

### Key Actors and Processes

The BQ Protocol is structured around three primary user roles, each interacting with the protocol’s layered architecture to facilitate decentralized risk management:

- **Proposers (Cover Buyers/Clients):**  
   Proposers utilize the platform to secure their Bitcoin-related financial activities, such as staking and smart contracts, by purchasing tailored insurance coverage. After connecting their non-custodial wallet, proposers can select from various coverage options based on their specific risk profiles. The claims process is managed through a decentralized governance model, involving risk assessors, validators, and underwriters, particularly for complex risk scenarios.

- **Stakers (Liquidity Providers):**  
   Stakers provide liquidity to insurance pools, and vaults earning returns on their investments. The protocol ensures full transparency of risk and yield details, allowing Stakers to make informed decisions. The capital provided by Stakers is deployed to cover risks during adverse events, ensuring a resilient insurance framework.

## Core Features

1. **Purchase Cover:**  
   Users can browse through a selection of risks, select a coverage tenure and amount, and secure their BTCFi position. This feature is fully integrated with non-custodial wallets, enabling seamless transactions.

2. **Stake:**  
   The staking module allows users to contribute assets to various credit-rated pools or vaults. The module provides real-time visibility into pool fund utilization, daily yield claims, and asset withdrawal upon the completion of the staking period.

3. **Dynamic Pricing:**  
   The platform employs dynamic pricing algorithms to calculate cover capacity, pool ratios, and claim-based price discovery. This ensures that pricing remains fair and reflective of real-time risk assessments.

4. **Vaults**:
   Allows users to make deposits into multiple pools in a single unit

## LICENSE

This project is licensed under the MIT license, see LICENSE.md for details.

# TODOs

- Refactor storage variables, constants, sload, and sstore
