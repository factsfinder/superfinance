pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Supa is Ownable {
    address public adminAddress; // owner/admin/manager address;
    address public feesAddress; //  address where fees will be transferred. This fee is used to pay for devs/marketing etc;
    uint8 feePercent;
    bool isContractLocked;

    constructor(address admin, address fees) {
        adminAddress = admin;
        feesAddress = fees;
        isContractLocked = true;
        feePercent = 5;
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

    // Note: string below should refer to ATLAS or STRONGBLOCK
    mapping(address => mapping(NODE_TYPE => Investment)) public userInvestments;

    address[] public allShareHolders;

    address[] public suspendedUserAccounts; // malicious accounts suspended from trading/investing.

    function setFeePercent(uint8 feeNum) external onlyOwner {
        feePercent = feeNum;
    }

    function _addToInvestmentWallets(address _account) external onlyOwner {
        if (
            _account != address(0) &&
            _account != feesAddress &&
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
            _account != feesAddress &&
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

    function createInvestment(NODE_TYPE _nodePreference, uint256 _shares)
        external
        onlyNonSuspendedUsers
        onlyAtlasOrStrong(_nodePreference)
    {
        require(!isContractLocked, "contract is locked at the moment");
        require(_shares >= 1, "Minimum requirement of 1 share not met..!");
        address _account = msg.sender;
        if (
            _account != address(0) &&
            _account != feesAddress &&
            _account != adminAddress
        ) {
            Investment storage existingInvestment = userInvestments[_account][
                _nodePreference
            ];

            if (existingInvestment.numberOfShares > 0) {
                userInvestments[_account][_nodePreference]
                    .numberOfShares += _shares;
            } else {
                // Todo: transfer shares
                // Do Something like IERC20(_token ).safeTransferFrom( msg.sender, address(this), _price.mul( _tenToThePowerDecimals).mul( _shareCount ));
                userInvestments[_account][_nodePreference] = Investment(
                    _shares,
                    block.timestamp,
                    0 // claimable rewards
                );
                allShareHolders.push(_account);
            }
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
        // Todo: transfer rewards to msg.sender
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
        // Todo: transfer rewards to msg.sender
        atlasInvestment.claimableRewards = 0;
        strongInvestment.claimableRewards = 0;
        // Todo:  check whether we need to do these below again. Check during testing.
        userInvestments[_account][NODE_TYPE.ATLAS] = atlasInvestment;
        userInvestments[_account][NODE_TYPE.STRONGBLOCK] = strongInvestment;
    }
}
