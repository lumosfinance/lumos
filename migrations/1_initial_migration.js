const Migrations = artifacts.require("Migrations");


module.exports = async function (deployer, network) {
    if (network == "live") {
        return;
    }
    else {
        await deployer.deploy(Migrations);
    }
  
};
