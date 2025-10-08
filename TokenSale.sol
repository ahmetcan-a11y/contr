// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ProjectToken.sol";

/**
 * @title TokenSale
 * @dev Token sale contract that accepts USDT and mints project tokens
 * @notice Exchange rate: 0.2 USDT = 1 Project Token
 */
contract TokenSale is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant TOKEN_DECIMALS = 18;
    uint256 public constant USDT_DECIMALS = 6;

    IERC20 public immutable usdtToken;
    ProjectToken public immutable projectToken;
    address public immutable destinationAddress; // Address to receive all payments
    uint256 public immutable tokenPrice; // Price per token in USDT (with 6 decimals)
    uint256 public immutable totalTokensForSale; // Total tokens available for sale

    uint256 public totalUsdtRaised;
    uint256 public totalTokensSold;
    uint256 public saleStartTime;
    uint256 public saleEndTime;
    uint256 public minPurchaseAmount; // Minimum USDT amount
    uint256 public maxTokensPerWallet; // Maximum tokens per wallet (0.50% of total)

    mapping(address => uint256) public userPurchases; // Track user purchases in USDT
    mapping(address => uint256) public userTokensPurchased; // Track user token purchases

    event TokensPurchased(
        address indexed buyer,
        uint256 usdtAmount,
        uint256 tokenAmount
    );
    event SaleTimeUpdated(uint256 startTime, uint256 endTime);
    event PurchaseLimitsUpdated(uint256 minAmount, uint256 maxAmount);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    error SaleNotActive();
    error InsufficientUsdtAmount();
    error ExceedsMaxPurchase();
    error BelowMinPurchase();
    error InsufficientTokenSupply();
    error ExceedsMaxTokensPerWallet();
    error InvalidTimeRange();
    error ZeroAddress();
    error ZeroAmount();
    error ProjectTokenPaused();
    error ProjectTokenMaxSupplyExceeded();

    /**
     * @dev Constructor
     * @param _usdtToken Address of the USDT token contract
     * @param _projectToken Address of the project token contract
     * @param _destinationAddress Address to receive all payments (USDT, ETH, tokens)
     * @param _tokenPrice Price per token in USDT (with 6 decimals)
     * @param _totalTokensForSale Total tokens available for sale
     * @param _saleStartTime Start time of the token sale
     * @param _saleEndTime End time of the token sale
     * @param _minPurchaseAmount Minimum purchase amount in USDT
     */
    constructor(
        address _usdtToken,
        address _projectToken,
        address _destinationAddress,
        uint256 _tokenPrice,
        uint256 _totalTokensForSale,
        uint256 _saleStartTime,
        uint256 _saleEndTime,
        uint256 _minPurchaseAmount,
        uint256 _maxTokensPerWallet
    ) {
        if (_usdtToken == address(0) || _projectToken == address(0) || _destinationAddress == address(0)) {
            revert ZeroAddress();
        }
        if (_tokenPrice == 0 || _totalTokensForSale == 0 || _maxTokensPerWallet == 0) {
            revert ZeroAmount();
        }
        if (_saleStartTime >= _saleEndTime || _saleStartTime < block.timestamp) {
            revert InvalidTimeRange();
        }
        if (_minPurchaseAmount == 0) {
            revert InvalidTimeRange();
        }

        usdtToken = IERC20(_usdtToken);
        projectToken = ProjectToken(_projectToken);
        destinationAddress = _destinationAddress;
        tokenPrice = _tokenPrice;
        totalTokensForSale = _totalTokensForSale;
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        minPurchaseAmount = _minPurchaseAmount;
        maxTokensPerWallet = _maxTokensPerWallet;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @dev Purchase tokens with USDT
     * @param usdtAmount Amount of USDT to spend
     */
    function purchaseTokens(uint256 usdtAmount) external nonReentrant whenNotPaused {
        if (!isSaleActive()) {
            revert SaleNotActive();
        }
        if (usdtAmount == 0) {
            revert ZeroAmount();
        }
        if (usdtAmount < minPurchaseAmount) {
            revert BelowMinPurchase();
        }

        // Calculate token amount based on configurable price
        // tokenAmount = usdtAmount * 10^TOKEN_DECIMALS / tokenPrice
        uint256 tokenAmount = (usdtAmount * (10**TOKEN_DECIMALS)) / tokenPrice;
        
        // Check if enough tokens are available for sale
        if (totalTokensSold + tokenAmount > totalTokensForSale) {
            revert InsufficientTokenSupply();
        }
        
        // Check if user would exceed maximum tokens per wallet limit
        if (userTokensPurchased[msg.sender] + tokenAmount > maxTokensPerWallet) {
            revert ExceedsMaxTokensPerWallet();
        }

        // This prevents users from losing USDT if minting fails
        if (projectToken.paused()) {
            revert ProjectTokenPaused();
        }
        
        // Check if minting would exceed max supply
        if (projectToken.totalSupply() + tokenAmount > projectToken.MAX_SUPPLY()) {
            revert ProjectTokenMaxSupplyExceeded();
        }

        // Transfer USDT from buyer directly to destination address
        usdtToken.safeTransferFrom(msg.sender, destinationAddress, usdtAmount);

        // Mint tokens to buyer
        projectToken.mint(msg.sender, tokenAmount);

        // Update tracking variables
        totalUsdtRaised += usdtAmount;
        totalTokensSold += tokenAmount;
        userPurchases[msg.sender] += usdtAmount;
        userTokensPurchased[msg.sender] += tokenAmount;

        emit TokensPurchased(msg.sender, usdtAmount, tokenAmount);
    }

    /**
     * @dev Calculate token amount for given USDT amount
     * @param usdtAmount Amount of USDT
     * @return tokenAmount Amount of tokens that can be purchased
     */
    function calculateTokenAmount(uint256 usdtAmount) external view returns (uint256 tokenAmount) {
        return (usdtAmount * (10**TOKEN_DECIMALS)) / tokenPrice;
    }

    /**
     * @dev Calculate USDT amount for given token amount
     * @param tokenAmount Amount of tokens
     * @return usdtAmount Amount of USDT required
     */
    function calculateUsdtAmount(uint256 tokenAmount) external view returns (uint256 usdtAmount) {
        return (tokenAmount * tokenPrice) / (10**TOKEN_DECIMALS);
    }

    /**
     * @dev Check if sale is currently active
     * @return bool True if sale is active
     */
    function isSaleActive() public view returns (bool) {
        return block.timestamp >= saleStartTime && block.timestamp <= saleEndTime;
    }



    /**
     * @dev Update sale time range
     * @param _saleStartTime New start time
     * @param _saleEndTime New end time
     */
    function updateSaleTime(
        uint256 _saleStartTime,
        uint256 _saleEndTime
    ) external onlyRole(ADMIN_ROLE) {
        if (_saleStartTime >= _saleEndTime) {
            revert InvalidTimeRange();
        }

        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        emit SaleTimeUpdated(_saleStartTime, _saleEndTime);
    }

    /**
     * @dev Update purchase limits
     * @param _minPurchaseAmount New minimum purchase amount
     */
    function updatePurchaseLimits(
        uint256 _minPurchaseAmount,
        uint256 _maxTokensPerWallet
    ) external onlyRole(ADMIN_ROLE) {
        if (_minPurchaseAmount == 0) {
            revert InvalidTimeRange();
        }
        if (_maxTokensPerWallet == 0) {
            revert ZeroAmount();
        }

        minPurchaseAmount = _minPurchaseAmount;
        maxTokensPerWallet = _maxTokensPerWallet;
        emit PurchaseLimitsUpdated(_minPurchaseAmount, _maxTokensPerWallet);
    }

    /**
     * @dev Receive function to automatically forward ETH to destination address
     */
    receive() external payable {
        if (msg.value > 0) {
            (bool success, ) = destinationAddress.call{value: msg.value}("");
            require(success, "ETH transfer failed");
        }
    }

    /**
     * @dev Fallback function to automatically forward ETH to destination address
     */
    fallback() external payable {
        if (msg.value > 0) {
            (bool success, ) = destinationAddress.call{value: msg.value}("");
            require(success, "ETH transfer failed");
        }
    }

    /**
     * @dev Sweep any ERC20 tokens sent to this contract to destination address
     * @param token Address of the token to sweep
     */
    function sweepTokens(address token) external {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        
        if (balance > 0) {
            tokenContract.safeTransfer(destinationAddress, balance);
        }
    }

    /**
     * @dev Emergency withdraw any ERC20 token
     * @param token Address of the token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(token).safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(token, amount);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Get contract information
     * @return saleActive Whether sale is currently active
     * @return usdtRaised Total USDT raised
     * @return tokensSold Total tokens sold
     * @return remainingTokens Remaining tokens available for sale
     * @return tokenPriceUsdt Price per token in USDT
     * @return totalForSale Total tokens available for sale
     * @return maxTokensPerWalletLimit Maximum tokens per wallet (1% of total)
     */
    function getSaleInfo() external view returns (
        bool saleActive,
        uint256 usdtRaised,
        uint256 tokensSold,
        uint256 remainingTokens,
        uint256 tokenPriceUsdt,
        uint256 totalForSale,
        uint256 maxTokensPerWalletLimit
    ) {
        return (
            isSaleActive(),
            totalUsdtRaised,
            totalTokensSold,
            totalTokensForSale - totalTokensSold,
            tokenPrice,
            totalTokensForSale,
            maxTokensPerWallet
        );
    }

    /**
     * @dev Get user purchase information
     * @param user Address of the user
     * @return usdtSpent Total USDT spent by user
     * @return tokensReceived Total tokens received by user
     * @return remainingTokenLimit Remaining tokens user can purchase
     */
    function getUserInfo(address user) external view returns (
        uint256 usdtSpent,
        uint256 tokensReceived,
        uint256 remainingTokenLimit
    ) {
        usdtSpent = userPurchases[user];
        tokensReceived = userTokensPurchased[user];
        remainingTokenLimit = maxTokensPerWallet > tokensReceived ? 
            maxTokensPerWallet - tokensReceived : 0;
    }
}
