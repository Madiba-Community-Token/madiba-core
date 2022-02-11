const { expect } = require("chai");
const { expectRevert } = require('@openzeppelin/test-helpers');

const fromWei = (n) => web3.utils.fromWei(n.toString());
const bn2String = (bn) => fromWei(bn.toString());
const toWei = (n) => web3.utils.toWei(n.toString());

const MadibaTreasury = artifacts.require("MadibaTreasury");
const MadibaToken = artifacts.require("MadibaToken");

require("chai")
  .use(require("chai-as-promised"))
  .should();

contract("MadibaTreasury", (accounts) => {

  let token;
  let treasury;

  before(async () => {
    token = await MadibaToken.new();
    treasury = await MadibaTreasury.new(token.address);
    await token.setTreasuryAddress(treasury.address);
  });

  describe('MadibaTreasury', () => {
    it("Check treasutry balance", async function () {
      expect(bn2String(await treasury.balance())).to.equal('0');
    });

    it("Check treasury with funds", async function () {
      await token.transfer(treasury.address, toWei(1000));
      expect(bn2String(await treasury.balance())).to.equal('1000');
    });
  });
});
