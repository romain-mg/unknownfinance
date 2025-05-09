import { expect } from "chai";
import { LogDescription } from "ethers";

import { awaitAllDecryptionResults, initGateway } from "../asyncDecrypt";
import { createInstance } from "../instance";
import { reencryptEuint64 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployConfidentialERC20WithErrorsWrappedFixture } from "./confidentialERC20WithErrorsWrapped.fixture";
import { deployERC20Fixture } from "./testERC20.fixture";

describe("ConfidentialERC20Wrapper", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
    await initGateway();
  });

  beforeEach(async function () {
    const erc20 = await deployERC20Fixture("ERC20", "ERC20");
    const wrapperContract = await deployConfidentialERC20WithErrorsWrappedFixture(erc20);
    this.wrapperContractAddress = await wrapperContract.getAddress();
    this.erc20 = erc20;
    this.wrapperContract = wrapperContract;
    this.fhevm = await createInstance();
  });

  it("should wrap the erc20 into a confidential erc20", async function () {
    const amountToWrapUnwrap = 1000;
    const alice = this.signers.alice;
    const mintErc20 = await this.erc20.mint(alice, amountToWrapUnwrap);
    await mintErc20.wait();
    const approveErc20 = await this.erc20.connect(alice).approve(this.wrapperContractAddress, amountToWrapUnwrap);
    await approveErc20.wait();
    const wrapErc20 = await this.wrapperContract.connect(alice).wrap(amountToWrapUnwrap);
    await wrapErc20.wait();
    // Reencrypt Alice's balance
    const balanceHandleAlice = await this.wrapperContract.balanceOf(this.signers.alice);
    const encryptedTokenBalanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.wrapperContractAddress,
    );
    expect(encryptedTokenBalanceAlice).to.equal(amountToWrapUnwrap);
    const originalTokenBalanceAlice = await this.erc20.balanceOf(this.signers.alice);
    expect(originalTokenBalanceAlice).to.equal(0);
    const totalSupply = await this.wrapperContract.totalSupply();
    expect(totalSupply).to.equal(amountToWrapUnwrap);
  });

  it("should unwrap the confidential erc20 into the original erc20", async function () {
    const amountToWrapUnwrap = 1000;
    const alice = this.signers.alice;
    const mintErc20 = await this.erc20.mint(alice, amountToWrapUnwrap);
    await mintErc20.wait();
    const approveErc20 = await this.erc20.connect(alice).approve(this.wrapperContractAddress, amountToWrapUnwrap);
    await approveErc20.wait();
    const wrapErc20 = await this.wrapperContract.connect(alice).wrap(amountToWrapUnwrap);
    await wrapErc20.wait();

    const withdrawErc20 = await this.wrapperContract.connect(alice).unwrap(amountToWrapUnwrap);
    await withdrawErc20.wait();
    await awaitAllDecryptionResults();
    const balanceAlice = await this.erc20.balanceOf(alice);
    expect(balanceAlice).to.equal(amountToWrapUnwrap);
  });
});
