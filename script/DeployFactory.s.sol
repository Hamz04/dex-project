// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

contract DeployFactory is Script {
    uint256 constant CREATION_FEE = 0.001 ether;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Deploying TokenFactory...");
        console2.log("Deployer:", deployer);
        vm.startBroadcast(deployerPrivateKey);
        TokenFactory factory = new TokenFactory(CREATION_FEE);
        console2.log("TokenFactory deployed at:", address(factory));
        vm.stopBroadcast();
    }
}

contract DeployAndCreateToken is Script {
    uint256 constant CREATION_FEE = 0.001 ether;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        TokenFactory factory = new TokenFactory(CREATION_FEE);
        address sampleToken = factory.createToken{value: CREATION_FEE}("Sample Token", "SAMPLE", 18, 1_000_000);
        console2.log("Factory:", address(factory));
        console2.log("Sample Token:", sampleToken);
        vm.stopBroadcast();
    }
}
