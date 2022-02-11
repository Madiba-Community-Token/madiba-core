const MadibaToken = artifacts.require("MadibaToken");
const MadibaTreasury = artifacts.require("MadibaTreasury");

module.exports = async function (deployer) {
  await deployer.deploy(MadibaToken);
  await deployer.deploy(MadibaTreasury, MadibaToken.address);
};