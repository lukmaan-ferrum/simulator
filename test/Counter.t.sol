// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Surl} from "surl/Surl.sol";
import {strings} from "solidity-stringutils/strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "forge-std/IERC20.sol";


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
        console.logBytes(oneInchCalldata);

        vm.startPrank(whale);

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
}
