import { expect } from "chai";
import { LogDescription } from "ethers";
import { ethers } from "hardhat";

import { fhevm } from "../../types";
import { awaitAllDecryptionResults, initGateway } from "../asyncDecrypt";
import { awaitCoprocessor } from "../coprocessorUtils";
import { createInstance } from "../instance";
import { reencryptEuint64 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployConfidentialERC20WithErrorsMintableBurnableFixture } from "./confidentialERC20WithErrorsMintableBurnable.fixture";
import { deployConfidentialIndexFundFixture } from "./confidentialIndexFund.fixture";

describe("ConfidentialIndexFund", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
    await initGateway();
  });

  beforeEach(async function () {
    const [
      confidentialIndexFund,
      indexFundFactory,
      indexFundToken,
      wrappedStablecoin,
      testStablecoin,
      firstTestERC20,
      secondTestERC20,
      mockMarketDataFetcher,
      mockSwapsManager,
    ] = await deployConfidentialIndexFundFixture();
    this.confidentialIndexFund = confidentialIndexFund;
    this.indexFundFactory = indexFundFactory;
    this.wrappedStablecoin = wrappedStablecoin;
    this.testStablecoin = testStablecoin;
    this.firstTestERC20 = firstTestERC20;
    this.secondTestERC20 = secondTestERC20;
    this.mockMarketDataFetcher = mockMarketDataFetcher;
    this.mockSwapsManager = mockSwapsManager;
    this.confidentialIndexFundContractAddress = await confidentialIndexFund.getAddress();
    this.indexFundFactoryContractAddress = await indexFundFactory.getAddress();
    this.indexFundToken = indexFundToken;
    this.indexFundTokenContractAddress = await indexFundToken.getAddress();
    this.wrappedStablecoinContractAddress = await wrappedStablecoin.getAddress();
    this.testStablecoinContractAddress = await testStablecoin.getAddress();
    this.firstTestERC20ContractAddress = await firstTestERC20.getAddress();
    this.secondTestERC20ContractAddress = await secondTestERC20.getAddress();
    this.mockMarketDataFetcherContractAddress = await mockMarketDataFetcher.getAddress();
    this.mockSwapsManagerContractAddress = await mockSwapsManager.getAddress();
    this.fhevm = await createInstance();
    // Prepare mock swap manager and market data fetcher
    const nextSwapAmountOut = 1;
    const setMockSwaps = await this.mockSwapsManager.setNextAmountOut(nextSwapAmountOut);
    await setMockSwaps.wait();
    const setMockMarketData = await this.mockMarketDataFetcher.setIndexMarketCaps(1000, [500, 500]);
    await setMockMarketData.wait();

    // Mint the stablecoin
    const alice = this.signers.alice;
    const sharesMintStablecoinAmount = BigInt("1000");
    this.sharesMintStablecoinAmount = sharesMintStablecoinAmount;
    const mintTx = await this.testStablecoin.mint(alice.address, sharesMintStablecoinAmount);
    await mintTx.wait();

    // Wrap the stablecoin
    const approveStablecoinForWrap = await this.testStablecoin
      .connect(alice)
      .approve(this.wrappedStablecoinContractAddress, sharesMintStablecoinAmount);
    await approveStablecoinForWrap.wait();
    const wrapStablecoin = await this.wrappedStablecoin.connect(alice).wrap(sharesMintStablecoinAmount);
    await wrapStablecoin.wait();

    // Mint index fund tokens in the index fund balance (take decimals into account)
    const mint1 = await this.firstTestERC20.mint(this.confidentialIndexFundContractAddress, 1e6);
    await mint1.wait();

    const mint2 = await this.secondTestERC20.mint(this.confidentialIndexFundContractAddress, 1e6);
    await mint2.wait();

    // Approve the wrapped stablecoin for the index fund
    const approveInput = this.fhevm.createEncryptedInput(this.wrappedStablecoinContractAddress, alice.address);
    approveInput.add64(sharesMintStablecoinAmount);
    const encryptedApproveAmount = await approveInput.encrypt();

    const approveStablecoin = await this.wrappedStablecoin
      .connect(alice)
      ["approve(address,bytes32,bytes)"](
        this.confidentialIndexFundContractAddress,
        encryptedApproveAmount.handles[0],
        encryptedApproveAmount.inputProof,
      );
    await approveStablecoin.wait();
  });

  it("should correctly mint shares when minting conditions are met", async function () {
    const alice = this.signers.alice;
    // Mint shares
    const mintInput = this.fhevm.createEncryptedInput(this.confidentialIndexFundContractAddress, alice.address);
    mintInput.add64(this.sharesMintStablecoinAmount);
    const encryptedMintAmount = await mintInput.encrypt();

    const mintShares = await this.confidentialIndexFund
      .connect(alice)
      .mintShares(encryptedMintAmount.handles[0], encryptedMintAmount.inputProof);
    await mintShares.wait();

    await awaitAllDecryptionResults();
    await awaitCoprocessor();

    const finishMintShares = await this.confidentialIndexFund.connect(alice).finishMintShares(alice.address);
    await finishMintShares.wait();

    await awaitAllDecryptionResults(); // fulfills unwrap(canUnwrap)
    await awaitCoprocessor();
    // check if stablecoin transfer has been initiated
    const balanceHandleAlice = await this.wrappedStablecoin.balanceOf(this.signers.alice);
    const encryptedStablecoinBalanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.wrappedStablecoinContractAddress,
    );
    expect(encryptedStablecoinBalanceAlice).to.equal(0);

    // check if shares have been minted

    const encryptedSharesMintedHandleAlice = await this.indexFundToken.balanceOf(this.signers.alice);
    const encryptedsharesMintedAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      encryptedSharesMintedHandleAlice,
      this.indexFundTokenContractAddress,
    );

    const shareValue = await this.confidentialIndexFund.getSharePrice();
    const feeDivisor = await this.indexFundFactory.feeDivisor();
    const expectedSharesMintAmount =
      (this.sharesMintStablecoinAmount - this.sharesMintStablecoinAmount / feeDivisor) / shareValue;
    expect(encryptedsharesMintedAlice).to.equal(expectedSharesMintAmount);

    const totalSupply = await this.indexFundToken.totalSupply();
    expect(totalSupply).to.equal(expectedSharesMintAmount);
  });

  it("should correctly burn shares and transfer stablecoin when burning conditions are met", async function () {
    const alice = this.signers.alice;
    // Approve and mint shares
    const approveInput = this.fhevm.createEncryptedInput(this.wrappedStablecoinContractAddress, alice.address);
    approveInput.add64(this.sharesMintStablecoinAmount);
    const encryptedApproveAmount = await approveInput.encrypt();

    const approveStablecoin = await this.wrappedStablecoin
      .connect(alice)
      ["approve(address,bytes32,bytes)"](
        this.confidentialIndexFundContractAddress,
        encryptedApproveAmount.handles[0],
        encryptedApproveAmount.inputProof,
      );
    await approveStablecoin.wait();

    const mintInput = this.fhevm.createEncryptedInput(this.confidentialIndexFundContractAddress, alice.address);
    const sharesMintStablecoinAmountPerMint = this.sharesMintStablecoinAmount / BigInt("2");
    mintInput.add64(sharesMintStablecoinAmountPerMint);
    const encryptedMintAmount = await mintInput.encrypt();

    const mintShares = await this.confidentialIndexFund
      .connect(alice)
      .mintShares(encryptedMintAmount.handles[0], encryptedMintAmount.inputProof);
    await mintShares.wait();

    await awaitAllDecryptionResults();

    const finishMintShares = await this.confidentialIndexFund.connect(alice).finishMintShares(alice.address);
    await finishMintShares.wait();

    await awaitAllDecryptionResults(); // fulfills unwrap(canUnwrap)
    await awaitCoprocessor();

    // Now prepare to burn shares
    const sharesToBurn = BigInt("10");

    // Approve the index fund to burn shares
    const approveBurnInput = this.fhevm.createEncryptedInput(this.indexFundTokenContractAddress, alice.address);
    approveBurnInput.add64(sharesToBurn);
    const encryptedApproveBurnAmount = await approveBurnInput.encrypt();

    const approveBurn = await this.indexFundToken
      .connect(alice)
      ["approve(address,bytes32,bytes)"](
        this.confidentialIndexFundContractAddress,
        encryptedApproveBurnAmount.handles[0],
        encryptedApproveBurnAmount.inputProof,
      );
    await approveBurn.wait();

    // Create input for burning shares (amount and redeemIndexTokens flag)
    const burnInput = this.fhevm.createEncryptedInput(this.confidentialIndexFundContractAddress, alice.address);
    burnInput.add64(sharesToBurn);
    burnInput.addBool(false); // don't redeem index tokens
    const encryptedBurnAmount = await burnInput.encrypt();

    // Burn the shares
    const burnShares = await this.confidentialIndexFund
      .connect(alice)
      .burnShares(encryptedBurnAmount.handles[0], encryptedBurnAmount.handles[1], encryptedBurnAmount.inputProof);
    await burnShares.wait();

    await awaitAllDecryptionResults();
    await awaitCoprocessor();

    let triggers = await this.confidentialIndexFund.callbackTriggers();
    console.log("Total burnSharesCallback calls:", triggers.toString());
    expect(triggers).to.equal(1n); // check for two calls

    // Need to repeat the whole process a second time to trigger the number of swaps to batch
    // Approve and mint shares
    const approveInput2 = this.fhevm.createEncryptedInput(this.wrappedStablecoinContractAddress, alice.address);
    approveInput2.add64(this.sharesMintStablecoinAmount);
    const encryptedApproveAmount2 = await approveInput2.encrypt();

    const approveStablecoin2 = await this.wrappedStablecoin
      .connect(alice)
      ["approve(address,bytes32,bytes)"](
        this.confidentialIndexFundContractAddress,
        encryptedApproveAmount2.handles[0],
        encryptedApproveAmount2.inputProof,
      );
    await approveStablecoin2.wait();

    const mintInput2 = this.fhevm.createEncryptedInput(this.confidentialIndexFundContractAddress, alice.address);
    mintInput2.add64(sharesMintStablecoinAmountPerMint);
    const encryptedMintAmount2 = await mintInput2.encrypt();

    const mintShares2 = await this.confidentialIndexFund
      .connect(alice)
      .mintShares(encryptedMintAmount2.handles[0], encryptedMintAmount2.inputProof);
    await mintShares2.wait();

    await awaitAllDecryptionResults();

    const finishMintShares2 = await this.confidentialIndexFund.connect(alice).finishMintShares(alice.address);
    await finishMintShares2.wait();

    await awaitAllDecryptionResults(); // fulfills unwrap(canUnwrap)
    await awaitCoprocessor();

    triggers = await this.confidentialIndexFund.mintCallbackTriggers();
    console.log("Total mintSharesCallback calls:", triggers.toString());
    expect(triggers).to.equal(2n); // check for two calls
    const encryptedSharesBalanceHandle = await this.indexFundToken.balanceOf(this.signers.alice);
    const sharesBalanceAliceAfterMint = await debug.decrypt64(encryptedSharesBalanceHandle);

    // Now prepare to burn shares
    // Approve the index fund to burn shares
    const approveBurnInput2 = this.fhevm.createEncryptedInput(this.indexFundTokenContractAddress, alice.address);
    approveBurnInput2.add64(sharesToBurn);
    const encryptedApproveBurnAmount2 = await approveBurnInput2.encrypt();

    const approveBurn2 = await this.indexFundToken
      .connect(alice)
      ["approve(address,bytes32,bytes)"](
        this.confidentialIndexFundContractAddress,
        encryptedApproveBurnAmount2.handles[0],
        encryptedApproveBurnAmount2.inputProof,
      );
    await approveBurn2.wait();

    // Create input for burning shares (amount and redeemIndexTokens flag)
    const burnInput2 = this.fhevm.createEncryptedInput(this.confidentialIndexFundContractAddress, alice.address);
    burnInput2.add64(sharesToBurn);
    burnInput2.addBool(false); // don't redeem index tokens
    const encryptedBurnAmount2 = await burnInput2.encrypt();

    // Burn the shares
    const burnShares2 = await this.confidentialIndexFund
      .connect(alice)
      .burnShares(encryptedBurnAmount2.handles[0], encryptedBurnAmount2.handles[1], encryptedBurnAmount2.inputProof);
    await burnShares2.wait();

    await awaitAllDecryptionResults();
    await awaitCoprocessor();

    triggers = await this.confidentialIndexFund.callbackTriggers();
    console.log("Total burnSharesCallback calls:", triggers.toString());
    expect(triggers).to.equal(2n); // check for two calls

    const initStablecoinTransfer = await this.confidentialIndexFund.connect(alice).initRedeemAfterBurn();
    await initStablecoinTransfer.wait();
    await awaitAllDecryptionResults();
    await awaitCoprocessor();

    const initialBalanceHandle = await this.wrappedStablecoin.balanceOf(alice.address);
    const initialBalance = await debug.decrypt64(initialBalanceHandle);

    const finishStablecoinTransfer = await this.confidentialIndexFund.finishRedeemInStablecoinCase(alice.address);
    await finishStablecoinTransfer.wait();
    await awaitAllDecryptionResults();

    // Check if shares were burned

    const expectedSharesAfterBurn = sharesBalanceAliceAfterMint - sharesToBurn;
    const totalSupply = await this.indexFundToken.totalSupply();
    expect(totalSupply).to.equal(expectedSharesAfterBurn);

    // Get final balance after transfer
    const finalBalanceHandle = await this.wrappedStablecoin.balanceOf(alice.address);
    const finalBalance = await debug.decrypt64(finalBalanceHandle);

    // Verify the balance increased
    expect(finalBalance).to.be.gt(initialBalance);
  });
});
