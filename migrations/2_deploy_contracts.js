const MasterChef = artifacts.require('MasterChef')
const RewardPool = artifacts.require('RewardPool')
const LotlToken = artifacts.require('LotlToken')

module.exports = async function(deployer, network, accounts) {

  await deployer.deploy(LotlToken)
  const lotlToken = await LotlToken.deployed()

  await deployer.deploy(MasterChef, lotlToken.address)
  const masterChef = await MasterChef.deployed()

  await deployer.deploy(RewardPool, masterChef.address, lotlToken.address)
  const rewardPool = await RewardPool.deployed()
}

