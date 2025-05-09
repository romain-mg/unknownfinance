import { ethers } from "hardhat";
import { artifacts } from "hardhat";

import type {
  ConfidentialERC20WithErrorsWrapped,
  ConfidentialIndexFund,
  IndexFundFactory,
  IndexFundStateManagement,
  IndexFundToken,
  MockMarketDataFetcher,
  MockSwapsManager,
  TestErc20,
} from "../../types";
import { GATEWAYCONTRACT_ADDRESS } from "../constants";
import { getSigners } from "../signers";

export async function deployConfidentialIndexFundFixture(): Promise<
  [
    ConfidentialIndexFund,
    IndexFundFactory,
    IndexFundToken,
    ConfidentialERC20WithErrorsWrapped,
    TestErc20,
    TestErc20,
    TestErc20,
    MockMarketDataFetcher,
    MockSwapsManager,
  ]
> {
  const signers = await getSigners();
  const alice = signers.alice;

  const testERC20Factory = await ethers.getContractFactory("TestErc20");
  const firstTestERC20 = await testERC20Factory.connect(alice).deploy("test1", "t1");
  await firstTestERC20.waitForDeployment();
  const secondTestERC20 = await testERC20Factory.connect(alice).deploy("test2", "t2");
  await secondTestERC20.waitForDeployment();
  const testStablecoin = await testERC20Factory.connect(alice).deploy("testStablecoin", "tst");
  await testStablecoin.waitForDeployment();

  const wrappedTokensFactory = await ethers.getContractFactory("ConfidentialERC20WithErrorsWrapped");
  const decryptionDelaySeconds = 100;
  const wrappedStablecoin = await wrappedTokensFactory
    .connect(alice)
    .deploy(testStablecoin.getAddress(), decryptionDelaySeconds);
  await wrappedStablecoin.waitForDeployment();

  const mockMarketDataFetcherFactory = await ethers.getContractFactory("MockMarketDataFetcher");
  const mockMarketDataFetcher = await mockMarketDataFetcherFactory.connect(alice).deploy();
  await mockMarketDataFetcher.waitForDeployment();

  const mockSwapsManagerFactory = await ethers.getContractFactory("MockSwapsManager");
  const mockSwapsManager = await mockSwapsManagerFactory.connect(alice).deploy();
  await mockSwapsManager.waitForDeployment();

  const initialSharePrice = 1;

  const PoolKeys = [
    {
      currency0: firstTestERC20.getAddress(),
      currency1: testStablecoin.getAddress(),
      fee: 0,
      tickSpacing: 0,
      hooks: ethers.ZeroAddress,
    },
    {
      currency0: secondTestERC20.getAddress(),
      currency1: testStablecoin.getAddress(),
      fee: 0,
      tickSpacing: 0,
      hooks: ethers.ZeroAddress,
    },
  ];
  const libName = "contracts/lib/IndexFundStateManagement.sol:IndexFundStateManagement";

  const IndexFundStateManagementLibraryFactory = await ethers.getContractFactory("IndexFundStateManagement");
  const IndexFundStateManagementLibrary = await IndexFundStateManagementLibraryFactory.connect(alice).deploy();
  await IndexFundStateManagementLibrary.waitForDeployment();
  const IndexFundStateManagementLibraryAddress = await IndexFundStateManagementLibrary.getAddress();

  const IndexFundFactoryFactory = await ethers.getContractFactory("IndexFundFactory", {
    libraries: {
      [libName]: IndexFundStateManagementLibraryAddress,
    },
  });

  const indexFundFactory = await IndexFundFactoryFactory.connect(alice).deploy(
    mockSwapsManager.getAddress(),
    mockMarketDataFetcher.getAddress(),
    initialSharePrice,
    1000,
  );
  await indexFundFactory.waitForDeployment();

  const numberOfSwapsToBatch = 2;

  const IndexFundFactory = await ethers.getContractFactory("ConfidentialIndexFund", {
    libraries: {
      [libName]: IndexFundStateManagementLibraryAddress,
    },
  });
  const indexFundCounter = 0;
  const indexFund = await IndexFundFactory.connect(alice).deploy(
    [firstTestERC20.getAddress(), secondTestERC20.getAddress()],
    wrappedStablecoin.getAddress(),
    testStablecoin.getAddress(),
    indexFundFactory.getAddress(),
    mockMarketDataFetcher.getAddress(),
    mockSwapsManager.getAddress(),
    initialSharePrice,
    PoolKeys,
    numberOfSwapsToBatch,
    indexFundCounter,
  );
  await indexFund.waitForDeployment();

  const indexFundTokenAddress = await indexFund.getIndexFundToken();
  const indexFundToken = await ethers.getContractAt("IndexFundToken", indexFundTokenAddress);

  return [
    indexFund,
    indexFundFactory,
    indexFundToken,
    wrappedStablecoin,
    testStablecoin,
    firstTestERC20,
    secondTestERC20,
    mockMarketDataFetcher,
    mockSwapsManager,
  ];
}
