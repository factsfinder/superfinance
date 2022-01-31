// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Supa is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public adminAddress; // owner/admin/manager address;
    address payable public feesVault; //  address where fees will be transferred. This fee is used to pay for devs/marketing etc;
    address payable public investmentVault; // address where user funds after fees will go to. ($10 per share, usdc)
    address payable public rewardsVault; // address where user rewards will be moved to initially before being claiming.

    address public paymentTokenAddress;

    uint8 feePercent = 5;
    bool isContractLocked = true;

    constructor(
        address admin,
        address feesAddress,
        address investmentAddress,
        address rewardsAddress,
        address tokenAddress
    ) {
        require(
            admin != feesAddress &&
                feesAddress != investmentAddress &&
                investmentAddress != rewardsAddress,
            "all addreses must be different"
        );
        adminAddress = admin;
        feesVault = payable(feesAddress);
        investmentVault = payable(investmentAddress);
        rewardsVault = payable(rewardsAddress);
        paymentTokenAddress = tokenAddress;
    }

    // accounts which are used to create atlas/strongblock nodes.
    // We need multiple wallets because there is a hard limit of 100 nodes for strongblock/atlas nodes per wallet.
    address[] public investmentWallets;

    enum NODE_TYPE {
        ATLAS,
        STRONGBLOCK
    }

    struct Investment {
        uint256 numberOfShares; // 1 share =10 usd
        uint256 createdAt;
        uint256 claimableRewards;
    }

    // Note: NODE_TYPE below should refer to ATLAS (0) or STRONGBLOCK (1).
    // Enums are uint and will start with 0 by default so ATLAS vaule will be 0 and strongblock will be 1.
    mapping(address => mapping(NODE_TYPE => Investment)) public userInvestments;

    address[] public allShareHolders;

    address[] public suspendedUserAccounts; // malicious accounts suspended from trading/investing.

    function setFeePercent(uint8 feeNum) external onlyOwner {
        feePercent = feeNum;
    }

    function setFeeVault(address feeAddress) external onlyOwner {
        require(feeAddress != feesVault, "same address provided");
        require(
            (feeAddress != investmentVault &&
                feeAddress != rewardsVault &&
                feeAddress != adminAddress &&
                feeAddress != address(0)),
            "Can't be any of admin, rewards or investment addresses"
        );
        feesVault = payable(feeAddress);
    }

    function setAdminAddress(address adminWallet) external onlyOwner {
        require(adminAddress != adminWallet, "same address provided");
        require(
            (adminWallet != rewardsVault &&
                adminWallet != feesVault &&
                adminWallet != investmentVault &&
                adminWallet != address(0)),
            "Can't be any of admin, rewards or investment addresses"
        );
        adminAddress = adminWallet;
    }

    function setInvestmentVault(address investmentAddress) external onlyOwner {
        require(investmentAddress != investmentVault, "same address provided");
        require(
            (investmentAddress != rewardsVault &&
                investmentAddress != feesVault &&
                investmentAddress != adminAddress &&
                investmentAddress != address(0)),
            "Can't be any of admin, rewards or investment addresses"
        );
        investmentVault = payable(investmentAddress);
    }

    function setRewardsvault(address rewardsAddress) external onlyOwner {
        require(rewardsVault != rewardsAddress, "same address provided");
        require(
            (rewardsAddress != investmentVault &&
                rewardsAddress != feesVault &&
                rewardsAddress != adminAddress &&
                rewardsAddress != address(0)),
            "Can't be any of admin, rewards or investment addresses"
        );
        rewardsVault = payable(rewardsAddress);
    }

    function updatePaymentTokenAddress(address _tokenAddress)
        external
        onlyOwner
    {
        require(
            _tokenAddress != address(0) &&
                _tokenAddress != adminAddress &&
                _tokenAddress != feesVault &&
                _tokenAddress != rewardsVault,
            "Need a stable coin contract address"
        );
        paymentTokenAddress = _tokenAddress;
    }

    function _addNewToInvestmentWallets(address _account) external onlyOwner {
        if (
            _account != address(0) &&
            _account != feesVault &&
            _account != adminAddress
        ) {
            investmentWallets.push(_account);
        }
    }

    function setContractLockStatus(bool lockOrUnLock)
        external
        onlyOwner
        returns (bool)
    {
        isContractLocked = lockOrUnLock;
        return lockOrUnLock;
    }

    function suspendAccount(address _account) external onlyOwner {
        require(
            !isSuspendedUserAccount(_account),
            "This account is already suspended"
        );
        if (
            _account != address(0) &&
            _account != feesVault &&
            _account != adminAddress
        ) {
            suspendedUserAccounts.push(_account);
        }
    }

    function isSuspendedUserAccount(address _account)
        public
        view
        returns (bool)
    {
        for (uint256 i = 0; i < suspendedUserAccounts.length; i++) {
            if (suspendedUserAccounts[i] == _account) {
                return true;
            }
        }
        return false;
    }

    modifier onlyNonSuspendedUsers() {
        require(
            !isSuspendedUserAccount(msg.sender),
            "Your account is suspended at the moment. Please contact SUPA support if you think this is a mistake..!"
        );
        _;
    }

    modifier onlyAtlasOrStrong(NODE_TYPE _nodeType) {
        require(
            _nodeType == NODE_TYPE.ATLAS || _nodeType == NODE_TYPE.STRONGBLOCK,
            "NODE Type must be one of ATLAS or STRONGBLOCK"
        );
        _;
    }

    function removeUserSuspension(address _account)
        external
        onlyOwner
        returns (bool)
    {
        uint256 accountIndex;
        for (uint256 i = 0; i < suspendedUserAccounts.length; i++) {
            if (suspendedUserAccounts[i] == _account) {
                accountIndex = i;
            }
        }
        if (suspendedUserAccounts[accountIndex] == _account) {
            suspendedUserAccounts[accountIndex] = suspendedUserAccounts[
                suspendedUserAccounts.length - 1
            ];
            suspendedUserAccounts.pop();
            return true;
        }
        return false;
    }

    function getUserTotalSharesByType(NODE_TYPE _nodeType, address _account)
        public
        view
        onlyNonSuspendedUsers
        onlyAtlasOrStrong(_nodeType)
        returns (uint256)
    {
        return userInvestments[_account][_nodeType].numberOfShares;
    }

    function getUserClaimableRewardsyType(NODE_TYPE _nodeType, address _account)
        public
        view
        onlyNonSuspendedUsers
        onlyAtlasOrStrong(_nodeType)
        returns (uint256)
    {
        return userInvestments[_account][_nodeType].claimableRewards;
    }

    function getUserTotalClaimableRewards(address _account)
        public
        view
        onlyNonSuspendedUsers
        returns (uint256)
    {
        return
            userInvestments[_account][NODE_TYPE.ATLAS].claimableRewards +
            userInvestments[_account][NODE_TYPE.STRONGBLOCK].claimableRewards;
    }

    function getTotalAtlasSharesBoughtByAll() public view returns (uint256) {
        uint256 totalAtlasShares = 0;
        for (uint256 i = 0; i < allShareHolders.length; i++) {
            uint256 atlasSharesBought = userInvestments[allShareHolders[i]][
                NODE_TYPE.ATLAS
            ].numberOfShares;
            totalAtlasShares += atlasSharesBought;
        }
        return totalAtlasShares;
    }

    function getTotalStrongSharesBoughtByAll() public view returns (uint256) {
        uint256 totalStrongShares = 0;
        for (uint256 i = 0; i < allShareHolders.length; i++) {
            uint256 strongSharesBought = userInvestments[allShareHolders[i]][
                NODE_TYPE.STRONGBLOCK
            ].numberOfShares;
            totalStrongShares += strongSharesBought;
        }
        return totalStrongShares;
    }

    function getTotalSharesBoughtByAll() public view returns (uint256) {
        return
            getTotalAtlasSharesBoughtByAll() +
            getTotalStrongSharesBoughtByAll();
    }

    function createInvestment(NODE_TYPE _nodePreference, uint256 _shares)
        external
        payable
        onlyNonSuspendedUsers
        onlyAtlasOrStrong(_nodePreference)
    {
        require(!isContractLocked, "contract is locked at the moment");
        require(_shares >= 1, "Minimum requirement of 1 share not met..!");
        address _account = msg.sender;
        require(
            _account != address(0) &&
                _account != feesVault &&
                _account != adminAddress,
            "only non contract related address allowed"
        );

        Investment storage existingInvestment = userInvestments[_account][
            _nodePreference
        ];

        IERC20(paymentTokenAddress).safeTransferFrom(
            _account,
            investmentVault,
            10000000000000000000 * _shares // 10 ** 18 wei  is equal to 1 eth - use https://eth-converter.com/
        );

        if (existingInvestment.numberOfShares > 0) {
            userInvestments[_account][_nodePreference]
                .numberOfShares += _shares;
        } else {
            userInvestments[_account][_nodePreference] = Investment(
                _shares,
                block.timestamp,
                0 // claimable rewards
            );
            allShareHolders.push(_account);
        }
    }

    function compoundRewards(NODE_TYPE _nodePreference)
        external
        onlyNonSuspendedUsers
        onlyAtlasOrStrong(_nodePreference)
    {
        require(!isContractLocked, "contract is locked at the moment");
        address _account = msg.sender;
        Investment storage existingInvestment = userInvestments[_account][
            _nodePreference
        ];
        uint256 rewardsToClaim = existingInvestment.claimableRewards;
        require(
            rewardsToClaim > 1,
            "claimable rewards minimum requirement not met. Must be atleast 1"
        );
        existingInvestment.numberOfShares += rewardsToClaim;
        existingInvestment.claimableRewards = 0;
        // Todo:  check whether we need to do the below operation. Check during testing.
        userInvestments[_account][_nodePreference] = existingInvestment;
    }

    function distributeRewards() external onlyOwner {
        uint256 totalAtlasShares = getTotalAtlasSharesBoughtByAll();
        uint256 totalStrongShares = getTotalStrongSharesBoughtByAll();
        uint256 balanceInRewardsVault = IERC20(paymentTokenAddress).balanceOf(
            rewardsVault
        );
        for (uint256 i = 0; i < allShareHolders.length; i++) {
            address userAddress = allShareHolders[i];
            uint256 atlasSharesBoughtByUser = userInvestments[userAddress][
                NODE_TYPE.ATLAS
            ].numberOfShares;
            uint256 userAtlasSharesPercent = atlasSharesBoughtByUser
                .div(totalAtlasShares)
                .mul(100);
            userInvestments[userAddress][NODE_TYPE.ATLAS].claimableRewards =
                userAtlasSharesPercent *
                balanceInRewardsVault;
            // Now for strong nodes
            uint256 strongSharesBoughtByUser = userInvestments[userAddress][
                NODE_TYPE.STRONGBLOCK
            ].numberOfShares;
            uint256 userStrongSharesPercent = strongSharesBoughtByUser
                .div(totalStrongShares)
                .mul(100);
            userInvestments[userAddress][NODE_TYPE.STRONGBLOCK]
                .claimableRewards =
                userStrongSharesPercent *
                balanceInRewardsVault;
        }
    }

    function claimRewardByType(NODE_TYPE _nodeType)
        external
        onlyNonSuspendedUsers
        onlyAtlasOrStrong(_nodeType)
    {
        address _account = msg.sender;
        Investment storage existingInvestment = userInvestments[_account][
            _nodeType
        ];
        uint256 claimableRewards = existingInvestment.claimableRewards;
        require(claimableRewards > 1, "Not enough rewards to claim!");
        uint256 feeChargedFromRewards = claimableRewards.mul(5).div(100);
        uint256 rewardsClaimableAfterFee = claimableRewards -
            feeChargedFromRewards;
        IERC20(paymentTokenAddress).safeTransferFrom(
            rewardsVault,
            feesVault,
            feeChargedFromRewards.mul(1000000000000000000) // in wei
        );
        IERC20(paymentTokenAddress).safeTransferFrom(
            rewardsVault,
            _account,
            rewardsClaimableAfterFee.mul(1000000000000000000) // in wei
        );
        existingInvestment.claimableRewards = 0;
        // Todo:  check whether we need to do these below again. Check during testing.
        userInvestments[_account][_nodeType] = existingInvestment;
    }

    function claimAllRewards() external onlyNonSuspendedUsers {
        address _account = msg.sender;
        Investment storage atlasInvestment = userInvestments[_account][
            NODE_TYPE.ATLAS
        ];
        Investment storage strongInvestment = userInvestments[_account][
            NODE_TYPE.STRONGBLOCK
        ];
        uint256 claimableRewards = atlasInvestment.claimableRewards +
            strongInvestment.claimableRewards;
        require(claimableRewards > 1, "Not enough rewards to claim!");
        uint256 feeChargedFromRewards = claimableRewards.mul(5).div(100);
        uint256 rewardsClaimableAfterFee = claimableRewards -
            feeChargedFromRewards;
        IERC20(paymentTokenAddress).safeTransferFrom(
            rewardsVault,
            feesVault,
            feeChargedFromRewards.mul(1000000000000000000) // in wei
        );
        IERC20(paymentTokenAddress).safeTransferFrom(
            rewardsVault,
            _account,
            rewardsClaimableAfterFee.mul(1000000000000000000) // in wei
        );
        atlasInvestment.claimableRewards = 0;
        strongInvestment.claimableRewards = 0;
        // Todo:  check whether we need to do these below again. Check during testing.
        userInvestments[_account][NODE_TYPE.ATLAS] = atlasInvestment;
        userInvestments[_account][NODE_TYPE.STRONGBLOCK] = strongInvestment;
    }
}
