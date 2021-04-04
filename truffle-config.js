var HDWalletProvider = require("@truffle/hdwallet-provider");
const MNEMONIC = 'c38355040aa557b62412265cab31af2ed959359e78435371f01b753e341ef227';

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*" // Match any network id
    },
    ropsten: {
      provider: function() {
        return new HDWalletProvider(MNEMONIC, "https://ropsten.infura.io/v3/1e7237c1831a4c38a7eac27009b50046")
      },
      network_id: 3,
      gas: 8000000      //make sure this gas allocation isn't over 8M, which is the max
  }
},
  contracts_directory: './src/contracts/',
  contracts_build_directory: './src/abis/',
  compilers: {
    solc: {
      version: "0.8.0",
      optimizer: {
        enabled: true,
        runs: 200
      },
    }
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    etherscan: 'QEPHIEGVG89RKNNVPW2W4HZQHB74W5C5XZ'
  }

};
