// SPDX-License-Identifier: UNLICENSED

/// Proof of ownership ERC721
/// @author dev.aurelianoa.eth
pragma solidity ^0.8.9;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @dev This is a work in progress and the general idea is to provide a mechanism where the owner of a certain ERC721
/// token can validate the ownership of its token without interacting with the wallet that owns the token.
/// This case is referred as a cold wallet mechanism where the owner transfer valuable assets to a wallet that
/// never interacts with other contracts. But this bring the necessity of having a way to verify the ownership
/// of a token in the cold wallet for social verification such twitter, discord, party events, and other benefits like
/// mint in other contracts that will require to hold the token.
/// The mechanism proposes that the owner of the tokenId in a cold wallet can authorize another wallet (hot) to hold a
/// certificate of proof of ownership. this certificate hold the necessary data to be verifiable by this contract
/// Key Points:
/// - The certificate is requested by the (hot) wallet and the system after certain verification
///   (cold + contract + tokenId), will mint (send) the cert to the cold wallet and setting the (hot) wallet as a
///   authorizedHolder. Then the cold wallet must transfer the certificate back to the (hot) wallet in order to the
///   certificate to become valid and the certification process to be completed. If the certificate is elsewhere
///   (including the cold wallet) it will be NOT valid.
/// - This contract represent a validator that will register as many ERC721 contracts to validate.
///   The validation is only possible against who wants to validate.
///   For example RTFKT will use this contract to register the collections who wants to validate
/// TODO: create a proxy system to create multiple contract for each validator.

contract ProofERC721 is ERC721A, Ownable {
    using Strings for uint256;

    bool public isActive = false;

    struct ERC721MetaData {
        address contractAddress;
        uint256 tokenId;
        address ownerAddress;
        address authorizedHolder;
        uint256 issuedTime;
    }
    /// tokenId => metadata
    mapping(uint256 => ERC721MetaData) private ownership;

    /// contracts to be validated
    mapping(address => bool) private validators;

    /// address+contract+id => tokenId
    mapping(string => uint256) private activeCerts;

    /// Errors
    error NoTransferAllowed(address from, address to);

    constructor(string memory name, string memory symbol) ERC721A(name, symbol) {}

    function setIsActive(bool active) external onlyOwner {
        isActive = active;
    }

    function isContractActive() external view returns (bool) {
        return isActive;
    }
    /// @param contractAddress address
    /// @param active bool
    function setValidator(address contractAddress, bool active) external onlyOwner {
        require(isActive == true, "the contract is not active");
        IERC721 token = IERC721(contractAddress);

        require(token.supportsInterface(type(IERC721).interfaceId), "no ERC721 support");

        validators[contractAddress] = active;
    }
    /// @notice This will create a unique key owner+contract+id
    /// @param ownerAddress address
    /// @param contractAddress address
    /// @param tokenId uint256
    /// @return string memory
    function _encodeKey(address ownerAddress, address contractAddress, uint256 tokenId) internal
    pure returns (string memory) {
        return string(abi.encodePacked(ownerAddress, contractAddress, tokenId.toString()));
    }

    /// @param _certificateTokenId uint256
    /// @return string memory
    function encodeKey(uint256 _certificateTokenId) internal view returns (string memory) {
        ERC721MetaData memory metaData = ownership[_certificateTokenId];
        return _encodeKey(metaData.ownerAddress, metaData.contractAddress, metaData.tokenId);
    }

    /// TODO: sign approve from the hot wallet
    /// @dev The contract will check the existence and ownership of the tokenId,
    /// then it will mint (send) the certTokenId to the cold wallet owner of the tokenId
    /// @notice After this the cold must transfer the cer to the hot (authorized) wallet in order to complete
    /// the verification, otherwise the certificate will be not valid
    /// @param contractAddress address
    /// @param tokenId uint256
    function makeCert(address contractAddress, uint256 tokenId) external {
        require(isActive == true, "the contract is not active");
        require(validators[contractAddress] == true, "Validator not active");

        IERC721 token = IERC721(contractAddress);
        address ownerAddress = token.ownerOf(tokenId);

        require(token.supportsInterface(type(IERC721).interfaceId), "no ERC721 support");
        require(ownerAddress != address (0), "Owner doesnt exist");

        ERC721MetaData memory metaData = ERC721MetaData(
            contractAddress,
            tokenId,
            ownerAddress,
            msg.sender,
            block.timestamp
        );

        string memory encodedKey = _encodeKey(ownerAddress, contractAddress, tokenId);

        /// @dev checking if there is not another certificate out there
        require(activeCerts[encodedKey] == 0, "Cert Already activated");

        ownership[totalSupply()] = metaData;

        _safeMint(ownerAddress, 1, "");
    }

    /// @notice isValid will consider for the authorizedHolder to hold the certificate, The token to ve verified must
    /// be on the owners wallet (cold), the certificate must have the authorizedHolder as the same as the
    /// _authorizedAddress, and the certificate must be active in the activeCerts
    /// @param _certificateTokenId uint256
    /// @param _authorizedAddress address
    /// @return bool
    function isValid(uint256 _certificateTokenId, address _authorizedAddress) external view returns (bool) {
        // TODO: hot wallet must be recovered from signature
        require(ownerOf(_certificateTokenId) == _authorizedAddress, "You dont own this cert");

        bool _isValid = true;

        ERC721MetaData memory metaData = ownership[_certificateTokenId];

        require(validators[metaData.contractAddress] == true, "Validator not active");

        string memory encodedKey = encodeKey(_certificateTokenId);
        IERC721 token = IERC721(metaData.contractAddress);

        if(
            token.ownerOf(metaData.tokenId) != metaData.ownerAddress ||
            activeCerts[encodedKey] != _certificateTokenId ||
            metaData.authorizedHolder != _authorizedAddress
        )
            _isValid = false;

        return _isValid;
    }

    /// ERC721A override
    /// @notice this will create a strict mechanism where its only possible the transfer
    /// from the cold wallet to the hot wallet, from the contract to the cold wallet (token creation) and
    /// from the (cold or hot) wallet to address(0) (burn)
    /// this will prevent malicious behaviour where a certificate can be easily transferred.
    /// The only way to Update/Transfer the certificate is creating a new one by repeating the process.
    function _beforeTokenTransfers(address from, address to, uint256 startTokenId, uint256 quantity) internal
    virtual override {
        address nullAddress = address(0);
        if(
            to == nullAddress ||
            from == nullAddress && to == ownership[startTokenId].ownerAddress ||
            from == ownership[startTokenId].ownerAddress && to == ownership[startTokenId].authorizedHolder
        ) {
            super._beforeTokenTransfers(from, to, startTokenId, quantity);
        } else {
            revert NoTransferAllowed(from, to);
        }

    }

    /// ERC721A override
    /// @notice The authorizeHolder will be update leaving the old cert invalid if exists.
    function _afterTokenTransfers(address from, address to, uint256 startTokenId, uint256 quantity) internal
    virtual override {
        string memory encodedKey = encodeKey(startTokenId);
        ///_burn(activeCerts[encodedKey]);
        delete activeCerts[encodedKey];
        activeCerts[encodedKey] = startTokenId;

        super._afterTokenTransfers(from, to, startTokenId, quantity);
    }
}