// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "../errors/BQErrors.sol";

contract BqBTC is ERC20, Ownable {
    using SafeERC20 for IERC20;

    uint8 private _customDecimals;
    address public poolAddress;
    address public coverAddress;
    address public initialOwner;
    mapping(uint256 chainId => uint256 multiplier) public networkMultipliers;
    IERC20 public alternativeToken; // 0x6ce8da28e2f864420840cf74474eff5fd80e65b8
    address vaultContract;

    event Mint(
        address indexed account,
        uint256 amount,
        uint256 chainId,
        bool native
    );

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply,
        address _initialOwner,
        address _alternativeToken,
        uint256 _multiplier
    ) ERC20(name, symbol) Ownable(_initialOwner) {
        if (_multiplier <= 0 || _multiplier >= 1100) {
            revert BQ__InvalidMultiplier();
        }
        if (_alternativeToken == address(0)) {
            revert BQ__InvalidTokenAddress();
        }
        _customDecimals = decimals_;
        _mint(msg.sender, initialSupply);
        initialOwner = _initialOwner;
        alternativeToken = IERC20(_alternativeToken);
        networkMultipliers[block.chainid] = _multiplier;
    }

    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }

    function mint(address account, uint256 btcAmount) external payable {
        uint256 currentChainId = block.chainid;
        uint256 networkMultiplier = networkMultipliers[currentChainId];

        if (networkMultiplier <= 0) {
            revert BQ__NoNetworkMultiplier();
        }
        if (account == address(0)) {
            revert BQ__InvalidUserAddress();
        }

        bool nativeSent = msg.value > 0;
        bool btcSent = false;
        uint256 mintAmount;

        if (nativeSent) {
            mintAmount = (msg.value * networkMultiplier) / 1 ether;
        }

        if (!nativeSent) {
            mintAmount = (btcAmount * networkMultiplier) / 1 ether;
            if (btcAmount <= 0) {
                revert BQ__InvalidAmount();
            }
            alternativeToken.safeTransferFrom(
                msg.sender,
                address(this),
                btcAmount
            );
            btcSent = true;
        }

        if (!nativeSent && !btcSent) {
            revert BQ__InsufficientTokensSent();
        }

        _mint(account, mintAmount);

        emit Mint(account, mintAmount, currentChainId, nativeSent);
    }

    function burn(address account, uint256 amount) external {
        if (
            msg.sender != initialOwner &&
            msg.sender != poolAddress &&
            msg.sender != coverAddress
        ) {
            revert BQ__NotAuthorized();
        }

        _burn(account, amount);
    }

    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
        return super.balanceOf(account);
    }

    function bqMint(address account, uint256 amount) external onlyBQContracts {
        _mint(account, amount);
    }

    function newMint(address account) external onlyBQContracts {
        uint256 amount = 1 * 1000000000000000000;
        _mint(account, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        return super.approve(spender, amount);
    }

    function setContracts(
        address pool,
        address cover,
        address vault
    ) public onlyOwner {
        if (pool == address(0) || cover == address(0) || vault == address(0)) {
            revert BQ__InvalidAddress();
        }

        if (
            poolAddress != address(0) ||
            coverAddress != address(0) ||
            vaultContract != address(0)
        ) {
            revert BQ__PoolAlreadySet();
        }

        coverAddress = cover;
        poolAddress = pool;
        vaultContract = vault;
    }

    function setNetworkMultiplier(
        uint256 chainId,
        uint256 multiplier
    ) external onlyOwner {
        if (multiplier <= 0 || multiplier >= 1100) {
            revert BQ__InvalidMultiplier();
        }

        networkMultipliers[chainId] = multiplier;
    }

    modifier onlyBQContracts() {
        if (
            msg.sender != coverAddress &&
            msg.sender != initialOwner &&
            msg.sender != vaultContract &&
            msg.sender != poolAddress
        ) {
            revert BQ__NotGovernance();
        }

        _;
    }
}
