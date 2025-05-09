import { expect } from "chai";
import { LogDescription } from "ethers";

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
  });

  it("should correctly mint shares when minting conditions are met", async function () {
    // Prepare mock swap manager and market data fetcher
    const nextSwapAmountOut = 1;
    const setMockSwaps = await this.mockSwapsManager.setNextAmountOut(nextSwapAmountOut);
    await setMockSwaps.wait();
    const setMockMarketData = await this.mockMarketDataFetcher.setIndexMarketCaps(1000, [500, 500]);
    await setMockMarketData.wait();

    // Mint the stablecoin
    const alice = this.signers.alice;
    const sharesMintStablecoinAmount = BigInt("1000");
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
    const mint1 = this.firstTestERC20.mint(this.confidentialIndexFundContractAddress, 1e6);
    await mint1.wait;

    const mint2 = this.secondTestERC20.mint(this.confidentialIndexFundContractAddress, 1e6);
    await mint2.wait;

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

    // Mint shares
    const mintInput = this.fhevm.createEncryptedInput(this.confidentialIndexFundContractAddress, alice.address);
    mintInput.add64(sharesMintStablecoinAmount);
    const encryptedMintAmount = await mintInput.encrypt();

    const mintShares = await this.confidentialIndexFund
      .connect(alice)
      .mintShares(encryptedMintAmount.handles[0], encryptedMintAmount.inputProof);
    await mintShares.wait();

    await awaitAllDecryptionResults(); // fulfills unwrap(canUnwrap)

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
      (sharesMintStablecoinAmount - sharesMintStablecoinAmount / feeDivisor) / shareValue;
    expect(encryptedsharesMintedAlice).to.equal(expectedSharesMintAmount);

    const totalSupply = await this.indexFundToken.totalSupply();
    expect(totalSupply).to.equal(expectedSharesMintAmount);
  });
});
