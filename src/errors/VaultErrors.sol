// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

error Vault__MismatchedPoolIdsAndPercentages(type name );
error Vault__InvalidAssetForDepositType(type name );
error Vault__InvalidMinPeriod();
error Vault__InvalidPercentageSplit();
error Vault__NoDepositFound();
error Vault__InactiveDeposit();
error Vault__DepositPeriodStillActive();
error Vault__DepositAlreadyWithdrawn();
error Vault__PeriodTooShort();
error Vault__IncompatibleAssetType();
error Vault__GovernanceAlreadySet();
error Vault__InvalidGovernanceAddress();
error Vault__CoverAlreadySet();
error Vault__InvalidCoverAddress();
error Vault__PoolAlreadySet();
error Vault__InvalidPoolAddress();
error Vault__PoolCanisterAlreadySet();
error Vault__InvalidPoolCanisterAddress();
error Vault__NotGovernance();
error Vault__NotCover();
error Vault__NotPool();
error Vault__NotPoolCanister();



