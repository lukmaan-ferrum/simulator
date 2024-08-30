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

    address whale = 0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A;
    address oneInch = 0x111111125421cA6dc452d289314280a0f8842A65;
    address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address outToken = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    function setUp() public {
    }

    function testCall1Inch() public {
        bytes memory oneInchCalldata = _get1InchCalldata();
        oneInchCalldata = _modifyAndReplaceChunk(oneInchCalldata, 164);

        vm.startPrank(whale);
        IERC20(usdc).approve(oneInch, 50 * 10 ** 6);
        console.log("Approved");
        (bool success,) = oneInch.call(oneInchCalldata);
        console.log(success);
    }

    function _get1InchCalldata() internal returns (bytes memory) {
        string memory url = "https://api.1inch.dev/swap/v6.0/8453/swap";
        string memory params = string.concat(
            "?from=",
            vm.toString(whale),
            "&src=",
            vm.toString(usdc),
            "&dst=",
            vm.toString(outToken),
            "&amount=",
            vm.toString(uint256(5 * 10 ** 6)),
            "&slippage=",
            vm.toString(uint256(3)),
            "&disableEstimate=true",
            "&origin=",
            vm.toString(whale)
        );

        string memory apiKey = vm.envString("ONEINCH_API_KEY");

        string[] memory headers = new string[](2);
        headers[0] = "accept: application/json";
        headers[1] = string.concat("Authorization: Bearer ", apiKey);

        string memory request = string.concat(url, params);
        (uint256 status, bytes memory res) = request.get(headers);


        string memory json = string(res);

        bytes memory data = json.readBytes(".tx.data");
        assertEq(status, 200);
        return data;
    }

    function _modifyAndReplaceChunk(bytes memory data, uint256 index) public pure returns (bytes memory) {
        uint256 value;

        // Extract the 32-byte chunk and convert it to a uint256
        assembly {
            let dataPtr := add(data, 32) // Get the pointer to the start of the bytes array's content
            let chunkPtr := add(dataPtr, index) // Get the pointer to the target chunk
            value := mload(chunkPtr) // Load the 32-byte chunk into the uint256 variable
        }

        console.log("Original value: ", value);
        // Subtract 2% from the value
        uint256 newValue = value * 98 / 100; // Equivalent to subtracting 2%
        console.logBytes(data);

        console.log("New value: ", newValue);

        // Replace the original 32-byte chunk with the new value
        assembly {
            let dataPtr := add(data, 32) // Get the pointer to the start of the bytes array's content
            let chunkPtr := add(dataPtr, index) // Get the pointer to the target chunk
            mstore(chunkPtr, newValue) // Store the new value as a 32-byte chunk
        }

        console.logBytes(data);
        return data;
    }
}

// Compare the price. So get dstAmount from API response, calc price based on input and this
// Then run simulation, and calc output price based on input and output
// Compare the 2 prices
