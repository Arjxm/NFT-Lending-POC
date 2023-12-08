// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./NFTCollateral.sol";
import "./Automate/AutomateTaskCreator.sol";

contract Lending is NFTCollateral, AutomateTaskCreator {
    IERC721 public nft;
    IERC20 public burrToken;
    uint256 public interestRate;
    address public owner;

    struct Loan {
        address borrower;
        uint256 amount;
        uint256 dueDate;
        bool isActive;
        uint256 tokenId;
        address nftAddress;
    }

    mapping(address => Loan) public loans;
    address[] public borrowerAddresses;

    event NFTDeposited(
        address indexed user,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 amount
    );
    event Liquidation(
        address indexed liquidator,
        address indexed borrower,
        uint256 nftId
    );
    event FundsSent(address indexed recipient, uint256 amount);
    event TaskCreated(bytes32 taskId);

    constructor(
        address payable _automate,
        address _fundsOwner
    ) AutomateTaskCreator(_automate, _fundsOwner) {
        owner = payable(msg.sender);
    }

    function createTaskForAutomaticLiquidation()
        external
        returns (bytes32 taskId)
    {
        require(taskId == bytes32(0), "Already started task");

        ModuleData memory moduleData = ModuleData({
            modules: new Module[](2),
            args: new bytes[](2)
        });

        moduleData.modules[0] = Module.RESOLVER;
        moduleData.modules[1] = Module.PROXY;

        moduleData.args[0] = _resolverModuleArg(
            address(this),
            abi.encodeWithSelector(this.checker.selector)
        );
        moduleData.args[1] = _proxyModuleArg();

        bytes32 id = _createTask(
            address(this),
            abi.encodeWithSelector(this.liquidate.selector),
            moduleData,
            ETH
        );

        taskId = id;
        emit TaskCreated(id);
        return id;
    }

    function _sendFunds(address _recipient, uint256 _amount) internal {
        require(
            address(this).balance >= _amount,
            "Insufficient funds in the contract"
        );
        (bool success, ) = payable(_recipient).call{value: _amount}("");
        require(success, "Failed to send funds");
        emit FundsSent(_recipient, _amount);
    }

    function AddFundToContract() public payable {
        require(msg.value > 0, "Must send Ether to stake");
    }

    function depositNFT(address nftAddress, uint256 tokenId) external {
        uint256 _amount = _depositNFT(nftAddress, tokenId);
        Loan memory newLoan = Loan({
            borrower: msg.sender,
            amount: _amount,
            dueDate: block.timestamp + 30 days,
            isActive: true,
            tokenId: tokenId,
            nftAddress: nftAddress
        });
        loans[msg.sender] = newLoan;
        // Add borrower to the list
        borrowerAddresses.push(msg.sender);

        // Send native currency to the user
        payable(msg.sender).transfer(_amount);

        //Create task

        // Emit the event to notify the frontend
        emit NFTDeposited(msg.sender, nftAddress, tokenId, _amount);
    }

    function liquidate(
        address _borrower,
        uint256 _tokenId,
        address nftAddress
    ) public {
        Loan storage loan = loans[_borrower];

        require(loan.isActive, "Loan is not active");
        require(block.timestamp > loan.dueDate, "Loan is not overdue");

        // Ensure the NFT is owned by the contract
        require(
            IERC721(nftAddress).ownerOf(_tokenId) == address(this),
            "NFT not owned by the contract"
        );

        // Transfer the NFT from the contract to the liquidator (msg.sender)
        IERC721(nftAddress).transferFrom(address(this), owner, _tokenId);

        loan.isActive = false;

        // Emit the event to notify the frontend
        emit Liquidation(msg.sender, _borrower, _tokenId);
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        for (uint256 i = 0; i < borrowerAddresses.length; i++) {
            address borrower = borrowerAddresses[i];
            Loan storage loan = loans[borrower];

            if (loan.isActive && block.timestamp > loan.dueDate + 10 days) {
                // If the loan is active and overdue by more than 10 days, create a liquidation payload
                bytes memory payload = abi.encodeWithSelector(
                    this.liquidate.selector,
                    borrower,
                    loan.tokenId,
                    loan.nftAddress
                );

                return (true, payload);
            }
        }

        // If no action is required, return canExec=false and an empty payload
        return (false, "");
    }
}
