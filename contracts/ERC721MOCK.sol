// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "erc721a/contracts/ERC721A.sol";

contract ERC721MOCK is ERC721A {

    constructor() ERC721A("721Mock", "MOCK") {}

    function mint() external {
        _safeMint(msg.sender, 1, "");
    }
}
