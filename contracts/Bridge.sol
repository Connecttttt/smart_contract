// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "../interfaces/IERC20.sol";

contract Bridge {
    struct Transaction {
        uint256 ID;
        address from;
        string fromUsername;
        address to;
        string toUsername;
        address asset;
        uint256 amount;
        bytes32 claimCodeHash;
        string description;
        bool arbitration;
        TimeDetails timeDetails;
        ArbTransactionDetails arbDetails;
        uint256 state;
        // 1= unaccepted, 2=active, 3=pending, 3.5=completed,
    }

    struct TimeDetails {
        uint256 txEndTime;
        uint256 toBeSetTime;
        bool claimed;
    }

    struct ArbTransactionDetails {
        bool retracted;
        uint256 successArbitersCount;
        uint256 nullArbitersCount;
        address[] fromArbiters;
        address[] toArbiters;
        uint256 arbOutcome; // 0 - nothing, 1 - succesful transaction, 2 - null transaction,
    }

    struct UserDetails {
        uint256 totalTransactions;
        uint256 succesfullTransactions;
        uint256 nulllTransactions;
        uint256 bridgeTokenBalance; //NOT TOUCHEDDDDDD
    }

    uint256 public constant MAX_USERNAME_LENGTH = 20;
    uint256 public transactionIDCounter;

    address public bridgeTokenAddress;

    Transaction[] public transactions;

    mapping(address => string) public _username;
    mapping(string => address) public _usernameToAddress;
    mapping(string => bool) public _usernameTaken;
    mapping(address => bool) public _userSignedUp;

    mapping(address => UserDetails) public _userDetails;

    mapping(uint256 => mapping(address => bool)) public _hasMadeDecision;

    event SignedUp(address user, string username);

    event TransactionCreated(uint256 ID, Transaction tx);

    event TransactionAccepted(uint256 ID, Transaction tx);

    event BetClaimed(uint256 ID, Transaction tx);

    event ArbitrateTransaction(uint256 ID, Transaction tx);

    event TransactionRetracted(uint256 ID, Transaction tx);

    constructor(address _bridgeTokenAddress) {
        bridgeTokenAddress = _bridgeTokenAddress;
    }

    function signUp(string memory _userName) public {
        require(!_usernameTaken[_userName], "UserName Taken");
        require(!_userSignedUp[msg.sender], "User Already Signed Up");

        _checkUsernameValidity(_userName);

        // assign the user the username
        _username[msg.sender] = _userName;
        _usernameTaken[_userName] = true;
        _userSignedUp[msg.sender] = true;
        _usernameToAddress[_userName] = msg.sender;

        // fire event
        emit SignedUp(msg.sender, _userName);
    }

    function createTransaction(
        string memory _toUserName,
        address _asset,
        uint256 _txEndTime,
        bool _arbitration,
        address[] memory _fromArbiters,
        bytes32 _claimCodeHash,
        uint256 _amount,
        string memory _description
    ) public payable {
        require(_usernameTaken[_toUserName], "Username Does Not Exist");
        require(_userSignedUp[msg.sender], "Sender Has Not Signed Up");

        if (_asset == address(0)) {
            require(msg.value >= _amount, "Insufficient Deposit Amount");
        } else {
            if (_asset == bridgeTokenAddress) {
                require(
                    _userDetails[msg.sender].bridgeTokenBalance >= _amount,
                    "Insufficient Bridge Account Balance"
                );
                _userDetails[msg.sender].bridgeTokenBalance -= _amount;
            } else {
                IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
            }
        }

        Transaction memory tx;
        transactions.push(tx);

        transactions[transactionIDCounter].ID = transactionIDCounter;
        transactions[transactionIDCounter].from = msg.sender;
        transactions[transactionIDCounter].fromUsername = _username[msg.sender];

        transactions[transactionIDCounter].to = getUserAddress(_toUserName);
        transactions[transactionIDCounter].toUsername = _toUserName;

        transactions[transactionIDCounter].asset = _asset;
        transactions[transactionIDCounter].amount = _amount;

        transactions[transactionIDCounter].claimCodeHash = _claimCodeHash;
        transactions[transactionIDCounter].description = _description;

        if (_arbitration) {
            require(_fromArbiters.length == 2, "Invalid Arbiters Length");
            require(
                _fromArbiters[0] != _fromArbiters[1],
                "Arbiters Not Unique"
            );

            transactions[transactionIDCounter]
                .arbDetails
                .fromArbiters = _fromArbiters;

            transactions[transactionIDCounter].claimCodeHash = _claimCodeHash;
            transactions[transactionIDCounter].description = _description;
            transactions[transactionIDCounter].arbitration = true;

            transactions[transactionIDCounter].state = 1;
            transactions[transactionIDCounter]
                .timeDetails
                .toBeSetTime = _txEndTime;
        } else {
            transactions[transactionIDCounter].state = 2;
            transactions[transactionIDCounter].timeDetails.txEndTime =
                block.timestamp +
                _txEndTime;
        }

        transactionIDCounter++;

        emit TransactionCreated(transactionIDCounter - 1, transactions[0]);
    }

    function acceptTransaction(
        address[] memory _toArbiters,
        uint256 _transactionID
    ) public {
        require(_toArbiters.length == 2, "Invalid Arbiters Length");
        require(_toArbiters[0] != _toArbiters[1], "Arbiters Not Unique");
        require(
            _transactionID <= transactionIDCounter,
            "Transaction Does Not Exist"
        );
        require(
            transactions[_transactionID].to == msg.sender,
            "Not Recipient For Transaction"
        );
        require(
            transactions[_transactionID].arbitration,
            "Transaction Does Not Require Acceptance"
        );
        require(
            transactions[_transactionID].state == 1,
            "Transaction Is Not In An Unaccepted State"
        );
        require(
            !transactions[_transactionID].arbDetails.retracted,
            "Transaction Has Been Retracted"
        );

        // CANT HAVE THE SAME ARBITER ON FROM AND TO
        require(
            _toArbiters[0] !=
                transactions[_transactionID].arbDetails.fromArbiters[0],
            "Cant Be The Same Arbiter As From"
        );
        require(
            _toArbiters[0] !=
                transactions[_transactionID].arbDetails.fromArbiters[1],
            "Cant Be The Same Arbiter As From"
        );

        require(
            _toArbiters[0] !=
                transactions[_transactionID].arbDetails.fromArbiters[0],
            "Cant Be The Same Arbiter As From"
        );
        require(
            _toArbiters[0] !=
                transactions[_transactionID].arbDetails.fromArbiters[1],
            "Cant Be The Same Arbiter As From"
        );

        transactions[_transactionID].arbDetails.toArbiters = _toArbiters;
        transactions[_transactionID].state = 2;
        transactions[_transactionID].timeDetails.txEndTime =
            block.timestamp +
            transactions[_transactionID].timeDetails.toBeSetTime;

        emit TransactionAccepted(_transactionID, transactions[_transactionID]);
    }

    function claimTransaction(
        uint256 _transactionID,
        string memory _claimCode
    ) public {
        require(
            _transactionID <= transactionIDCounter,
            "Transaction Does Not Exist"
        );
        require(
            transactions[_transactionID].to == msg.sender,
            "Not Recipient For Transaction"
        );
        require(
            transactions[_transactionID].state == 2,
            "Transaction Is Not In An Active State"
        );
        require(
            block.timestamp >
                transactions[_transactionID].timeDetails.txEndTime,
            "Transaction End Time Not Exceeded"
        );

        if (transactions[_transactionID].arbitration) {
            require(
                transactions[_transactionID].arbDetails.arbOutcome == 1,
                "Transaction Was Not Succesful"
            );
        }

        bool status = _validateCode(_claimCode, _transactionID);
        if (!status) {
            revert("Incorrect Claim Code");
        }

        transactions[_transactionID].timeDetails.claimed = true;

        if (transactions[_transactionID].asset == address(0)) {
            (bool success, ) = msg.sender.call{
                value: transactions[_transactionID].amount
            }(" ");

            require(success, "!sucessful");
        } else {
            if (transactions[_transactionID].asset == bridgeTokenAddress) {
                _userDetails[msg.sender].bridgeTokenBalance += transactions[
                    _transactionID
                ].amount;
            } else {
                IERC20(transactions[_transactionID].asset).transfer(
                    msg.sender,
                    transactions[_transactionID].amount
                );
            }
        }

        emit BetClaimed(_transactionID, transactions[_transactionID]);
    }

    // arbitrate transaction
    function arbitrateTransaction(uint256 _transactionID, bool _choice) public {
        require(
            _transactionID <= transactionIDCounter,
            "Transaction Does Not Exist"
        );
        bool anArbiter = _isUserAnArbiter(
            msg.sender,
            transactions[_transactionID].arbDetails.fromArbiters,
            transactions[_transactionID].arbDetails.toArbiters
        );
        require(anArbiter, "Not An Arbiter For This Bet");
        require(
            transactions[_transactionID].state == 2,
            "Transaction Is Not In An Active State"
        );

        require(
            !_hasMadeDecision[_transactionID][msg.sender],
            "Already Made Decision On Transaction"
        );
        require(
            block.timestamp >
                transactions[_transactionID].timeDetails.txEndTime,
            "Tx Wait Time Not Exceeded"
        );
        //
        //
        _hasMadeDecision[_transactionID][msg.sender] = true;

        if (_choice) {
            transactions[_transactionID].arbDetails.successArbitersCount += 1;
            if (
                transactions[_transactionID].arbDetails.successArbitersCount > 2
            ) {
                transactions[_transactionID].arbDetails.arbOutcome = 1;
            }
        } else {
            transactions[_transactionID].arbDetails.nullArbitersCount += 1;
            if (
                transactions[_transactionID].arbDetails.successArbitersCount ==
                2
            ) {
                transactions[_transactionID].arbDetails.arbOutcome = 2;
            }
        }

        // firewv event

        emit ArbitrateTransaction(_transactionID, transactions[_transactionID]);
    }

    // retract transaction
    function retractTransaction(uint256 _transactionID) public {
        require(
            _transactionID <= transactionIDCounter,
            "Transaction Does Not Exist"
        );
        require(
            !transactions[_transactionID].arbDetails.retracted,
            "Already Retracted!"
        );

        require(
            msg.sender == transactions[_transactionID].from,
            "Not Transaction Initiator"
        );
        require(
            transactions[_transactionID].state == 1,
            "Transaction Is Already Accepted! Cant Retract Now"
        );

        if (transactions[_transactionID].asset == address(0)) {
            (bool success, ) = msg.sender.call{
                value: transactions[_transactionID].amount
            }("");

            require(success, "!sucessful");
        } else {
            if (transactions[_transactionID].asset == bridgeTokenAddress) {
                _userDetails[msg.sender].bridgeTokenBalance += transactions[
                    _transactionID
                ].amount;
            } else {
                IERC20(transactions[_transactionID].asset).transfer(
                    msg.sender,
                    transactions[_transactionID].amount
                );
            }
        }

        transactions[_transactionID].arbDetails.retracted = true;

        emit TransactionRetracted(_transactionID, transactions[_transactionID]);
    }

    // ACCOUNT

    function fundAccount(uint256 _amount) public {
        require(
            IERC20(bridgeTokenAddress).balanceOf(msg.sender) >= _amount,
            "Insufficient Balance"
        );

        IERC20(bridgeTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        _userDetails[msg.sender].bridgeTokenBalance += _amount;
    }

    function withdrawFromAccount(uint256 _amount) public {
        require(
            _userDetails[msg.sender].bridgeTokenBalance >= _amount,
            "Insufficient Balance"
        );

        IERC20(bridgeTokenAddress).transfer(msg.sender, _amount);

        _userDetails[msg.sender].bridgeTokenBalance -= _amount;
    }

    // INTERNAL FUNCTIONS

    function _isUserAnArbiter(
        address _user,
        address[] memory _fromArbiters,
        address[] memory _toArbiters
    ) public pure returns (bool) {
        for (uint256 i = 0; i < _fromArbiters.length; i++) {
            if (_fromArbiters[i] == _user) {
                return true;
            }
        }

        for (uint256 i = 0; i < _toArbiters.length; i++) {
            if (_toArbiters[i] == _user) {
                return true;
            }
        }

        return false;
    }

    function _validateCode(
        string memory _code,
        uint256 _transactionID
    ) internal view returns (bool) {
        bytes32 codeHash = keccak256(bytes(_code));
        if (codeHash == transactions[_transactionID].claimCodeHash) {
            return true;
        } else {
            return false;
        }
    }

    // check handle validity
    function _checkUsernameValidity(string memory _userName) internal pure {
        bytes memory byteUserName = bytes(_userName);
        if (
            byteUserName.length == 0 ||
            byteUserName.length > MAX_USERNAME_LENGTH
        ) revert("Max Username Length Exceeded");

        uint256 byteUsernameLength = byteUserName.length;
        for (uint256 i = 0; i < byteUsernameLength; ) {
            if (
                (byteUserName[i] < "0" ||
                    byteUserName[i] > "z" ||
                    (byteUserName[i] > "9" && byteUserName[i] < "a")) ||
                byteUserName[i] == "." ||
                byteUserName[i] == "-" ||
                byteUserName[i] == "_"
            ) revert("Invalid Characters Used");

            unchecked {
                ++i;
            }
        }
    }

    // GETTER FUNCTIONS

    function getActiveTransactions(
        address _user
    ) public view returns (Transaction[] memory) {
        uint256 activeTransactionslistLength;

        for (uint i = 0; i < transactions.length; i++) {
            if (
                transactions[i].state == 2 &&
                block.timestamp < transactions[i].timeDetails.txEndTime
            ) {
                if (
                    transactions[i].from == _user || transactions[i].to == _user
                ) {
                    activeTransactionslistLength++;
                }
            }
        }

        Transaction[] memory activeTransactions = new Transaction[](
            activeTransactionslistLength
        );
        uint256 indexCounter;

        for (uint i = 0; i < transactions.length; i++) {
            if (
                transactions[i].state == 2 &&
                block.timestamp < transactions[i].timeDetails.txEndTime
            ) {
                if (
                    transactions[i].from == _user || transactions[i].to == _user
                ) {
                    activeTransactions[indexCounter] = transactions[i];
                    indexCounter++;
                }
            }
        }

        return activeTransactions;
    }

    function getCompletedTransctions(
        address _user
    ) public view returns (Transaction[] memory) {
        uint256 completedTransactionsListLength;

        for (uint i = 0; i < transactions.length; i++) {
            if (transactions[i].arbitration) {
                if (transactions[i].arbDetails.arbOutcome != 0) {
                    if (
                        transactions[i].from == _user ||
                        transactions[i].to == _user
                    ) {
                        completedTransactionsListLength++;
                    }
                }
            } else {
                if (block.timestamp > transactions[i].timeDetails.txEndTime) {
                    if (
                        transactions[i].from == _user ||
                        transactions[i].to == _user
                    ) {
                        completedTransactionsListLength++;
                    }
                }
            }
        }

        Transaction[] memory completedTransactions = new Transaction[](
            completedTransactionsListLength
        );
        uint256 indexCounter;

        for (uint i = 0; i < transactions.length; i++) {
            if (transactions[i].arbitration) {
                if (transactions[i].arbDetails.arbOutcome != 0) {
                    if (
                        transactions[i].from == _user ||
                        transactions[i].to == _user
                    ) {
                        completedTransactions[indexCounter] = transactions[i];
                        indexCounter++;
                    }
                }
            } else {
                if (block.timestamp > transactions[i].timeDetails.txEndTime) {
                    if (
                        transactions[i].from == _user ||
                        transactions[i].to == _user
                    ) {
                        completedTransactions[indexCounter] = transactions[i];
                        indexCounter++;
                    }
                }
            }
        }

        return completedTransactions;
    }

    function getUnacceptedTransactions(
        address _user
    ) public view returns (Transaction[] memory) {
        uint256 unacceptedTransactionslistLength;

        for (uint i = 0; i < transactions.length; i++) {
            if (transactions[i].state == 1) {
                if (transactions[i].to == _user) {
                    unacceptedTransactionslistLength++;
                }
            }
        }

        Transaction[] memory unacceptedTransactions = new Transaction[](
            unacceptedTransactionslistLength
        );
        uint256 indexCounter;

        for (uint i = 0; i < transactions.length; i++) {
            if (transactions[i].state == 1) {
                if (transactions[i].to == _user) {
                    unacceptedTransactions[indexCounter] = transactions[i];
                    indexCounter++;
                }
            }
        }

        return unacceptedTransactions;
    }

    function getPendingTransactions(
        address _user
    ) public view returns (Transaction[] memory) {
        uint256 pendingTransactionslistLength;

        for (uint i = 0; i < transactions.length; i++) {
            if (
                transactions[i].state == 2 &&
                block.timestamp > transactions[i].timeDetails.txEndTime &&
                transactions[i].arbitration
            ) {
                if (
                    transactions[i].from == _user || transactions[i].to == _user
                ) {
                    pendingTransactionslistLength++;
                }
            }
        }

        Transaction[] memory pendingTransactions = new Transaction[](
            pendingTransactionslistLength
        );
        uint256 indexCounter;

        for (uint i = 0; i < transactions.length; i++) {
            if (
                transactions[i].state == 2 &&
                block.timestamp > transactions[i].timeDetails.txEndTime &&
                transactions[i].arbitration
            ) {
                if (
                    transactions[i].from == _user || transactions[i].to == _user
                ) {
                    pendingTransactions[indexCounter] = transactions[i];
                    indexCounter++;
                }
            }
        }

        return pendingTransactions;
    }

    function getUserDetails(
        address _user
    ) public view returns (UserDetails memory) {
        return _userDetails[_user];
    }

    function isArbiterForTransaction(
        uint256 _transactionID,
        address _user
    ) public view returns (bool) {
        bool isArbiter = _isUserAnArbiter(
            _user,
            transactions[_transactionID].arbDetails.fromArbiters,
            transactions[_transactionID].arbDetails.toArbiters
        );

        return isArbiter;
    }

    function getIsSender(
        address _user,
        uint256 _transactionID
    ) public view returns (bool) {
        if (transactions[_transactionID].from == _user) {
            return true;
        } else {
            return false;
        }
    }

    function getIsRecipient(
        address _user,
        uint256 _transactionID
    ) public view returns (bool) {
        if (transactions[_transactionID].to == _user) {
            return true;
        } else {
            return false;
        }
    }

    function getUsername(address _user) public view returns (string memory) {
        return _username[_user];
    }

    function getUserAddress(
        string memory _userName
    ) public view returns (address) {
        return _usernameToAddress[_userName];
    }

    function getCurrentTimestamp() public view returns (uint256) {
        return block.timestamp;
    }
}
