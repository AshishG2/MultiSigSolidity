// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SecureMultiWallet {
    event FundsDeposited(address indexed depositor, uint amount, uint newBalance);
    event TransactionSubmitted(
        address indexed initiator,
        uint indexed txID,
        address indexed target,
        uint amount,
        bytes payload
    );
    event TransactionConfirmed(address indexed approver, uint indexed txID);
    event ConfirmationRevoked(address indexed approver, uint indexed txID);
    event TransactionExecuted(address indexed executor, uint indexed txID);

    address[] public authorizedUsers;
    mapping(address => bool) public isAuthorized;
    uint public requiredApprovals;

    struct PendingTransaction {
        address target;
        uint amount;
        bytes payload;
        bool hasBeenExecuted;
        uint approvalCount;
    }

    // mapping from tx ID => approver => bool
    mapping(uint => mapping(address => bool)) public hasConfirmed;

    PendingTransaction[] public pendingTransactions;

    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "Unauthorized");
        _;
    }

    modifier transactionExists(uint _txID) {
        require(_txID < pendingTransactions.length, "Transaction not found");
        _;
    }

    modifier notYetExecuted(uint _txID) {
        require(!pendingTransactions[_txID].hasBeenExecuted, "Transaction already executed");
        _;
    }

    modifier notYetConfirmed(uint _txID) {
        require(!hasConfirmed[_txID][msg.sender], "Transaction already approved");
        _;
    }

    constructor(address[] memory _users, uint _requiredApprovals) {
        require(_users.length > 0, "Users required");
        require(
            _requiredApprovals > 0 &&
                _requiredApprovals <= _users.length,
            "Invalid approval count"
        );

        for (uint i = 0; i < _users.length; i++) {
            address user = _users[i];

            require(user != address(0), "Invalid user");
            require(!isAuthorized[user], "Duplicate user");

            isAuthorized[user] = true;
            authorizedUsers.push(user);
        }

        requiredApprovals = _requiredApprovals;
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value, address(this).balance);
    }

    function addTransaction(
        address _target,
        uint _amount,
        bytes memory _payload
    ) public onlyAuthorized {
        uint txID = pendingTransactions.length;

        pendingTransactions.push(
            PendingTransaction({
                target: _target,
                amount: _amount,
                payload: _payload,
                hasBeenExecuted: false,
                approvalCount: 0
            })
        );

        emit TransactionSubmitted(msg.sender, txID, _target, _amount, _payload);
    }

    function approveTransaction(
        uint _txID
    ) public onlyAuthorized transactionExists(_txID) notYetExecuted(_txID) notYetConfirmed(_txID) {
        PendingTransaction storage pendingTx = pendingTransactions[_txID];
        pendingTx.approvalCount += 1;
        hasConfirmed[_txID][msg.sender] = true;

        emit TransactionConfirmed(msg.sender, _txID);
    }

    function runTransaction(
        uint _txID
    ) public onlyAuthorized transactionExists(_txID) notYetExecuted(_txID) {
        PendingTransaction storage pendingTx = pendingTransactions[_txID];

        require(
            pendingTx.approvalCount >= requiredApprovals,
            "Insufficient approvals"
        );

        pendingTx.hasBeenExecuted = true;

        (bool success, ) = pendingTx.target.call{value: pendingTx.amount}(
            pendingTx.payload
        );
        require(success, "Transaction execution failed");

        emit TransactionExecuted(msg.sender, _txID);
    }

    function retractApproval(
        uint _txID
    ) public onlyAuthorized transactionExists(_txID) notYetExecuted(_txID) {
        PendingTransaction storage pendingTx = pendingTransactions[_txID];

        require(hasConfirmed[_txID][msg.sender], "No prior approval found");

        pendingTx.approvalCount -= 1;
        hasConfirmed[_txID][msg.sender] = false;

        emit ConfirmationRevoked(msg.sender, _txID);
    }

    function listUsers() public view returns (address[] memory) {
        return authorizedUsers;
    }

    function countTransactions() public view returns (uint) {
        return pendingTransactions.length;
    }

    function fetchTransaction(
        uint _txID
    )
        public
        view
        returns (
            address target,
            uint amount,
            bytes memory payload,
            bool hasBeenExecuted,
            uint approvalCount
        )
    {
        PendingTransaction storage pendingTx = pendingTransactions[_txID];

        return (
            pendingTx.target,
            pendingTx.amount,
            pendingTx.payload,
            pendingTx.hasBeenExecuted,
            pendingTx.approvalCount
        );
    }
}
