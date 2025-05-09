import { ethers } from "hardhat";

import type { ConfidentialERC20WithErrorsWrapped, TestErc20 } from "../../types";
import { getSigners } from "../signers";

export async function deployConfidentialERC20WithErrorsWrappedFixture(
  _underlyingERC20: TestErc20,
  maxDecryptionTime: number = 10000,
): Promise<ConfidentialERC20WithErrorsWrapped> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("ConfidentialERC20WithErrorsWrapped");
  const contract = await contractFactory.connect(signers.alice).deploy(_underlyingERC20, maxDecryptionTime);
  await contract.waitForDeployment();

  return contract;
}
