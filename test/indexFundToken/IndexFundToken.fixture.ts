import { ethers } from "hardhat";

import type { IndexFundToken } from "../../types";
import { getSigners } from "../signers";

export async function deployIndexFundTokenFixture(): Promise<IndexFundToken> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("IndexFundToken");
  const contract = await contractFactory.connect(signers.alice).deploy("Naraggara", "NARA"); // City of Zama's battle
  await contract.waitForDeployment();

  return contract;
}
