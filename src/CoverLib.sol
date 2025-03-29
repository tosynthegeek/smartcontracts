// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library CoverLib {
    // Pool
    struct Pool {
        uint256 id;
        string poolName;
        RiskType riskType;
        uint256 apy;
        uint256 minPeriod;
        uint256 totalUnitProcessed; // Total value that has been passed into the pool (both external and internal)
        uint256 tvl; // Total value locked of the of asset in the pool (both internal and external)
        uint256 baseValue; // Internal liquidity after investment allocation
        uint256 coverUnits; // Max coverage the pool can provide (baseValue * leverage)
        uint256 tcp;
        bool isActive;
        uint8 percentageSplitBalance;
        uint8 investmentArmPercent;
        uint8 leverage;
        address asset;
    }

    struct PoolParams {
        uint256 poolId;
        RiskType riskType;
        string poolName;
        uint256 apy;
        uint256 minPeriod;
        uint8 leverage;
        uint8 investmentArm;
        address asset;
    }

    struct Deposits {
        address lp;
        uint256 amount;
        uint256 poolId;
        uint256 dailyPayout;
        Status status;
        uint256 daysLeft;
        uint256 startDate;
        uint256 expiryDate;
        uint256 accruedPayout;
        DepositType pdt; // Vault deposit or normal pool deposit?
    }

    struct DepositParams {
        address depositor;
        uint256 poolId;
        uint256 amount;
        uint256 period;
        DepositType pdt;
        address asset;
    }

    struct GenericDepositDetails {
        address lp;
        uint256 amount;
        uint256 poolId;
        uint256 dailyPayout;
        Status status;
        uint256 daysLeft;
        uint256 startDate;
        uint256 expiryDate;
        uint256 accruedPayout;
        DepositType pdt;
        address asset; // Vault deposit or normal pool deposit?
    }

    struct PoolInfo {
        string poolName;
        uint256 poolId;
        uint256 dailyPayout;
        uint256 depositAmount;
        uint256 apy;
        uint256 minPeriod;
        uint256 totalUnit;
        uint256 tvl;
        uint256 tcp; // Total claim paid to users
        bool isActive; // Pool status to handle soft deletion
        uint256 accruedPayout;
    }

    enum DepositType {
        Normal,
        Vault
    }

    enum Status {
        Active,
        Due,
        Withdrawn
    }

    // Cover
    struct Cover {
        uint256 id;
        string coverName;
        RiskType riskType;
        string chains;
        uint256 capacity; // Capacity / percentage assigned to the cover from the pool
        uint256 capacityAmount; // Total capacity amount based on the balance of the pool
        uint256 coverValues;
        uint256 maxAmount; // Max unit of asset available
        uint256 poolId;
        string CID;
        address asset; // Asset accept for cover, should be same with the pool
    }

    struct GenericCoverInfo {
        address user;
        uint256 coverId;
        RiskType riskType;
        string coverName;
        uint256 coverValue; // This is the value of the cover purchased
        uint256 claimPaid;
        uint256 coverPeriod; // This is the period the cover is purchased for in days
        uint256 endDay; // When the cover expires
        bool isActive;
    }

    struct GenericCover {
        RiskType riskType;
        bytes coverData;
    }

    // Governance
    struct ProposalParams {
        address user;
        RiskType riskType;
        uint256 coverId;
        string txHash;
        string description;
        uint256 poolId;
        uint256 claimAmount;
        address asset;
    }

    struct Proposal {
        uint256 id;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 createdAt;
        uint256 deadline;
        uint256 timeleft;
        ProposalStaus status;
        bool executed;
        ProposalParams proposalParam;
    }

    struct Voter {
        bool voted;
        bool vote;
        uint256 weight;
    }

    enum ProposalStaus {
        Submitted,
        Pending,
        Approved,
        Claimed,
        Rejected
    }

    // Vaults
    struct Vault {
        uint256 id;
        string vaultName;
        Pool[] pools;
        uint256 minPeriod;
        uint8 investmentArmPercent;
        address asset;
        bool isActive;
    }

    struct VaultDeposit {
        address lp;
        uint256 amount;
        uint256 vaultId;
        uint256 dailyPayout;
        Status status;
        uint256 daysLeft;
        uint256 startDate;
        uint256 expiryDate;
        uint256 accruedPayout;
        address asset;
    }

    // Generic
    enum RiskType {
        Low,
        Medium,
        High
    }
}
