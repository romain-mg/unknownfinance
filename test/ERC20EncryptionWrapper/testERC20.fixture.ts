import { ethers } from "hardhat";

import type { TestErc20 } from "../../types";
import { getSigners } from "../signers";

export async function deployERC20Fixture(name: string, symbol: string): Promise<TestErc20> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("TestErc20");
  const contract = await contractFactory.connect(signers.alice).deploy(name, symbol);
  await contract.waitForDeployment();

  return contract;
}
