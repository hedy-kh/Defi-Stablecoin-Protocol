// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DecentralizedCoin} from "src/DecStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import{OracleLib} from"./Library/OracleLib.sol";
contract DSCEngine is ReentrancyGuard {
    error DSEN__zero();
    error DSEN__MisMatchedLength();
    error DSEN_NotAllowedToken();
    error DSEN__TransferFailed();
    error DSEN__BreakHealthFactor(uint256 HealthFactor);
    error DSEN__MintFailed();
    error DSEN__HealthFactorOk();
    error DSEN__HealthFactorNotImproved();
    using OracleLib for AggregatorV3Interface;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedCoin private immutable i_dsc;
    uint256 private constant Precision = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemdFrom, address indexed Redeemto, address indexed token, uint256 amount
    );

    modifier AboveZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSEN__zero();
        }
        _;
    }

    modifier IsAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSEN_NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSEN__MisMatchedLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedCoin(dscAddress);
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCtoMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        MintDsc(amountDSCtoMint);
    }

    function depositCollateral(address _tokenAddress, uint256 _amountCollateral)
        public
        AboveZero(_amountCollateral)
        IsAllowedToken(_tokenAddress)
        nonReentrant
    {
        //update state and emit event
        s_collateralDeposited[msg.sender][_tokenAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenAddress, _amountCollateral);
        bool success = IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSEN__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface PriceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = PriceFeed.stalePriceCheck();
        return (usdAmount * 1e18) / (uint256(price) * 1e10);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountcollateral)
        public
        AboveZero(amountcollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountcollateral;
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountcollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountcollateral)
        private
        AboveZero(amountcollateral)
    {
        //s_collateralDeposited[from][tokenCollateralAddress] -= amountcollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountcollateral);
        bool sucess = IERC20(tokenCollateralAddress).transfer(to, amountcollateral);
        if (!sucess) {
            revert DSEN__TransferFailed();
        }
    }

    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountcollateral, uint256 amoutnDSCToBurn)
        external
    {
        burnDsc(amoutnDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountcollateral);
    }

    function MintDsc(uint256 amountToMint) public AboveZero(amountToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSEN__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public AboveZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        AboveZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= 1e18) {
            revert DSEN__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * 10) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= 1e18) {
            revert DSEN__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSEN__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function getHealthyFactor() external {}

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }

    function getCalculateHealthFactor(uint256 totalDscMinted, uint256 collateralValue) public view returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValue);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 UserhelathFactor = _healthFactor(user);
        if (UserhelathFactor < 1e18) {
            revert DSEN__BreakHealthFactor(UserhelathFactor);
        }
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralInUsd += getUsdValue(token, amount);
        }
        return totalCollateralInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheck();
        return ((uint256(price) * 1e10) * amount) / Precision;
    }

    function getAccountInfo(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralDeposited(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getCollateralTokens(uint256 index) external view returns (address) {
        return s_collateralTokens[index];
    }

    function getTokenCollateral() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function addCollateralToken(address token) external {
        s_collateralTokens.push(token);
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
