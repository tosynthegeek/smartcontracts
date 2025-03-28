// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "aave-v3-core/contracts/interfaces/IPool.sol";
import "./CoverLib.sol";
import "./errors/VaultErrors.sol";

interface ICover {
    function updateMaxAmount(uint256 _coverId) external;
    function getDepositClaimableDays(address user, uint256 _poolId) external view returns (uint256);
    function getLastClaimTime(address user, uint256 _poolId) external view returns (uint256);
}

interface IbqBTC {
    function bqMint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ILP {
    function vaultWithdrawUpdate(CoverLib.Deposits[] _deposits, CoverLib.Pool[] _pools) external;

    function getPool(uint256 _poolId) external view returns (CoverLib.Pool memory);
    function registerVaultDeposits(CoverLib.DepositParams[] calldata _depositParams, uint256[] internalDepositAmounts)
        external
        returns (uint256);
}

interface IGov {
    function getProposalDetails(uint256 _proposalId) external returns (CoverLib.Proposal memory);
    function updateProposalStatusToClaimed(uint256 proposalId) external;
}

contract Vaults is ReentrancyGuard, Ownable {
    using CoverLib for *;

    mapping(uint256 => Vault) s_vaults;
    mapping(uint256 => mapping(uint256 => uint256)) s_vaultPercentageSplits; //vault id to pool id to the pool percentage split;
    mapping(address => mapping(uint256 => mapping(CoverLib.DepositType => CoverLib.Deposits))) s_deposits;
    mapping(address => mapping(uint256 => CoverLib.VaultDeposit)) s_userVaultDeposits;
    mapping(address => uint256) private s_participation;
    address[] private s_participants;
    address private s_governance;

    uint256 private s_vaultCount;
    IGov private s_governanceContract;
    uint16 private s_referralCode = 0;

    ICover private immutable i_coverContract;
    ILP private immutable i_poolContract;
    IPool public immutable i_aavePool;
    IbqBTC private immutable i_bqBTC;

    address private immutable i_poolContractAddress;
    address private immutable i_bqBTCAddress;
    address private immutable i_coverContractAddress;
    address private immutable i_initialOwner;

    event Deposited(address indexed user, uint256 amount, string pool);
    event Withdraw(address indexed user, uint256 amount, string pool);
    event ClaimPaid(address indexed recipient, string pool, uint256 amount);
    event PoolCreated(uint256 indexed id, string poolName);
    event PoolUpdated(uint256 indexed poolId, uint256 apy, uint256 _minPeriod);
    event ClaimAttempt(uint256, uint256, address);

    constructor(address _initialOwner, address bq, address _poolAddress, address _coverAdress, address _aavePoolAdress)
        Ownable(_initialOwner)
    {
        i_initialOwner = _initialOwner;
        i_bqBTC = IbqBTC(bq);
        i_bqBTCAddress = bq;
        i_aavePool = IPool(_aavePoolAdress);
        i_poolContract = ILP(_poolAddress);
        i_coverContract = ICover(_coverAdress);
        i_poolContractAddress = _poolAddress;
        i_coverContractAddress = _coverAdress;
    }

    function createVault(
        string memory _vaultName,
        uint256[] memory _poolIds,
        uint256[] memory poolPercentageSplit,
        uint256 _minPeriod,
        uint8 _investmentArmPercent,
        address asset
    ) public onlyOwner {
        if (_poolIds.length != poolPercentageSplit.length) {
            revert Vault__MismatchedPoolIdsAndPercentages();
        }
        if (asset == address(0)) {
            revert Vault__InvalidAssetForDepositType();
        }

        s_vaultCount += 1;
        Vault storage vault = s_vaults[vaultCount];
        vault.id = vaultCount;
        vault.vaultName = _vaultName;
        vault.investmentArm = _investmentArmPercent;
        vault.asset = asset;
        vault.isActive = true;

        (uint256 percentageSplit, uint256 minPeriod) = validateAndSetPools(vault, _poolIds, poolPercentageSplit, adt);

        if (_minPeriod < minPeriod) revert Vault__InvalidMinPeriod();

        if (percentageSplit != 100) revert Vault__InvalidPercentageSplit();

        vault.minPeriod = _minPeriod;
    }

    function vaultDeposit(uint256 _vaultId, uint256 _amount, uint256 _period) public nonReentrant {
        Vault memory vault = s_vaults[_vaultId];
        if (_period < vault.minPeriod) revert Vault__PeriodTooShort();
        if (!vault.isActive) revert Vault__InactiveVault();
        if (vault.asset == address(0)) revert Vault__InvalidAssetForDepositType();
        if (_amount <= 0) revert Vault__AmountTooLow();

        uint256 externalDeposit = 0;
        uint256 internalDeposit = 0;

        CoverLib.DepositParams[] memory depositParams = new CoverLib.DepositParams[](vault.pools.length);
        uint256[] memory internalDepositAmounts = new uint256[](vault.pools.length);
        for (uint256 i = 0; i < vault.pools.length; i++) {
            uint256 poolId = vault.pools[i].id;
            uint256 poolPercentage = vaultPercentageSplits[_vaultId][poolId];
            uint256 percentage_amount = (poolPercentage * _amount) / 100;
            uint256 poolExternalAmount = (vault.pools[i].investmentArmPercent * percentage_amount) / 100;
            uint256 internal_deposit_percentage = percentage_amount - poolExternalAmount;
            CoverLib.DepositParams memory depositParam = CoverLib.DepositParams({
                depositor: msg.sender,
                poolId: poolId,
                amount: percentage_amount,
                period: _period,
                pdt: CoverLib.DepositType.Vault,
                adt: vault.assetType,
                asset: vault.asset
            });

            depositParams[i] = depositParam;
            internalDepositAmounts[i] = internal_deposit_percentage;

            externalDeposit += poolExternalAmount;
            internalDeposit += internal_deposit_percentage;
        }

        IERC20(vault.asset).transferFrom(msg.sender, i_poolContractAddress, internaDeposit);
        try i_aavePool.supply(vault.asset, externalDepositAmount, msg.sender, s_referralCode) {}
        catch {
            revert Vault__AaveSupplyFailed();
        }

        uint256 totalDailyPayout = i_poolContract.registerVaultDeposits(depositParams, internalDepositAmounts);

        VaultDeposit memory userDeposit = VaultDeposit({
            lp: msg.sender,
            amount: totalAmount,
            vaultId: _vaultId,
            dailyPayout: totalDailyPayout,
            status: CoverLib.Status.Active,
            daysLeft: _period,
            startDate: block.timestamp,
            expiryDate: block.timestamp + (_period * 1 days),
            accruedPayout: 0,
            assetType: vault.assetType,
            asset: vault.asset
        });

        s_userVaultDeposits[msg.sender][_vaultId] = userDeposit;
        i_bqBTC.bqMint(msg.sender, internalDeposit);

        emit Deposited(msg.sender, _amount, vault.vaultName);
    }

    function vaultWithdraw(uint256 _vaultId) public nonReentrant {
        VaultDeposit memory userVaultDeposit = s_userVaultDeposits[msg.sender][_vaultId];
        if (userVaultDeposit.amount == 0) revert Vault__NoDepositFound();

        if (userVaultDeposit.status != CoverLib.Status.Active) {
            revert Vault__InactiveDeposit();
        }

        if (block.timestamp < userVaultDeposit.expiryDate) {
            revert Vault__DepositPeriodStillActive();
        }

        bqBTC.burn(msg.sender, userVaultDeposit.amount);
        CoverLib.Deposits[] memory userDeposits = new CoverLib.Deposits[](vault.pools.length);

        Vault memory vault = s_vaults[_vaultId];
        for (uint256 i = 0; i < vault.pools.length; i++) {
            uint256 poolId = vault.pools[i].id;
            if (userDeposit[i].status != CoverLib.Status.Active) {
                revert Vault__InactiveDeposit();
            }

            deposits[msg.sender][poolId][CoverLib.DepositType.Vault].status = CoverLib.Status.Due;
            CoverLib.Deposits memory userDeposit = deposits[msg.sender][poolId][CoverLib.DepositType.Vault];
            userDeposits[i] = userDeposit;
            deposits[msg.sender][poolId][CoverLib.DepositType.Vault].amount = 0;
        }

        userVaultDeposit.status = CoverLib.Status.Due;
        userVaultDeposit.amount = 0;
        userVaultDeposit.daysLeft = 0;

        i_poolContract.vaultWithdrawUpdate(userDeposits, vault.pools);

        emit Withdraw(msg.sender, userVaultDeposit.amount, vault.vaultName);
    }

    function getVault(uint256 vaultId) public view returns (Vault memory) {
        return s_vaults[vaultId];
    }

    function getVaultPools(uint256 vaultId) public view returns (CoverLib.Pool[] memory) {
        return s_vaults[vaultId].pools;
    }

    function getUserVaultPoolDeposits(uint256 vaultId, address user) public view returns (CoverLib.Deposits[] memory) {
        Vault memory vault = s_vaults[vaultId];
        CoverLib.Deposits[] memory vaultDeposits = new CoverLib.Deposits[](vault.pools.length);
        for (uint256 i = 0; i < vault.pools.length; i++) {
            uint256 poolId = vault.pools[i].id;
            vaultDeposits[i] = deposits[user][poolId][CoverLib.DepositType.Vault];
        }

        return vaultDeposits;
    }

    function getUserVaultDeposits(address user) public view returns (CoverLib.VaultDeposit[] memory) {
        uint256 resultCount = 0;
        for (uint256 i = 1; i <= vaultCount; i++) {
            if (s_userVaultDeposits[user][i].amount > 0) {
                resultCount++;
            }
        }

        CoverLib.VaultDeposit[] memory userVaultDeposits = new CoverLib.VaultDeposit[](resultCount);
        for (uint256 i = 1; i <= vaultCount; i++) {
            userVaultDeposits[i - 1] = s_userVaultDeposits[user][i];
        }

        return userVaultDeposits;
    }

    function getUserVaultDeposit(uint256 vaultId, address user) public view returns (VaultDeposit memory) {
        return s_userVaultDeposits[user][vaultId];
    }

    function getVaults() public view returns (Vault[] memory) {
        Vault[] memory allVaults = new Vault[](vaultCount);
        for (uint256 i = 1; i <= vaultCount; i++) {
            allVaults[i - 1] = s_vaults[i];
        }

        return allVaults;
    }

    function setGovernance(address _governance) external onlyOwner {
        if (s_governance != address(0)) revert Vault__GovernanceAlreadySet();
        if (_governance == address(0)) revert Vault__InvalidGovernanceAddress();

        s_governance = _governance;
        s_governanceContract = IGov(_governance);
    }

    function setCover(address _coverContract) external onlyOwner {
        if (coverContract != address(0)) revert Vault__CoverAlreadySet();
        if (_coverContract == address(0)) revert Vault__InvalidCoverAddress();

        ICoverContract = ICover(_coverContract);
        coverContract = _coverContract;
    }

    function setPool(address _poolContract) external onlyOwner {
        if (poolContract != address(0)) revert Vault__PoolAlreadySet();
        if (_poolContract == address(0)) revert Vault__InvalidPoolAddress();

        IPoolContract = IPool(_poolContract);
        poolContract = _poolContract;
    }

    function setPoolCanister(address _poolCanister) external onlyOwner {
        if (poolCanister != address(0)) revert Vault__PoolCanisterAlreadySet();
        if (_poolCanister == address(0)) {
            revert Vault__InvalidPoolCanisterAddress();
        }

        poolCanister = _poolCanister;
    }

    function updatePoolCanister(address _poolCanister) external onlyOwner {
        if (_poolCanister == address(0)) {
            revert Vault__InvalidPoolCanisterAddress();
        }
        poolCanister = _poolCanister;
    }

    function validateAndSetPools(
        Vault storage vault,
        uint256[] memory _poolIds,
        uint256[] memory poolPercentageSplit,
        CoverLib.AssetDepositType adt
    ) internal returns (uint256 percentageSplit, uint256 minPeriod) {
        minPeriod = 365;
        for (uint256 i = 0; i < _poolIds.length; i++) {
            CoverLib.Pool memory pool = IPoolContract.getPool(_poolIds[i]);
            if (pool.assetType != adt) revert Vault__IncompatibleAssetType();

            percentageSplit += poolPercentageSplit[i];
            vaultPercentageSplits[vault.id][_poolIds[i]] = poolPercentageSplit[i];
            vault.pools.push(pool);
            if (pool.minPeriod < minPeriod) {
                minPeriod = pool.minPeriod;
            }
        }
    }

    modifier onlyGovernance() {
        if (msg.sender != governance && msg.sender != initialOwner) {
            revert Vault__NotGovernance();
        }
        _;
    }

    modifier onlyCover() {
        if (msg.sender != coverContract && msg.sender != initialOwner) {
            revert Vault__NotCover();
        }
        _;
    }

    modifier onlyPool() {
        if (msg.sender != poolContract && msg.sender != initialOwner) {
            revert Vault__NotPool();
        }
        _;
    }

    modifier onlyPoolCanister() {
        if (msg.sender != poolCanister && msg.sender != initialOwner) {
            revert Vault__NotPoolCanister();
        }
        _;
    }
}
