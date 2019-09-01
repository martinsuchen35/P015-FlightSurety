let HDWalletProvider = require("truffle-hdwallet-provider");
let mnemonic = "dizzy baby cloud basic grace where volume damage clerk action observe what";  // Mac Pro
//let mnemonic = "plunge actress custom salon logic patch frown cable dumb gravity satisfy give";  // Mac Mini

module.exports = {
    networks: {
        development: {
            provider: function () {
                return new HDWalletProvider(mnemonic, "http://127.0.0.1:8545/", 0, 50);
            },
            network_id: '*',
            //gas: 9999999
            gas: 0
        }
    },
    compilers: {
        solc: {
            version: "^0.4.24"
        }
    }
};
