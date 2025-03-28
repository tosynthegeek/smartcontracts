// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "aave-v3-core/contracts/interfaces/IPool.sol";
import "./CoverLib.sol";
import "./errors/PoolErrors.sol";

interface ICover {
    function updateMaxAmount(CoverLib.Cover[]) external;
    function getDepositClaimableDays(address user, uint256 _poolId) external view returns (uint256);
    function getLastClaimTime(address user, uint256 _poolId) external view returns (uint256);
}

interface IVault {
    function getVault(uint256 vaultId) external view returns (CoverLib.Vault memory);
    function getUserVaultDeposit(uint256 vaultId, address user) external view returns (CoverLib.VaultDeposit memory);
    function setUserVaultDepositToZero(uint256 vaultId, address user) external;
}

interface IbqBTC {
    function bqMint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IGov {
    function getProposalDetails(uint256 _proposalId) external returns (CoverLib.Proposal memory);
    function updateProposalStatusToClaimed(uint256 proposalId) external;
    function setUserVaultDepositToZero(uint256 vaultId, address user) external;
}

contract InsurancePool is ReentrancyGuard, Ownable {
    using CoverLib for *;

    mapping(address => mapping(uint256 => mapping(CoverLib.DepositType => CoverLib.Deposits))) private s_deposits;
    mapping(uint256 => CoverLib.Cover[]) private s_poolToCovers;
    mapping(uint256 => CoverLib.Pool) private s_pools;
    mapping(address => uint256) private s_participation;
    address[] private s_participants;
    address private s_governance;
    address private s_vaultContractAddress;
    address private s_coverContractAddress;
    IGov private s_governanceContract;
    IVault private s_vaultContract;
    ICover private s_coverContract;

    uint256 private s_poolCount;
    uint16 private s_referralCode = 0;

    IbqBTC private immutable i_bqBTC;
    IPool public immutable i_aavePool;
    address public immutable i_bqBTCAddress;
    address private immutable i_initialOwner;

    event Deposited(address indexed user, uint256 amount, string pool);
    event Withdraw(address indexed user, uint256 amount, string pool);
    event ClaimPaid(address indexed recipient, string pool, uint256 amount);
    event PoolCreated(uint256 indexed id, string poolName);
    event PoolUpdated(uint256 indexed poolId, uint256 apy, uint256 _minPeriod);
    event ClaimAttempt(uint256, uint256, address);

    constructor(address _initialOwner, address bq, address _aavePoolAdress) Ownable(_initialOwner) {
        i_initialOwner = _initialOwner;
        i_bqBTC = IbqBTC(bq);
        i_bqBTCAddress = bq;
        i_aavePool = IPool(_aavePoolAdress);
    }

    function createPool(CoverLib.PoolParams memory params) public onlyOwner {
        if (params.adt != CoverLib.AssetDepositType.Native && params.asset == address(0)) {
            revert Pool__InvalidAssetForDeposit();
        }

        s_poolCount += 1;
        CoverLib.Pool storage newPool = s_pools[params.poolId];
        newPool.id = params.poolId;
        newPool.poolName = params.poolName;
        newPool.apy = params.apy;
        newPool.totalUnit = 0;
        newPool.minPeriod = params.minPeriod;
        newPool.tvl = 0;
        newPool.coverUnits = 0;
        newPool.baseValue = 0;
        newPool.isActive = true;
        newPool.riskType = params.riskType;
        newPool.investmentArmPercent = params.investmentArm;
        newPool.leverage = params.leverage;
        newPool.percentageSplitBalance = 100 - params.investmentArm;
        newPool.assetType = params.adt;
        newPool.asset = params.asset;

        emit PoolCreated(params.poolId, params.poolName);
    }

    function updatePool(uint256 _poolId, uint256 _apy, uint256 _minPeriod) public onlyOwner {
        if (!s_pools[_poolId].isActive) {
            revert Pool__PoolInactiveOrNonExistent();
        }
        if (_apy <= 0) {
            revert Pool__InvalidAPY();
        }
        if (_minPeriod <= 0) {
            revert Pool__InvalidMinPeriod();
        }

        s_pools[_poolId].apy = _apy;
        s_pools[_poolId].minPeriod = _minPeriod;

        emit PoolUpdated(_poolId, _apy, _minPeriod);
    }

    function reducePercentageSplit(uint256 _poolId, uint256 __poolPercentageSplit) external onlyCover {
        s_pools[_poolId].percentageSplitBalance -= __poolPercentageSplit;
    }

    function increasePercentageSplit(uint256 _poolId, uint256 __poolPercentageSplit) external onlyCover {
        s_pools[_poolId].percentageSplitBalance += __poolPercentageSplit;
    }

    function deactivatePool(uint256 _poolId) public onlyOwner {
        if (!s_pools[_poolId].isActive) {
            revert Pool__PoolInactiveOrNonExistent();
        }
        s_pools[_poolId].isActive = false;
    }

    function updatePoolCovers(uint256 _poolId, CoverLib.Cover memory _cover) external onlyCover {
        uint256 poolCoverLength = s_poolToCovers[_poolId].length;
        for (uint256 i = 0; i < poolCoverLength; i++) {
            if (s_poolToCovers[_poolId][i].id == _cover.id) {
                s_poolToCovers[_poolId][i] = _cover;
                break;
            }
        }
    }

    function deposit(CoverLib.DepositParams calldata _depositParam) public nonReentrant {
        CoverLib.Pool memory selectedPool = s_pools[_depositParam.poolId];

        if (!selectedPool.isActive) {
            revert Pool__PoolInactiveOrNonExistent();
        }

        if (selectedPool.assetType != _depositParam.adt) {
            revert Pool__InvalidDepositType();
        }

        if (_depositParam.period < selectedPool.minPeriod) {
            revert Pool__PeriodTooShort();
        }

        if (selectedPool.asset != _depositParam.asset) {
            revert Pool__InvalidPoolAsset();
        }

        if (s_deposits[_depositParam.depositor][_depositParam.poolId][_depositParam.pdt].amount > 0) {
            revert Pool__AlreadyDeposited();
        }

        if (_depositParam.amount <= 0) {
            revert Pool__InvalidAmount();
        }

        uint256 externalDepositAmount = (selectedPool.investmentArmPercent * _depositParam.amount) / 100;
        uint256 internalDepositAmount = _depositParam.amount - externalDepositAmount;

        IERC20(_depositParam.asset).transferFrom(_depositParam.depositor, address(this), internalDepositAmount);
        try i_aavePool.supply(deposit.asset, externalDepositAmount, _depositParam.depositor, s_referralCode) {}
        catch {
            revert Pool__AaveSupplyFailed();
        }

        registerDeposit(_depositParam, internalDepositAmount);

        if (s_participation[_depositParam.depositor] == 0) {
            s_participants.push(_depositParam.depositor);
        }

        s_participation[_depositParam.depositor] += 1;
        i_bqBTC.bqMint(_depositParam.depositor, internalDepositAmount);

        emit Deposited(_depositParam.depositor, _depositParam.amount, selectedPool.poolName);
    }

    // function updatePoolCoverValues(uint256 _poolid) public onlyVaultOrPool {
    //     CoverLib.Cover[] calldata poolCovers = getPoolCovers(_poolId);
    //     s_coverContract.updateMaxAmount(poolCovers);
    // }

    function poolWithdraw(uint256 _poolId) public nonReentrant {
        CoverLib.Pool memory selectedPool = s_pools[_poolId];
        CoverLib.Deposits memory userDeposit = s_deposits[msg.sender][_poolId][CoverLib.DepositType.Normal];

        if (userDeposit.amount == 0) {
            revert Pool__NoPoolDepositsFound();
        }

        if (userDeposit.status != CoverLib.Status.Active) {
            revert Pool__DepositNotActive();
        }

        if (block.timestamp < userDeposit.expiryDate) {
            revert Pool__DepositPeriodStillActive();
        }

        i_bqBTC.burn(msg.sender, internaDeposit);

        registerWithdrawal(userDeposit, selectedPool);

        IERC20(selectedPool.asset).transfer(msg.sender, internalDeposit);
        i_aavePool.withdraw(selectedPool.asset, externalDeposit, msg.sender);

        emit Withdraw(msg.sender, userDeposit.amount, selectedPool.poolName);
    }

    function vaultWithdrawUpdate(CoverLib.Deposits[] calldata _deposits, CoverLib.Pool[] calldata _pools)
        external
        nonReentrant
        onlyVault
    {
        if (_deposits.length != _pools.length) {
            revert Pool__MismatchedDepositsAndPools();
        }

        uint256 totalInternalAmount = 0;
        uint256 totalExternalAmount = 0;

        for (uint256 i = 0; i < _deposits.length; i++) {
            CoverLib.Pool memory selectedPool = _pools[i];
            CoverLib.Deposits memory userDeposit = _deposits[i];

            if (userDeposit.amount == 0) {
                revert Pool__NoPoolDepositsFound();
            }

            if (userDeposit.status != CoverLib.Status.Due) {
                revert Pool__DepositNotActive();
            }

            if (block.timestamp < userDeposit.expiryDate) {
                revert Pool__DepositPeriodStillActive();
            }

            (uint256 internalDeposit, uint256 externalDeposit) = registerWithdrawal(userDeposit, selectedPool);

            totalInternalAmount += internalDeposit;
            totalExternalAmount += externalDeposit;
        }

        IERC20(selectedPool.asset).transfer(userDeposit.lp, totalInternalAmount);
        i_aavePool.withdraw(selectedPool.asset, totalExternalAmount, userDeposit.lp);

        emit Withdraw(depositor, userDeposit.amount, selectedPool.poolName);
    }

    // Revisit the necessity of this function
    function finalizeProposalClaim(uint256 _proposalId, address user) public nonReentrant onlyPoolCanister {
        CoverLib.Proposal memory proposal = s_governanceContract.getProposalDetails(_proposalId);
        CoverLib.ProposalParams memory proposalParam = proposal.proposalParam;
        CoverLib.Pool storage pool = s_pools[proposalParam.poolId];

        pool.tcp += proposalParam.claimAmount;
        pool.tvl -= proposalParam.claimAmount;
        CoverLib.Cover[] memory poolCovers = getPoolCovers(proposalParam.poolId);
        for (uint256 i = 0; i < poolCovers.length; i++) {
            s_coverContract.updateMaxAmount(poolCovers[i].id);
        }

        s_governanceContract.updateProposalStatusToClaimed(_proposalId);

        emit ClaimPaid(user, pool.poolName, proposalParam.claimAmount);
    }

    function registerVaultDeposits(
        CoverLib.DepositParams[] calldata _deposits,
        uint256[] calldata internalDepositAmounts
    ) external nonReentrant onlyVault returns (uint256) {
        if (_deposits.length != internalDepositAmounts.length) {
            revert Vault__MismatchedDepositsAndAmounts();
        }

        uint256 totalDailyPayout = 0;

        for (uint256 i = 0; i < _deposits.length; i++) {
            uint256 dailyPayout = registerDeposit(_deposits[i], internalDepositAmounts[i]);
            totalDailyPayout += dailyPayout;
        }

        return totalDailyPayout;
    }

    function addPoolCover(uint256 _poolId, CoverLib.Cover memory _cover) external onlyCover {
        s_poolToCovers[_poolId].push(_cover);
    }

    function getPool(uint256 _poolId) public view returns (CoverLib.Pool memory) {
        return s_pools[_poolId];
    }

    function getAllPools() public view returns (CoverLib.Pool[] memory) {
        CoverLib.Pool[] memory result = new CoverLib.Pool[](s_poolCount);
        for (uint256 i = 1; i <= s_poolCount; i++) {
            CoverLib.Pool memory pool = s_pools[i];
            result[i - 1] = CoverLib.Pool({
                id: i,
                poolName: pool.poolName,
                riskType: pool.riskType,
                apy: pool.apy,
                minPeriod: pool.minPeriod,
                totalUnit: pool.totalUnit,
                tvl: pool.tvl,
                baseValue: pool.baseValue,
                coverUnits: pool.coverUnits,
                tcp: pool.tcp,
                isActive: pool.isActive,
                percentageSplitBalance: pool.percentageSplitBalance,
                investmentArmPercent: pool.investmentArmPercent,
                leverage: pool.leverage,
                asset: pool.asset,
                assetType: pool.assetType
            });
        }
        return result;
    }

    function getPoolCovers(uint256 _poolId) public view returns (CoverLib.Cover[] memory) {
        return s_poolToCovers[_poolId];
    }

    function getPoolsByAddress(address _userAddress) public view returns (CoverLib.PoolInfo[] memory) {
        uint256 resultCount = 0;
        for (uint256 i = 1; i <= s_poolCount; i++) {
            if (s_deposits[_userAddress][i][CoverLib.DepositType.Normal].amount > 0) {
                resultCount++;
            }
        }

        CoverLib.PoolInfo[] memory result = new CoverLib.PoolInfo[](resultCount);

        if (resultCount == 0) {
            revert Pool__NoPoolDepositsFound();
        }

        uint256 resultIndex = 0;

        for (uint256 i = 1; i <= s_poolCount; i++) {
            if (s_deposits[_userAddress][i][CoverLib.DepositType.Normal].amount > 0) {
                if (resultIndex >= resultCount) {
                    revert Pool__IndexOutOfBounds();
                }

                CoverLib.Pool memory pool = s_pools[i];
                CoverLib.Deposits memory userDeposit = s_deposits[_userAddress][i][CoverLib.DepositType.Normal];
                uint256 claimableDays = s_coverContract.getDepositClaimableDays(_userAddress, i);
                uint256 accruedPayout = userDeposit.dailyPayout * claimableDays;
                result[resultIndex++] = CoverLib.PoolInfo({
                    poolName: pool.poolName,
                    poolId: i,
                    dailyPayout: s_deposits[_userAddress][i][CoverLib.DepositType.Normal].dailyPayout,
                    depositAmount: s_deposits[_userAddress][i][CoverLib.DepositType.Normal].amount,
                    apy: pool.apy,
                    minPeriod: pool.minPeriod,
                    totalUnit: pool.totalUnit,
                    tcp: pool.tcp,
                    isActive: pool.isActive,
                    accruedPayout: accruedPayout
                });
            }
        }
        return result;
    }

    function getUserPoolDeposit(uint256 _poolId, address _user) public view returns (CoverLib.Deposits memory) {
        CoverLib.Deposits memory userDeposit = s_deposits[_user][_poolId][CoverLib.DepositType.Normal];
        uint256 claimTime = s_coverContract.getLastClaimTime(_user, _poolId);
        uint256 lastClaimTime;
        if (claimTime == 0) {
            lastClaimTime = userDeposit.startDate;
        } else {
            lastClaimTime = claimTime;
        }
        uint256 currentTime = block.timestamp;
        if (currentTime > userDeposit.expiryDate) {
            currentTime = userDeposit.expiryDate;
        }
        uint256 claimableDays = (currentTime - lastClaimTime) / 1 days;
        userDeposit.accruedPayout = userDeposit.dailyPayout * claimableDays;
        if (userDeposit.expiryDate <= block.timestamp) {
            userDeposit.daysLeft = 0;
        } else {
            uint256 timeLeft = userDeposit.expiryDate - block.timestamp;
            userDeposit.daysLeft = (timeLeft + 1 days - 1) / 1 days;
        }
        return userDeposit;
    }

    function getUserGenericDeposit(uint256 _poolId, address _user, CoverLib.DepositType pdt)
        public
        view
        returns (CoverLib.GenericDepositDetails memory)
    {
        CoverLib.Deposits memory userDeposit = s_deposits[_user][_poolId][pdt];
        CoverLib.Pool memory pool = s_pools[_poolId];
        uint256 claimTime = s_coverContract.getLastClaimTime(_user, _poolId);
        uint256 lastClaimTime;
        if (claimTime == 0) {
            lastClaimTime = userDeposit.startDate;
        } else {
            lastClaimTime = claimTime;
        }
        uint256 currentTime = block.timestamp;
        if (currentTime > userDeposit.expiryDate) {
            currentTime = userDeposit.expiryDate;
        }
        uint256 claimableDays = (currentTime - lastClaimTime) / 1 days;
        userDeposit.accruedPayout = userDeposit.dailyPayout * claimableDays;
        if (userDeposit.expiryDate <= block.timestamp) {
            userDeposit.daysLeft = 0;
        } else {
            uint256 timeLeft = userDeposit.expiryDate - block.timestamp;
            userDeposit.daysLeft = (timeLeft + 1 days - 1) / 1 days;
        }

        return CoverLib.GenericDepositDetails({
            lp: userDeposit.lp,
            amount: userDeposit.amount,
            poolId: userDeposit.poolId,
            dailyPayout: userDeposit.dailyPayout,
            status: userDeposit.status,
            daysLeft: userDeposit.daysLeft,
            startDate: userDeposit.startDate,
            expiryDate: userDeposit.expiryDate,
            accruedPayout: userDeposit.accruedPayout,
            pdt: userDeposit.pdt,
            adt: pool.assetType,
            asset: pool.asset
        });
    }

    function setUserDepositToZero(uint256 poolId, address user, CoverLib.DepositType pdt)
        public
        nonReentrant
        onlyPoolCanister
    {
        s_deposits[user][poolId][pdt].amount = 0;
    }

    function getPoolTVL(uint256 _poolId) public view returns (uint256) {
        return s_pools[_poolId].tvl;
    }

    function poolActive(uint256 poolId) public view returns (bool) {
        CoverLib.Pool storage pool = s_pools[poolId];
        return pool.isActive;
    }

    function getAllParticipants() public view returns (address[] memory) {
        return s_participants;
    }

    function getUserParticipation(address user) public view returns (uint256) {
        return s_participation[user];
    }

    function setReferralCode(uint16 _referralCode) public onlyOwner {
        s_referralCode = _referralCode;
    }

    function setGovernance(address _governance) external onlyOwner {
        if (s_governanceContractAddress != address(0)) revert Pool__GovernanceAlreadySet();
        if (_governance == address(0)) revert Pool__InvalidGovernanceAddress();

        s_governanceContractAddress = _governance;
        s_governanceContract = IGov(_governance);
    }

    function setCover(address _coverContract) external onlyOwner {
        if (s_coverContractAdress != address(0)) revert Pool__CoverAlreadySet();
        if (_coverContract == address(0)) revert Pool__InvalidCoverAddress();

        s_coverContract = ICover(_coverContract);
        s_coverContractAddress = _coverContract;
    }

    function setVault(address _vaultContract) external onlyOwner {
        if (s_vaultContractAddress != address(0)) revert Pool__VaultAlreadySet();
        if (_vaultContract == address(0)) revert Pool__InvalidVaultAddress();

        s_vaultContract = IVault(_vaultContract);
        s_vaultContractAddress = _vaultContract;
    }

    // INTERNAL FUNCTIONS

    function registerDeposit(CoverLib.DepositParams calldata _depositParam, uint256 internalDepositAmount)
        internal
        nonReentrant
        onlyVaultOrPool
        returns (uint256)
    {
        CoverLib.Pool memory selectedPool = s_pools[depositParam.poolId];

        s_pools[depositParam.poolId].totalUnit.totalUnit += depositParam.amount;
        s_pools[depositParam.poolId].totalUnit.tvl += depositParam.amount;
        s_pools[depositParam.poolId].totalUnit.baseValue += internalDepositAmount;
        s_pools[depositParam.poolId].totalUnit.coverUnits += (internalDepositAmount * selectedPool.leverage);

        uint256 dailyPayout = (_depositParam.amount * selectedPool.apy) / 100 / 365;
        s_deposits[_depositParam.depositor][_depositParam.poolId][_depositParam.pdt] = CoverLib.Deposits({
            lp: _depositParam.depositor,
            amount: _depositParam.amount,
            poolId: _depositParam.poolId,
            dailyPayout: dailyPayout,
            status: CoverLib.Status.Active,
            daysLeft: _depositParam.period,
            startDate: block.timestamp,
            expiryDate: block.timestamp + (_depositParam.period * 1 seconds), // ✅ Use seconds for testing, change to days for production
            accruedPayout: 0,
            pdt: _depositParam.pdt
        });

        s_coverContract.updateMaxAmount(_depositParam.poolId);

        return dailyPayout;
    }

    function registerWithdrawal(CoverLib.Deposits calldata userDeposit, CoverLib.Pool calldata selectedPool)
        internal
        nonReentrant
        onlyVaultOrPool
        returns (uint256, uint256)
    {
        uint256 externalDeposit = (selectedPool.investmentArmPercent * userDeposit.amount) / 100;
        uint256 internalDeposit = userDeposit.amount - externalDeposit;
        uint256 _poolId = pool.id;

        s_deposits[msg.sender][_poolId][userDeposit.pdt].status = CoverLib.Status.Withdrawn;
        s_pools[_poolId].tvl -= userDeposit.amount;
        s_pools[_poolId].baseValue -= internalDeposit;
        s_pools[_poolId].coverUnits = s_pools[_poolId].baseValue * selectedPool.leverage;
        s_deposits[msg.sender][_poolId][CoverLib.DepositType.Normal].amount = 0;

        CoverLib.Cover[] memory poolCovers = getPoolCovers(_poolId);
        s_coverContract.updateMaxAmount(_poolId);

        return (internalDeposit, externalDeposit);
    }

    modifier onlyGovernance() {
        if (msg.sender != s_governanceContractAddress && msg.sender != i_initialOwner) {
            revert Pool__NotGovernance();
        }
        _;
    }

    modifier onlyCover() {
        if (msg.sender != s_coverContractAddress && msg.sender != i_initialOwner) {
            revert Pool__NotCover();
        }
        _;
    }

    modifier onlyVault() {
        if (msg.sender != s_vaultContractAddress && msg.sender != i_initialOwner) {
            revert Pool__NotVault();
        }
        _;
    }

    modifier onlyVaultOrPool() {
        require(msg.sender == address(vault) || msg.sender == address(this), "Not authorized");
        _;
    }
}
