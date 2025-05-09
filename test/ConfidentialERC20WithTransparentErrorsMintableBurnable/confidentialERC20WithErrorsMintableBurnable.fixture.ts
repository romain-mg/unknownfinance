import { ethers } from "hardhat";

import type { ConfidentialERC20WithErrorsMintableBurnable } from "../../types";
import { getSigners } from "../signers";

export async function deployConfidentialERC20WithErrorsMintableBurnableFixture(
  name = "ConfidentialToken",
  symbol = "CTKN",
): Promise<ConfidentialERC20WithErrorsMintableBurnable> {
  const signers = await getSigners();

  const factory = await ethers.getContractFactory("ConfidentialERC20WithErrorsMintableBurnable");
  const contract = await factory.connect(signers.alice).deploy(name, symbol, signers.alice.address);
  await contract.waitForDeployment();
  return contract;
}
