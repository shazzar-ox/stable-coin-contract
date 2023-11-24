// SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

contract Nft {
    address immutable owner;

    struct GroupLength {
        uint256 A;
        uint256 B;
        uint256 C;
    }

    constructor() {
        owner = msg.sender;
    }

    mapping(uint256 group => address[]) public groupAddresses;
    mapping(uint256 group => mapping(address user => uint256 timeStamp)) public lists;

    modifier onlyOwner() {
        require(owner == msg.sender, "revert");
        _;
    }

    function addWhitelistAddress(uint256 groupNumber, address[] calldata userAddress, uint256 timeStamp) external {
        address[] memory users = new address[](userAddress.length);
        for (uint256 i = 0; i < userAddress.length; i++) {
            lists[groupNumber][userAddress[i]] = timeStamp;
            users[i] = userAddress[i];
        }
        groupAddresses[groupNumber] = users;
    }

    function updateWhitelist(uint256 groupNumber, uint256 timeStamp) external {
        uint256 userLength = groupAddresses[groupNumber].length;
        address[] memory users = groupAddresses[groupNumber];

        for (uint256 i = 0; i < userLength; i++) {
            lists[groupNumber][users[i]] = timeStamp;
        }
    }
}
