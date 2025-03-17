import { ethers } from "hardhat";

import type { ERC20EncryptionWrapper, TestErc20 } from "../../types";
import { getSigners } from "../signers";

export async function deployERC20EncryptionWrapperFixture(
  name: string,
  symbol: string,
  _underlyingERC20: TestErc20,
): Promise<ERC20EncryptionWrapper> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("ERC20EncryptionWrapper");
  const contract = await contractFactory.connect(signers.alice).deploy(name, symbol, _underlyingERC20);
  await contract.waitForDeployment();

  return contract;
}
