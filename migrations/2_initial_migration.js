const MadibaBEP20 = artifacts.require("MadibaBEP20");
const MadibaSwap = artifacts.require("MadibaSwap");
const MadibaTreasury = artifacts.require("MadibaTreasury");

module.exports = async function (deployer) {
  await deployer.deploy(MadibaBEP20, '0x0DE9Cb505Ed62531625dC74AA316d6236850839F',
    300,
    600);
  await deployer.deploy(MadibaSwap, MadibaBEP20.address, '0xd99d1c33f9fc3444f8101754abc46c52416550d1');
  await deployer.deploy(MadibaTreasury, MadibaBEP20.address);
};