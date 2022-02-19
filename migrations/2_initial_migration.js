const MadibaBEP20 = artifacts.require("MadibaBEP20");
const MadibaSwap = artifacts.require("MadibaSwap");
const MadibaTreasury = artifacts.require("MadibaTreasury");

module.exports = async function (deployer) {
  await deployer.deploy(MadibaBEP20, '0xfB8Fb3D7981bcD47799e338fAEe00dA0254DD7d4',
    300,
    600);
  await deployer.deploy(MadibaSwap, MadibaBEP20.address, '0x10ed43c718714eb63d5aa57b78b54704e256024e');
  await deployer.deploy(MadibaTreasury, MadibaBEP20.address);
};