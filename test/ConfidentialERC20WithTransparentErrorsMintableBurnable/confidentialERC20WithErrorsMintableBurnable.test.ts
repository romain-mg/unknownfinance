import { expect } from "chai";
import { LogDescription } from "ethers";
import { ethers } from "hardhat";

import { fhevm } from "../../types";
import { awaitAllDecryptionResults } from "../asyncDecrypt";
import { createInstance } from "../instance";
import { reencryptEuint64 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployConfidentialERC20WithErrorsMintableBurnableFixture } from "./confidentialERC20WithErrorsMintableBurnable.fixture";

describe("ConfidentialERC20WithErrorsMintableBurnable", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const confidentialERC20 = await deployConfidentialERC20WithErrorsMintableBurnableFixture();
    this.confidentialERC20 = confidentialERC20;
    this.confidentialERC20ContractAddress = await confidentialERC20.getAddress();
    this.fhevm = await createInstance();
  });

  it("should mint the confidential erc20", async function () {
    const alice = this.signers.alice;
    const mintErc20 = await this.confidentialERC20.mint(alice, 1000);
    await mintErc20.wait();
    const balanceHandleAlice = await this.confidentialERC20.balanceOf(alice);
    const encryptedTokenBalanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.confidentialERC20ContractAddress,
    );
    expect(encryptedTokenBalanceAlice).to.equal(1000);
  });

  it("should burn the confidential erc20", async function () {
    const alice = this.signers.alice;
    const mintErc20 = await this.confidentialERC20.mint(alice, 1000);
    await mintErc20.wait();
    const burnErc20 = await this.confidentialERC20.connect(alice).burn(1000);
    await burnErc20.wait();
    const balanceHandleAlice = await this.confidentialERC20.balanceOf(alice);
    const encryptedTokenBalanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.confidentialERC20ContractAddress,
    );
    expect(encryptedTokenBalanceAlice).to.equal(0);
  });
});
