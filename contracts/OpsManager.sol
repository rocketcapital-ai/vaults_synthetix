//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Types.sol";
import "./Vault.sol";
import "../interfaces/IPerpsV2MarketConsolidated.sol";
import "../interfaces/IPerpsV2MarketSettings.sol";
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/security/ReentrancyGuard.sol";
import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControl.sol';

contract OpsManager is ReentrancyGuard, AccessControl, Types {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public feeCollector;
    uint256 public onboardingFeePercentage;
    uint256 public offboardingFeePercentage;

    uint256 public maxProcessing;
    uint256 public maxOrderValue;
    uint256 public orderEps;
    uint256 public fillPriceBuffer;
    uint256 public keeperFeeFactor;

    uint256 public minDeposit;
    uint256 public minShares;

    uint256 public portfolioRotationStartTimestamp;
    uint256 public portfolioRotationEndTimestamp;
    uint256 public processStartTimestamp;

    mapping (address => Request) public pendingDepositRequests;
    mapping (address => Request) public pendingRedeemRequests;

    uint256 public depositRequestId;
    mapping (uint256 => Request) public depositRequests;

    uint256 public redeemRequestId;
    mapping (uint256 => Request) public redeemRequests;

    EnumerableSet.AddressSet private pendingDepositRequestAddresses;
    EnumerableSet.UintSet private processingDepositRequestIds;
    mapping (address => EnumerableSet.UintSet) private completedDepositRequestIds;

    EnumerableSet.AddressSet private pendingRedeemRequestAddresses;
    EnumerableSet.UintSet private processingRedeemRequestIds;
    mapping (address => EnumerableSet.UintSet) private completedRedeemRequestIds;

    OperationsCache public operationsCache;
    Portfolio private portfolio;
    Request private emptyRequest;

    uint256 private constant portfolioRotationTimeout = 8 hours;
    uint256 private constant portfolioRotationBackoff = 15 minutes;
    uint256 private constant processTimeout = 1 hours;

    Vault public vault;
    bool private vaultInitialized;
    address public immutable router;

    IPerpsV2MarketSettings private immutable marketSettings;
    IERC20 public immutable susd;

    mapping (address => uint256) public assetValueMap;
    mapping (address => uint256) public orderValueForIncreasingPositionsMap;
    mapping (address => int256) public orderSizeForReducingPositionsMap;
    mapping (address => uint256) public keeperFeeMap;
    mapping (address => int128) public lastSizeMap;
    mapping (address => int256) public orderedSizeMap;
    mapping (address => uint256) public marginOutMap;
    mapping (address => bool) public completionMap;

    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant PORTFOLIO_ADMIN = keccak256('PORTFOLIO_ADMIN');
    bytes32 public constant PARAMS_ADMIN = keccak256('PARAMS_ADMIN');

    constructor(address vault_, address router_,
        address currencyToken_, address feeCollector_,
        address marketSettings_
    )
    {
        _grantRole(MAIN_ADMIN, msg.sender);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);

        _grantRole(PORTFOLIO_ADMIN, msg.sender);
        _setRoleAdmin(PORTFOLIO_ADMIN, MAIN_ADMIN);

        _grantRole(PARAMS_ADMIN, msg.sender);
        _setRoleAdmin(PARAMS_ADMIN, MAIN_ADMIN);

        require(currencyToken_ != address(0), "e1");
        require(feeCollector_ != address(0), "e1");

        processStartTimestamp = 2**256 - 1;
        router = router_;
        feeCollector = feeCollector_;
        marketSettings = IPerpsV2MarketSettings(marketSettings_);
        susd = IERC20(currencyToken_);
        portfolio.leverageFactor = 1e18; // initialize leverage to 1x. (i.e. no leverage)
    }

    function updateVault(address shareToken_)
    external
    onlyRole(MAIN_ADMIN)
    {
        require(!vaultInitialized, "e2");
        require(shareToken_ != address(0), "e1");
        vault = Vault(shareToken_);
        vaultInitialized = true;
    }

    function updateFeeParams(uint256 onboardingFeePercentage_, uint256 offboardingFeePercentage_, address feeCollector_)
    external
    onlyRole(PARAMS_ADMIN)
    {
        require(onboardingFeePercentage_ <= 2e17, "e3");
        require(offboardingFeePercentage_ <= 2e17, "e3");
        require(feeCollector_ != address(0), "e1");

        onboardingFeePercentage = onboardingFeePercentage_;
        offboardingFeePercentage = offboardingFeePercentage_;
        feeCollector = feeCollector_;
    }

    function updateMinDeposit(uint256 minDeposit_)
    external
    onlyRole(PARAMS_ADMIN)
    {
        minDeposit = minDeposit_;
    }

    function updateMinShares(uint256 minShares_)
    external
    onlyRole(PARAMS_ADMIN)
    {
        minShares = minShares_;
    }

    function updateQueueMaxs(uint256 maxProcessing_)
    external
    onlyRole(PARAMS_ADMIN)
    {
        require(maxProcessing_ > 0, "e4");
        maxProcessing = maxProcessing_;
    }

    function updateOrderSettings(uint256 maxOrderValue_, uint256 orderEps_, uint256 fillPriceBuffer_, uint256 keeperFeeFactor_)
    external
    onlyRole(PARAMS_ADMIN)
    {
        require(maxOrderValue_ > 1000e18, "e4");
        require(keeperFeeFactor_ < 20, "e4");

        maxOrderValue = maxOrderValue_;
        orderEps = orderEps_;
        fillPriceBuffer = fillPriceBuffer_;
        keeperFeeFactor = keeperFeeFactor_;
    }

    function updateLeverageFactor(uint256 leverageFactor_)
    external
    onlyRole(PARAMS_ADMIN)
    {
        require(leverageFactor_ > 0, "e4");
        portfolio.leverageFactor = leverageFactor_;
    }

    function processBackup(uint256 phase)
    external
    onlyRole(PARAMS_ADMIN)
    {
        processingTimedOut();
        operationsCache.phase = phase;
    }

    function processBackupRefundSingleRequest()
    external
    onlyRole(PARAMS_ADMIN)
    {
        processingTimedOut();
        uint256 requestId;

        if (operationsCache.requestType == RequestType.Deposit) {
            requestId = processingDepositRequestIds.at(0);
            processingDepositRequestIds.remove(requestId);
            susd.transfer(
                depositRequests[requestId].user,
                depositRequests[requestId].requestAmount + depositRequests[requestId].requestFeeInUsd
            );
        } else {
            requestId = processingRedeemRequestIds.at(0);
            processingRedeemRequestIds.remove(requestId);
            vault.transfer(
                redeemRequests[requestId].user,
                redeemRequests[requestId].requestAmount
            );
        }
    }

    function beginPortfolioRotation()
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        phaseCheck(0);

        // check for backoff interval.
        require(block.timestamp > (portfolioRotationEndTimestamp + portfolioRotationBackoff), "eE");

        // enforce that portfolioRotationStartTimestamp cannot be re-updated within the same portfolio
        // rotation session, whether the session has timed out or not. This means that endPortfolioRotation
        // must always be called after beginPortfolioRotation even if the session has timed out,
        // before another portfolio rotation session can begin.
        // ie. consecutive beginPortfolioRotation calls are not allowed.
        // ie. consecutive endPortfolioRotation calls are not allowed.
        if (portfolioRotationStartTimestamp <= portfolioRotationEndTimestamp) {
            portfolioRotationStartTimestamp = block.timestamp;
        }
    }

    function transferMargin(address[] calldata assets, int[] calldata marginDeltas)
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        duringPortfolioRotation();
        require(assets.length == marginDeltas.length, "e5");

        for (uint i=0; i<assets.length;i++) {
            IPerpsV2MarketConsolidated(assets[i]).transferMargin(marginDeltas[i]);
        }
    }

    function submitOrders(address[] calldata assets, int[] calldata sizes, uint[] calldata desiredPrices)
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        duringPortfolioRotation();

        require(assets.length == sizes.length, "e5");
        require(assets.length == desiredPrices.length, "e5");

        for (uint i=0; i<assets.length;i++) {
            IPerpsV2MarketConsolidated(assets[i]).submitOffchainDelayedOrder(sizes[i], desiredPrices[i]);
        }
    }

    function cancelOrders(address[] calldata assets)
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        duringPortfolioRotation();
        for (uint i=0; i<assets.length;i++) {
            IPerpsV2MarketConsolidated(assets[i]).cancelOffchainDelayedOrder(address(this));
        }
    }

    function removeFromAep(address[] calldata asset)
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        duringPortfolioRotation();
        for (uint i=0; i<asset.length;i++) {
            portfolio.aep[asset[i]] = 0;
            portfolio.assets.remove(asset[i]);
        }
    }

    function addToAep(address[] calldata asset, uint256[] calldata averageEntryPrice)
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        duringPortfolioRotation();
        require(asset.length == averageEntryPrice.length, "e5");

        for (uint i=0; i<asset.length;i++) {
            require(averageEntryPrice[i] > 0, "e4");
            portfolio.aep[asset[i]] = averageEntryPrice[i];
            portfolio.assets.add(asset[i]);
        }
    }

    function updateFlatUsd(uint256 flatUsd)
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        duringPortfolioRotation();
        portfolio.flatUsd = flatUsd;
    }

    function endPortfolioRotation()
    external
    onlyRole(PORTFOLIO_ADMIN)
    {
        // enforce that begin-end portfolio rotation sessions must be called one after another.
        // consecutive beginPortfolioRotation calls are not allowed.
        // consecutive endPortfolioRotation calls are not allowed.
        if (portfolioRotationStartTimestamp >= portfolioRotationEndTimestamp) {
            portfolioRotationEndTimestamp = block.timestamp;
        }
    }

    function beginProcessingDeposits(address[] calldata pendingAddresses)
    external nonReentrant
    {
        duringOnOffBoarding();
        require(pendingAddresses.length > 0, "e6");
        require(pendingAddresses.length <= maxProcessing, "e7");
        phaseCheck(0);
        operationsCache.requestType = RequestType.Deposit;

        uint256 totalAmount;
        uint256 newRequestId;

        for (uint256 i = 0; i < pendingAddresses.length; i++) {
            require(pendingDepositRequestAddresses.contains(pendingAddresses[i]), "e8");

            newRequestId = depositRequestId + 1;
            depositRequestId = newRequestId;
            require(!processingDepositRequestIds.contains(newRequestId), "e8");

            totalAmount += pendingDepositRequests[pendingAddresses[i]].requestAmount;
            depositRequests[newRequestId] = pendingDepositRequests[pendingAddresses[i]];
            processingDepositRequestIds.add(newRequestId);
            pendingDepositRequestAddresses.remove(pendingAddresses[i]);
            pendingDepositRequests[pendingAddresses[i]] = emptyRequest;
        }
        operationsCache.processingLength = pendingAddresses.length;
        operationsCache.totalAmount = totalAmount;
        operationsCache.phase = 1;
        processStartTimestamp = block.timestamp;
        require(operationsCache.totalAmount > minDeposit, "e7");
    }

    function beginProcessingRedeems(address[] calldata pendingAddresses)
    external nonReentrant
    {
        duringOnOffBoarding();
        require(pendingAddresses.length > 0, "e6");
        require(pendingAddresses.length <= maxProcessing, "e7");
        phaseCheck(0);
        operationsCache.requestType = RequestType.Redeem;

        uint256 totalAmount;
        uint256 newRequestId;

        for (uint256 i = 0; i < pendingAddresses.length; i++) {
            require(pendingRedeemRequestAddresses.contains(pendingAddresses[i]), "e8");
            newRequestId = redeemRequestId + 1;
            redeemRequestId = newRequestId;

            require(!processingRedeemRequestIds.contains(newRequestId), "e8");
            totalAmount += pendingRedeemRequests[pendingAddresses[i]].requestAmount;
            redeemRequests[newRequestId] = pendingRedeemRequests[pendingAddresses[i]];
            processingRedeemRequestIds.add(newRequestId);
            pendingRedeemRequestAddresses.remove(pendingAddresses[i]);
            pendingRedeemRequests[pendingAddresses[i]] = emptyRequest;
        }
        operationsCache.processingLength = pendingAddresses.length;
        operationsCache.totalAmount = totalAmount;
        operationsCache.phase = 1;
        processStartTimestamp = block.timestamp;
        require(operationsCache.totalAmount > minShares, "e7");
    }

    function phase1ComputeAum(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(1);

        // Initialize variables.
        address asset;
        uint256 assetPrice;
        int256 priceDiff;
        uint256 assetValue;
        uint256 tempAum;
        IPerpsV2MarketConsolidated.Position memory tempPosition;
        uint256 counter = operationsCache.counter;
        uint256 portfolioAssetsLength = portfolio.assets.length();
        if (portfolioAssetsLength > 0) {
            require(processBatchSize > 0, "e4");
        }
        RequestType requestType = operationsCache.requestType;

        // Calculate portfolio allocation value for each asset.
        if (requestType == RequestType.Deposit) {
            require((counter + processBatchSize) <= portfolioAssetsLength, "e9");
            for (uint i = counter; i < (counter + processBatchSize); i++) {
                asset = portfolio.assets.at(i);
                tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
                (assetPrice,) = IPerpsV2MarketConsolidated(asset).assetPrice();
                assetValue = getValue(tempPosition.size, portfolio.aep[asset], assetPrice);
                assetValueMap[asset] = assetValue;
                tempAum += assetValue;
            }
            operationsCache.counter = counter + processBatchSize;
            operationsCache.aum += tempAum;
            if ((counter + processBatchSize) == portfolioAssetsLength) {
                operationsCache.phase = 2;
                operationsCache.aum += portfolio.flatUsd;
                operationsCache.counter = 0;
            }
        } else {
            operationsCache.phase = 2; // skip phase 1 for redeems.
        }
    }

    function phase2ComputeTargetPositions(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();

        // Check conditions.
        phaseCheck(2);

        // Initialize variables.
        address asset;
        uint256 assetValue;
        uint256 counter = operationsCache.counter;
        uint256 portfolioAssetsLength = portfolio.assets.length();
        if (portfolioAssetsLength > 0) {
            require(processBatchSize > 0, "e4");
        }
        RequestType requestType = operationsCache.requestType;
        IPerpsV2MarketConsolidated.Position memory tempPosition;
        require((counter + processBatchSize) <= portfolioAssetsLength, "e9");

        // Calculate portfolio allocation % and target position for each asset.
        if (requestType == RequestType.Deposit) {
            if (operationsCache.aum > 0) {
                uint256 pctIncrease;
                pctIncrease = operationsCache.totalAmount * portfolio.leverageFactor / operationsCache.aum;
                for (uint i=counter; i<(counter + processBatchSize); i++) {
                    asset = portfolio.assets.at(i);
                    assetValue = assetValueMap[asset];
                    orderValueForIncreasingPositionsMap[asset] = assetValue * pctIncrease / 1e18;
                }
            }
        } else {
            int pctDecrease;
            pctDecrease = int(operationsCache.totalAmount * 1e18 / vault.totalSupply());
            // if total supply is 0, there should be no shares in circulation to perform any redeem requests.
            for (uint i=counter; i<(counter + processBatchSize); i++) {
                asset = portfolio.assets.at(i);
                tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
                orderSizeForReducingPositionsMap[asset] = -1 * tempPosition.size * pctDecrease / int(1e18);
            }
        }
        operationsCache.counter = counter + processBatchSize;
        if ((counter + processBatchSize) == portfolioAssetsLength) {
            operationsCache.counter = 0;
            operationsCache.phase = 3;
        }
    }

    function phase3TransferMargin(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(3);

        // Initialize variables.
        address asset;
        uint256 orderValue;
        uint256 counter = operationsCache.counter;
        uint256 portfolioAssetsLength = portfolio.assets.length();
        if (portfolioAssetsLength > 0) {
            require(processBatchSize > 0, "e4");
        }
        require((counter + processBatchSize) <= portfolioAssetsLength, "e9");

        // Transfer margin if increasing positions.
        if (operationsCache.requestType == RequestType.Deposit) {
            for (uint i=counter; i<(counter+processBatchSize); i++) {
                asset = portfolio.assets.at(i);
                orderValue = orderValueForIncreasingPositionsMap[asset];
                IPerpsV2MarketConsolidated(asset).transferMargin(int(orderValue));
            }
            operationsCache.counter = counter + processBatchSize;
            if ((counter + processBatchSize) == portfolioAssetsLength) {
                operationsCache.counter = 0;
                operationsCache.phase = 4;
            }
        } else {
            operationsCache.phase = 4; // skip phase 3 for redeems.
        }
    }

    function phase4SendOrder(address[] calldata assets)
    external nonReentrant
    {
        duringOnOffBoarding();
        // Check conditions.
        RequestType requestType = operationsCache.requestType;
        if (operationsCache.phase == 3) {
            if (requestType == RequestType.Redeem) {
                operationsCache.phase = 4; // skip phase 3 for redeems.
            }
        }
        phaseCheck(4);

        // Initialize variables.
        address asset;
        uint256 assetPrice;
        uint256 orderValue;
        uint256 desiredFillPrice;
        int256 orderSize;
        IPerpsV2MarketConsolidated.Position memory tempPosition;
        uint256 keeperFee = marketSettings.minKeeperFee();

        if (requestType == RequestType.Deposit) {
            for (uint i=0; i<assets.length; i++) {
                asset = assets[i];
                require(orderedSizeMap[asset] == 0, "eA");
                orderValue = orderValueForIncreasingPositionsMap[asset];
                tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
                lastSizeMap[asset] = tempPosition.size;
                if (orderValue < (keeperFee * keeperFeeFactor)) { continue; }
                orderValue -= keeperFee;
                orderValue = orderValue > maxOrderValue ? maxOrderValue : orderValue;
                (assetPrice,) = IPerpsV2MarketConsolidated(asset).assetPrice();
                desiredFillPrice = tempPosition.size > 0 ?
                    assetPrice * (1e18 + fillPriceBuffer) / 1e18 : // Buy
                    assetPrice * (1e18 - fillPriceBuffer) / 1e18;  // Sell
                orderSize = tempPosition.size > 0 ?
                    int(orderValue * 1e18 / desiredFillPrice) :
                    int(orderValue * 1e18 / assetPrice) * -1;
                orderedSizeMap[asset] = orderSize;
                IPerpsV2MarketConsolidated(asset).submitOffchainDelayedOrder(orderSize, desiredFillPrice);
                keeperFeeMap[asset] = keeperFee;
            }
        } else {
            for (uint i=0; i<assets.length; i++) {
                asset = assets[i];
                require(orderedSizeMap[asset] == 0, "eA");
                orderSize = orderSizeForReducingPositionsMap[asset];
                (assetPrice,) = IPerpsV2MarketConsolidated(asset).assetPrice();
                orderValue = abs(orderSize) * assetPrice / 1e18;
                if (orderValue < (keeperFee * keeperFeeFactor)) { continue; }
                tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
                desiredFillPrice = orderSize > 0 ?
                    assetPrice * (1e18 + fillPriceBuffer) / 1e18 : // Buy
                    assetPrice * (1e18 - fillPriceBuffer) / 1e18;  // Sell
                orderSize = orderValue <= maxOrderValue ?
                    orderSize : orderSize > 0 ?
                        int(maxOrderValue * 1e18 / desiredFillPrice):
                        int(maxOrderValue * 1e18 / assetPrice) * -1;
                orderedSizeMap[asset] = orderSize;
                lastSizeMap[asset] = tempPosition.size;
                IPerpsV2MarketConsolidated(asset).submitOffchainDelayedOrder(orderSize, desiredFillPrice);
                keeperFeeMap[asset] = keeperFee;
            }
        }
    }

    function phase4CheckOrder(address[] calldata assets)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(4);

        address asset;
        int128 lastSize;
        int256 sizeDelta;
        uint256 valueDelta;
        uint256 eps;
        uint256 keeperFee;

        RequestType requestType = operationsCache.requestType;
        IPerpsV2MarketConsolidated.Position memory tempPosition;

        if (requestType == RequestType.Deposit) {
            for (uint i=0; i<assets.length;i++) {
                asset = assets[i];
                require(completionMap[asset] == false, "eA");
                keeperFee = keeperFeeMap[asset];
                eps = orderEps > (keeperFeeFactor * keeperFee) ? orderEps : (keeperFeeFactor * keeperFee);
                if (orderedSizeMap[asset] == 0) {
                    if (orderValueForIncreasingPositionsMap[asset] <= eps) {
                        completionMap[asset] = true;
                        operationsCache.completionCounter++;
                    }
                    continue;
                }

                tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
                lastSize = lastSizeMap[asset];
                lastSizeMap[asset] = tempPosition.size;
                sizeDelta = tempPosition.size - lastSize;
                if (sizeDelta != 0) {
                    orderedSizeMap[asset] = 0;
                    keeperFeeMap[asset] = 0;
                } else {
                    // case where value delta is 0.
                    if (orderValueForIncreasingPositionsMap[asset] <= eps) {
                        completionMap[asset] = true;
                        operationsCache.completionCounter++;
                    }
                    continue;
                }
                valueDelta = abs(sizeDelta) * uint(tempPosition.lastPrice) / 1e18;
                uint256 remainingValue = orderValueForIncreasingPositionsMap[asset];
                uint256 newRemainingValue;
                if (remainingValue < (valueDelta + keeperFee)) {
                    // take care of underflow.
                    newRemainingValue = 0;
                } else {
                    newRemainingValue = remainingValue - (valueDelta + keeperFee);
                }
                orderValueForIncreasingPositionsMap[asset] = newRemainingValue;
                operationsCache.amountSpent += valueDelta + keeperFee;

                if (newRemainingValue <= eps) {
                    completionMap[asset] = true;
                    operationsCache.completionCounter++;
                }

                // update AEP.
                portfolio.aep[asset] = tempPosition.size == 0 ?
                    0 :
                ((portfolio.aep[asset] * abs(lastSize)) + (tempPosition.lastPrice * abs(sizeDelta))) / abs(tempPosition.size);
            }
        } else {
            for (uint i=0; i<assets.length; i++) {
                asset = assets[i];
                require(completionMap[asset] == false, "eA");
                tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
                keeperFee = keeperFeeMap[asset];
                eps = orderEps > (keeperFeeFactor * keeperFee) ? orderEps : (keeperFeeFactor * keeperFee);
                if (orderedSizeMap[asset] == 0) {
                    if (((abs(orderSizeForReducingPositionsMap[asset]) * uint(tempPosition.lastPrice) / 1e18) <= eps)) {
                        completionMap[asset] = true;
                        operationsCache.completionCounter++;
                    }
                    continue;
                }
                lastSize = lastSizeMap[asset];
                lastSizeMap[asset] = tempPosition.size;
                sizeDelta = tempPosition.size - lastSize;
                if (sizeDelta != 0) {
                    orderedSizeMap[asset] = 0;
                    keeperFeeMap[asset] = 0;
                } else {
                    // case where size delta is 0.
                    if (((abs(orderSizeForReducingPositionsMap[asset]) * uint(tempPosition.lastPrice) / 1e18) <= eps)) {
                        completionMap[asset] = true;
                        operationsCache.completionCounter++;
                    }
                    continue;
                }
                valueDelta =
                tempPosition.size > 0 ?
                    abs(sizeDelta) * uint(tempPosition.lastPrice) / 1e18                // long positions
                    :
                    (portfolio.aep[asset] * 2) > uint(tempPosition.lastPrice) ?         // take care of underflow
                        (abs(sizeDelta) * ((portfolio.aep[asset] * 2) - uint(tempPosition.lastPrice)))
                        / 1e18                                                          // short positions
                        :
                        0;
                valueDelta = valueDelta > keeperFee ? valueDelta - keeperFee : 0;
                int256 remainingSize = orderSizeForReducingPositionsMap[asset];
                int256 newRemainingSize;
                marginOutMap[asset] += valueDelta;
                operationsCache.amountReceived += valueDelta;
                newRemainingSize = abs(remainingSize) > abs(sizeDelta) ?
                    remainingSize - sizeDelta :
                    int(0);
                orderSizeForReducingPositionsMap[asset] = newRemainingSize;

                if (((abs(newRemainingSize) * uint(tempPosition.lastPrice) / 1e18) <= eps)) {
                    completionMap[asset] = true;
                    operationsCache.completionCounter++;
                }

                // do not update AEP when reducing positions.
            }
        }

        if (operationsCache.completionCounter == portfolio.assets.length()) {
                operationsCache.completionCounter = 0;
                operationsCache.phase = 5;

            if (operationsCache.requestType == RequestType.Deposit) {
                uint256 totalAmount = operationsCache.totalAmount;
                uint256 amountSpent = operationsCache.amountSpent;
                portfolio.flatUsd += totalAmount > amountSpent ? totalAmount - amountSpent : 0;
            } else {
                uint256 flatUsd = portfolio.flatUsd;
                uint256 flatUsdOut = flatUsd * operationsCache.totalAmount / vault.totalSupply();
                // if total supply is 0, there should not be any shares in circulation to even make a redeem request.
                operationsCache.amountReceived += flatUsdOut;
                portfolio.flatUsd = flatUsd > flatUsdOut ? flatUsd - flatUsdOut : 0;
            }
        }
    }

    function phase4CancelOrder(address[] calldata assets)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(4);
        address asset;
        IPerpsV2MarketConsolidated.Position memory tempPosition;
        int256 lastSize;
        for (uint i=0; i<assets.length; i++) {
            asset = assets[i];
            lastSize = lastSizeMap[asset];
            tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
            require(tempPosition.size == lastSize, "e4");
            orderedSizeMap[asset] = 0;
            keeperFeeMap[asset] = 0;
            if (IPerpsV2MarketConsolidated(asset).delayedOrders(address(this)).sizeDelta != 0) {
                IPerpsV2MarketConsolidated(asset).cancelOffchainDelayedOrder(address(this));
            }
        }
    }

    function phase5TransferMargin(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(5);

        if (operationsCache.requestType == RequestType.Deposit) {
            operationsCache.phase = 6;
        } else {
            uint256 counter = operationsCache.counter;
            address asset;
            for (uint i=counter; i<(counter+processBatchSize); i++) {
                asset = portfolio.assets.at(i);
                IPerpsV2MarketConsolidated(asset).transferMargin(-1 * int(marginOutMap[asset]));
            }
            operationsCache.counter = counter + processBatchSize;
            if ((counter + processBatchSize) >= portfolio.assets.length()) {
                operationsCache.counter = 0;
                operationsCache.phase = 6;
            }
        }
    }

    function phase6ComputeNewAum(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();
        RequestType requestType = operationsCache.requestType;
        if (requestType == RequestType.Deposit && operationsCache.phase == 5) {
            operationsCache.phase = 6;
        }
        phaseCheck(6);
        uint256 portfolioAssetsLength = portfolio.assets.length();
        if (portfolioAssetsLength > 0) {
            require(processBatchSize > 0, "e4");
        }
        uint256 counter = operationsCache.counter;
        require((counter + processBatchSize) <= portfolioAssetsLength, "e9");
        address asset;
        IPerpsV2MarketConsolidated.Position memory tempPosition;
        uint256 assetValue;
        uint256 tempAum;
        uint256 assetPrice;

        for (uint i=counter; i<(counter+processBatchSize); i++) {
            asset = portfolio.assets.at(i);
            tempPosition = IPerpsV2MarketConsolidated(asset).positions(address(this));
            (assetPrice,) = IPerpsV2MarketConsolidated(asset).assetPrice();
            assetValue = getValue(tempPosition.size, portfolio.aep[asset], assetPrice);
            tempAum += assetValue;
        }
        operationsCache.counter = counter + processBatchSize;
        operationsCache.newAum += tempAum;

        if ((counter + processBatchSize) >= portfolioAssetsLength) {
            operationsCache.counter = 0;
            operationsCache.phase = 7;
            operationsCache.newAum += portfolio.flatUsd;
        }
    }

    function phase7MintWithdraw(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(7);
        uint256 counter = operationsCache.counter;
        require((counter + processBatchSize) <= operationsCache.processingLength, "e9");
        uint256 requestId;
        address user;

        if (operationsCache.requestType == RequestType.Deposit) {
            uint256 totalUsdForBatch = operationsCache.totalAmount;
            uint256 totalOnboardingFeesForBatch;
            // total usd for batch should not be 0 since minDeposit is at least 0, and total amount must be greater.
            if (operationsCache.totalSharesToMint == 0) {
                operationsCache.totalSharesToMint =
                (vault.totalSupply() == 0) || (operationsCache.aum == 0) ? totalUsdForBatch :
                ((operationsCache.newAum * 1e18 / operationsCache.aum) - 1e18)
                * vault.totalSupply()
                / 1e18;
            }
            uint256 totalSharesToMint = operationsCache.totalSharesToMint;

            for (uint i=counter; i<(counter+processBatchSize); i++) {
                requestId = processingDepositRequestIds.at(0);
                uint256 sharesToMint = depositRequests[requestId].requestAmount * totalSharesToMint / totalUsdForBatch;
                user = depositRequests[requestId].user;
                vault.shareMint(user, sharesToMint);
                completedDepositRequestIds[user].add(requestId);
                processingDepositRequestIds.remove(requestId);
                totalOnboardingFeesForBatch += depositRequests[requestId].requestFeeInUsd;
                depositRequests[requestId].processedTimestamp = block.timestamp;
                depositRequests[requestId].processedAmount = sharesToMint;
            }

            susd.transfer(feeCollector, totalOnboardingFeesForBatch);
            operationsCache.counter = counter + processBatchSize;
            if ((counter + processBatchSize) >= operationsCache.processingLength) {
                operationsCache.counter = 0;
                operationsCache.phase = 8;
            }

        } else {
            uint256 sharesToBurn;
            uint256 batchSharesToBurn;
            uint256 usdToReturn;
            uint256 feeInUsd;
            uint256 totalOffboardingFeesForBatch;
            for (uint i=counter; i<(counter+processBatchSize); i++) {
                requestId = processingRedeemRequestIds.at(0);
                sharesToBurn = redeemRequests[requestId].requestAmount;
                batchSharesToBurn += sharesToBurn;
                usdToReturn = sharesToBurn * operationsCache.amountReceived / operationsCache.totalAmount;
                feeInUsd = offboardingFeePercentage * usdToReturn / 1e18;
                usdToReturn -= feeInUsd;
                susd.transfer(redeemRequests[requestId].user, usdToReturn);
                completedRedeemRequestIds[redeemRequests[requestId].user].add(requestId);
                processingRedeemRequestIds.remove(requestId);
                totalOffboardingFeesForBatch += feeInUsd;
                redeemRequests[requestId].processedTimestamp = block.timestamp;
                redeemRequests[requestId].requestFeeInUsd = feeInUsd;
                redeemRequests[requestId].processedAmount = usdToReturn;
            }
            vault.burnShares(batchSharesToBurn);
            susd.transfer(feeCollector, totalOffboardingFeesForBatch);
            operationsCache.counter = counter + processBatchSize;
            if ((counter + processBatchSize) >= operationsCache.processingLength) {
                operationsCache.counter = 0;
                operationsCache.phase = 8;
            }
        }
    }

    function phase8Cleanup(uint256 processBatchSize)
    external nonReentrant
    {
        duringOnOffBoarding();
        phaseCheck(8);
        uint256 counter = operationsCache.counter;
        require((counter + processBatchSize) <= portfolio.assets.length(), "e9");

        address asset;

        for (uint i=counter; i<(counter+processBatchSize); i++) {
            asset = portfolio.assets.at(i);
            assetValueMap[asset] = 0;
            orderValueForIncreasingPositionsMap[asset] = 0;
            orderSizeForReducingPositionsMap[asset] = 0;
            lastSizeMap[asset] = 0;
            orderedSizeMap[asset] = 0;
            marginOutMap[asset] = 0;
            keeperFeeMap[asset] = 0;
            completionMap[asset] = false;
        }

        operationsCache.counter = counter + processBatchSize;

        if ((counter + processBatchSize) >= portfolio.assets.length()) {
            operationsCache.phase = 0;
            operationsCache.requestType = RequestType.Null;
            operationsCache.processingLength = 0;
            operationsCache.totalAmount = 0;
            operationsCache.counter = 0;
            operationsCache.aum = 0;
            operationsCache.newAum = 0;
            operationsCache.amountSpent = 0;
            operationsCache.totalSharesToMint = 0;
            operationsCache.amountReceived = 0;
            operationsCache.completionCounter = 0;
            processStartTimestamp = 2**256 - 1;
        }
    }

    function onOffBoard(address user, uint256 amount, RequestType requestType)
    external
    {
        onlyRouter();
        if (requestType == RequestType.Deposit) {
            uint256 fee = amount * onboardingFeePercentage / 1e18;
            pendingDepositRequests[user].requestType = requestType;
            pendingDepositRequests[user].user = user;
            pendingDepositRequests[user].requestAmount = amount - fee;
            pendingDepositRequests[user].requestFeeInUsd = fee;
            pendingDepositRequests[user].requestTimestamp = block.timestamp;
            pendingDepositRequestAddresses.add(user);
        } else if (requestType == RequestType.Redeem) {
            pendingRedeemRequests[user].requestType = requestType;
            pendingRedeemRequests[user].user = user;
            pendingRedeemRequests[user].requestAmount = amount;
            pendingRedeemRequests[user].requestTimestamp = block.timestamp;
            pendingRedeemRequestAddresses.add(user);
        }
    }

    function cancelRequest(address user, RequestType requestType)
    external
    {
        onlyRouter();
        if (requestType == RequestType.Deposit) {
            susd.transfer(user, pendingDepositRequests[user].requestAmount + pendingDepositRequests[user].requestFeeInUsd);
            pendingDepositRequests[user].requestType = RequestType.Null;
            pendingDepositRequests[user].user = address(0);
            pendingDepositRequests[user].requestAmount = 0;
            pendingDepositRequests[user].requestFeeInUsd = 0;
            pendingDepositRequests[user].requestTimestamp = 0;
            pendingDepositRequestAddresses.remove(user);
        } else if (requestType == RequestType.Redeem) {
            vault.transfer(user, pendingRedeemRequests[user].requestAmount);
            pendingRedeemRequests[user].requestType = RequestType.Null;
            pendingRedeemRequests[user].user = address(0);
            pendingRedeemRequests[user].requestAmount = 0;
            pendingRedeemRequests[user].requestTimestamp = 0;
            pendingRedeemRequestAddresses.remove(user);
        }
    }

    function getPortfolioAssetsLength()
    external view
    returns (uint256)
    {
        return portfolio.assets.length();
    }

    function getPendingDepositRequestAddressesLength()
    external view
    returns (uint256)
    {
        return pendingDepositRequestAddresses.length();
    }

    function getPendingRedeemRequestAddressesLength()
    external view
    returns (uint256)
    {
        return pendingRedeemRequestAddresses.length();
    }

    function getCompletedDepositRequestIdsLength(address user)
    external view
    returns (uint256)
    {
        return completedDepositRequestIds[user].length();
    }

    function getCompletedRedeemRequestIdsLength(address user)
    external view
    returns (uint256)
    {
        return completedRedeemRequestIds[user].length();
    }

    function getProcessingDepositRequestIdsLength()
    external view
    returns (uint256)
    {
        return processingDepositRequestIds.length();
    }

    function getProcessingRedeemRequestIdsLength()
    external view
    returns (uint256)
    {
        return processingRedeemRequestIds.length();
    }

    function getPortfolioAddresses(uint256 start, uint256 end)
    external view
    returns (address[] memory)
    {
        return getListFromAddressSet(portfolio.assets, start, end);
    }

    function getPendingDepositAddresses(uint256 start, uint256 end)
    external view
    returns (address[] memory)
    {
        return getListFromAddressSet(pendingDepositRequestAddresses, start, end);
    }

    function getPendingRedeemAddresses(uint256 start, uint256 end)
    external view
    returns (address[] memory)
    {
        return getListFromAddressSet(pendingRedeemRequestAddresses, start, end);
    }

    function getProcessingDepositRequestIds(uint256 start, uint256 end)
    external view
    returns (uint256[] memory)
    {
        return getListFromUintSet(processingDepositRequestIds, start, end);
    }

    function getProcessingRedeemRequestIds(uint256 start, uint256 end)
    external view
    returns (uint256[] memory)
    {
        return getListFromUintSet(processingRedeemRequestIds, start, end);
    }

    function getCompletedDepositRequestIds(address user, uint256 start, uint256 end)
    external view
    returns (uint256[] memory)
    {
        return getListFromUintSet(completedDepositRequestIds[user], start, end);
    }

    function getCompletedRedeemRequestIds(address user, uint256 start, uint256 end)
    external view
    returns (uint256[] memory)
    {
        return getListFromUintSet(completedRedeemRequestIds[user], start, end);
    }

    function getFlatUsd()
    external view
    returns (uint256)
    {
        return portfolio.flatUsd;
    }

    function getLeverageFactor()
    external view
    returns (uint256)
    {
        return portfolio.leverageFactor;
    }

    function getAeps(address[] memory assets)
    external view
    returns (uint256[] memory)
    {
        uint256[] memory aeps = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            aeps[i] = portfolio.aep[assets[i]];
        }
        return aeps;
    }

    function processingTimedOut() private view {
        require(block.timestamp > (processStartTimestamp + processTimeout), "eF");
    }

    function duringOnOffBoarding() private view {
        require(!portfolioRotationActive(), "eD");
    }

    function duringPortfolioRotation() private view {
        require(portfolioRotationActive(), "eG");
    }

    function portfolioRotationActive() private view returns (bool) {
        return (
            (portfolioRotationStartTimestamp > portfolioRotationEndTimestamp) &&
            (block.timestamp <= (portfolioRotationStartTimestamp + portfolioRotationTimeout))
        );
    }

    function onlyRouter() private view {
        require(msg.sender == router, "eH");
    }

    function phaseCheck(uint256 phase) private view {
        require(operationsCache.phase == phase, "eI");
    }
}