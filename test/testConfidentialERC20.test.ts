import { ethers } from "hardhat";

import type { TestConfidentialERC20 } from "../types";
import { getSigners, initSigners } from "./signers";

export async function deployTestConfidentialERC20Fixture(
  name = "ConfidentialToken",
  symbol = "CTKN",
): Promise<TestConfidentialERC20> {}

describe("ConfidentialIndexFund", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  it("should mint the contract", async function () {
    const alice = this.signers.alice;
    const contract = await deployTestConfidentialERC20Fixture();
  });
});
