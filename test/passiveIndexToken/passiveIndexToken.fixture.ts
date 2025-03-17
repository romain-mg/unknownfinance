import { ethers } from "hardhat";

import type { PassiveIndexToken } from "../../types";
import { getSigners } from "../signers";

export async function deployPassiveIndexTokenFixture(): Promise<PassiveIndexToken> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("PassiveIndexToken");
  const contract = await contractFactory.connect(signers.alice).deploy("PassiveIndexToken", "PSV"); // City of Zama's battle
  await contract.waitForDeployment();

  return contract;
}
