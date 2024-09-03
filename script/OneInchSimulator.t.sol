// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Surl} from "surl/Surl.sol";
import {strings} from "solidity-stringutils/strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract OneInchTest is Test {
    using Surl for *;
    using strings for *;
    using stdJson for string;

    // ############################
    string url = "https://api.1inch.dev/swap/v6.0/1/swap";
    string rpcUrl = "ETHEREUM_RPC";
    string path = "mainnet_data.csv";

    address whale = 0x7eb6c83AB7D8D9B8618c0Ed973cbEF71d1921EF2;
    address oneInch = 0x111111125421cA6dc452d289314280a0f8842A65;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // ############################

    address[] public outTokens = [
        0x6942040b6d25D6207E98f8E26C6101755D67Ac89
    ];

    function run() public {

        string memory data = string.concat(
            "outToken,amountIn,amountOut,amountInWithSlippage,amountOutWithSlippage,modifiedCalldata"
        );
        vm.writeLine(path, data);

        for (uint256 i = 0; i < outTokens.length; i++) {
            address outToken = outTokens[i];
            for (uint256 j = 0; j < 100; j++) {
                console.log("Iteration: ", j);
                // Create and select a new fork for each iteration
                vm.createSelectFork(vm.envString(rpcUrl));

                // Generate random uint256 values for amountInRng and slippageRng
                uint256 amountInRng = uint256(keccak256(abi.encodePacked(block.prevrandao, j)));
                uint256 slippageRng = uint256(keccak256(abi.encodePacked(amountInRng, j)));

                // Use amountInRng to get a random amount between 100 and 100,000
                uint256 amountIn = ((amountInRng % (100_000 - 100)) + 100) * 10 ** 6;

                // Call 1inch API to get calldata and dstAmount
                (bytes memory oneInchCalldata, uint256 dstAmount) = _get1InchCalldata(outToken, amountIn);

                if (dstAmount == 0) {
                    vm.writeLine(path, string.concat("skipping", vm.toString(oneInchCalldata)));
                    continue;
                }

                address outToken_ = outToken;

                // Modify the calldata to apply artifical source side slippage
                uint256 randSlippage = slippageRng % (10200 - 9800) + 9800;
                uint256 amountInWithSlippage = amountIn * randSlippage / 10000;
                uint256 replaceIndex = _getReplaceIndex(oneInchCalldata);

                if (replaceIndex == 0) {
                    vm.writeLine(path, string.concat("skipping", vm.toString(oneInchCalldata)));
                    // continue;
                }

                bytes memory modifiedCalldata = _replaceChunk(oneInchCalldata, replaceIndex, amountInWithSlippage);

                // Start impersonating the whale account
                vm.startPrank(whale);
                IERC20(usdc).approve(oneInch, amountInWithSlippage);

                uint256 preBalance = IERC20(outToken).balanceOf(whale);
                console.log("Pre balance: ", preBalance);

                // Call the 1inch contract with the modified calldata
                (bool successModified,) = oneInch.call(modifiedCalldata);
                if (!successModified) {
                    vm.writeLine(path, string.concat("failed", vm.toString(modifiedCalldata)));
                    continue;
                }

                // Get the output amount after modification (could be retrieved by querying the output token balance)
                uint256 postBalance = IERC20(outToken).balanceOf(whale);

                console.log("Post balance: ", postBalance);

                // Write to CSV
                string memory _data = string.concat(
                    vm.toString(outToken_), ",",
                    vm.toString(amountIn), ",",
                    vm.toString(dstAmount), ",",
                    vm.toString(amountInWithSlippage), ",", // Actual modified input amount with slippage applied
                    vm.toString(postBalance - preBalance), ",",
                    vm.toString(modifiedCalldata)
                );
                vm.writeLine(path, _data);
            }
        }
    }

    function _get1InchCalldata(address outToken, uint256 randAmountIn) internal returns (bytes memory, uint256) {
        string memory params = string.concat(
            "?from=",
            vm.toString(whale),
            "&src=",
            vm.toString(usdc),
            "&dst=",
            vm.toString(outToken),
            "&amount=",
            vm.toString(randAmountIn),
            "&slippage=",
            vm.toString(uint256(2)), // Default slippage to 2%
            "&disableEstimate=true",
            "&origin=",
            vm.toString(whale),
            "&excludedProtocols=ARBITRUM_PMM11"
        );

        string memory apiKey = vm.envString("ONEINCH_API_KEY");

        string[] memory headers = new string[](2);
        headers[0] = "accept: application/json";
        headers[1] = string.concat("Authorization: Bearer ", apiKey);

        string memory request = string.concat(url, params);
        (uint256 status, bytes memory res) = request.get(headers);

        string memory json = string(res);
        
        if(status != 200) {
            console.log("JSON: ", json);
            vm.writeLine(path, json);
            return (bytes(""), 0);
        }

        bytes memory oneInchdata = json.readBytes(".tx.data");
        uint256 dstAmount = json.readUint(".dstAmount");

        console.log("DST AMOUNT: ", dstAmount);
        return (oneInchdata, dstAmount);
    }

    function _replaceChunk(bytes memory data, uint256 index, uint256 newValue) public pure returns (bytes memory) {
        console.log("Replacing chunk at index: ", index, " with value: ", newValue);
        assembly {
            let dataPtr := add(data, 32) // Get the pointer to the start of the bytes array's content
            let chunkPtr := add(dataPtr, index) // Get the pointer to the target chunk
            mstore(chunkPtr, newValue) // Store the new value as a 32-byte chunk
        }

        return data;
    }

    function _getReplaceIndex(bytes memory oneInchCalldata) internal pure returns (uint256) {
        // Extract the first 4 bytes of the calldata to identify the method signature
        bytes4 methodSignature;
        assembly {
            methodSignature := mload(add(oneInchCalldata, 32))
        }

        uint256 index;

        if (methodSignature == bytes4(hex"07ed2379")) { // swap()
            index = 0xa0;
        } else if (methodSignature == bytes4(hex"83800a8e") || methodSignature == bytes4(hex"8770ba91") || methodSignature == bytes4(hex"19367472")) { // unoswaps()
            index = 0x20;
        } else {
            console.log("Skipping method: ");
            console.logBytes4(methodSignature);
            return 0;
        }

        return index + 4;
    }
}
