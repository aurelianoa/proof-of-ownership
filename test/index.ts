import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish, Signer } from "ethers";
import { ERC721MOCK, Proof } from "../typechain";

describe("Proof of ownership", function () {
  let owner: Signer;
  let cold: Signer;
  let hot: Signer;
  let hot2: Signer;
  let ownerAddress: string;
  let coldAddress: string;
  let hotAddress: string;
  let hot2Address: string;
  let proofContract: Proof;
  let mockContract: ERC721MOCK;
  let tokenId: BigNumberish;
  let certTokenId: BigNumberish;

  beforeEach(async function () {
    [owner, cold, hot, hot2] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    coldAddress = await cold.getAddress();
    hotAddress = await hot.getAddress();
    hot2Address = await hot2.getAddress();
    const proof = await ethers.getContractFactory("ProofERC721");
    proofContract = await proof
      .connect(owner)
      .deploy("Proof of ownership", "POO");
    await proofContract.deployed();
    await proofContract.connect(owner).setIsActive(true);
    const mock = await ethers.getContractFactory("ERC721MOCK");
    mockContract = await mock.deploy();
    await mockContract.deployed();
    await mockContract.connect(cold).mint();
    tokenId = 0;
    certTokenId = 0;
  });

  it("Contract must be active", async function () {
    expect(await proofContract.isContractActive()).to.equal(true);
  });

  it("User must mint a ERC721 token", async function () {
    expect(await mockContract.ownerOf(tokenId)).to.equal(coldAddress);
  });
  describe("Create Certificate of Proof of ownership token", function () {
    beforeEach(async function () {
      await proofContract
        .connect(owner)
        .setValidator(mockContract.address, true);
      await proofContract.connect(hot).makeCert(mockContract.address, tokenId);
    });
    it("must receive the certToken", async function () {
      expect(await proofContract.ownerOf(certTokenId)).to.equal(coldAddress);
    });
    it("must complete the certification process", async function () {
      await proofContract
        .connect(cold)
        .transferFrom(coldAddress, hotAddress, 0);
      expect(await proofContract.ownerOf(certTokenId)).to.equal(hotAddress);
      await expect(
        proofContract.connect(hot).transferFrom(hotAddress, hot2Address, 0)
      ).to.be.revertedWith(
        `NoTransferAllowed("${hotAddress}", "${hot2Address}")`
      );
    });
  });

  describe("Validate Certificate", function () {
    beforeEach(async function () {
      await proofContract
        .connect(owner)
        .setValidator(mockContract.address, true);
      await proofContract.connect(hot).makeCert(mockContract.address, tokenId);
      await proofContract
        .connect(cold)
        .transferFrom(coldAddress, hotAddress, 0);
    });
    it("certificate Should be valid", async function () {
      expect(await proofContract.isValid(certTokenId, hotAddress)).to.equal(
        true
      );
    });
  });

  describe("Updating Authorized Holder", function () {
    beforeEach(async function () {
      await proofContract
        .connect(owner)
        .setValidator(mockContract.address, true);
      await proofContract.connect(hot).makeCert(mockContract.address, tokenId);
      await proofContract
        .connect(cold)
        .transferFrom(coldAddress, hotAddress, 0);
    });
    it("certificate can be Updated", async function () {
      await proofContract.connect(hot2).makeCert(mockContract.address, tokenId);
      expect(await proofContract.ownerOf(1)).to.equal(coldAddress);
      await proofContract
        .connect(cold)
        .transferFrom(coldAddress, hot2Address, 1);
      expect(await proofContract.ownerOf(1)).to.equal(hot2Address);
      expect(await proofContract.isValid(0, hotAddress)).to.equal(false);
    });
    it("Certificate can be burnt", async function () {
      await expect(
        proofContract
          .connect(hot)
          .transferFrom(
            hotAddress,
            ethers.utils.getAddress(
              "0x0000000000000000000000000000000000000000"
            ),
            0
          )
      ).to.not.be.revertedWith(
        `NoTransferAllowed("${hotAddress}", "${ethers.utils.getAddress(
          "0x0000000000000000000000000000000000000000"
        )}")`
      );
    });
  });
});
