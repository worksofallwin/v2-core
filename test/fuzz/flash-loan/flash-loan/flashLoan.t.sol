// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { MAX_UD60x18, UD60x18, ud } from "@prb/math/UD60x18.sol";
import { IERC3156FlashBorrower } from "erc3156/interfaces/IERC3156FlashBorrower.sol";

import { Errors } from "src/libraries/Errors.sol";

import { FlashLoan_Fuzz_Test } from "../FlashLoan.t.sol";

contract FlashLoanFunction_Fuzz_Test is FlashLoan_Fuzz_Test {
    modifier whenNoDelegateCall() {
        _;
    }

    function testFuzz_RevertWhen_AmountTooHigh(uint256 amount) external whenNoDelegateCall {
        amount = bound(amount, uint256(UINT128_MAX) + 1, UINT256_MAX);
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierV2FlashLoan_AmountTooHigh.selector, amount));
        flashLoan.flashLoan({
            receiver: IERC3156FlashBorrower(address(0)),
            asset: address(DEFAULT_ASSET),
            amount: amount,
            data: bytes("")
        });
    }

    modifier whenAmountNotTooHigh() {
        _;
    }

    modifier whenAssetFlashLoanable() {
        _;
    }

    function testFuzz_RevertWhen_CalculatedFeeTooHigh(UD60x18 flashFee)
        external
        whenNoDelegateCall
        whenAmountNotTooHigh
        whenAssetFlashLoanable
    {
        // Bound the flash fee so that the calculated fee ends up being greater than 2^128.
        flashFee = bound(flashFee, ud(1.1e18), ud(10e18));
        comptroller.setFlashFee(flashFee);

        // Run the test.
        uint256 fee = flashLoan.flashFee({ asset: address(DEFAULT_ASSET), amount: UINT128_MAX });
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierV2FlashLoan_CalculatedFeeTooHigh.selector, fee));
        flashLoan.flashLoan({
            receiver: IERC3156FlashBorrower(address(0)),
            asset: address(DEFAULT_ASSET),
            amount: UINT128_MAX,
            data: bytes("")
        });
    }

    modifier whenCalculatedFeeNotTooHigh() {
        _;
    }

    modifier whenBorrowDoesNotFail() {
        _;
    }

    modifier whenNoReentrancy() {
        _;
    }

    /// @dev Given enough test runs, all of the following scenarios will be fuzzed:
    ///
    /// - Multiple values for the comptroller flash fee, including zero
    /// - Multiple values for the flash loan amount, including zero
    /// - Multiple values for the data bytes array, including zero length
    function testFuzz_FlashLoanFunction(
        UD60x18 comptrollerFlashFee,
        uint128 amount,
        bytes calldata data
    )
        external
        whenNoDelegateCall
        whenAmountNotTooHigh
        whenAssetFlashLoanable
        whenCalculatedFeeNotTooHigh
        whenBorrowDoesNotFail
        whenNoReentrancy
    {
        comptrollerFlashFee = bound(comptrollerFlashFee, 0, MAX_FEE);
        comptroller.setFlashFee(comptrollerFlashFee);

        // Load the initial protocol revenues.
        uint128 initialProtocolRevenues = flashLoan.protocolRevenues(DEFAULT_ASSET);

        // Load the flash fee.
        uint256 fee = flashLoan.flashFee({ asset: address(DEFAULT_ASSET), amount: amount });

        // Mint the flash loan amount to the contract.
        deal({ token: address(DEFAULT_ASSET), to: address(flashLoan), give: amount });

        // Mint the flash fee to the receiver so that they can repay the flash loan.
        deal({ token: address(DEFAULT_ASSET), to: address(goodFlashLoanReceiver), give: fee });

        // Expect `amount` of assets to be transferred from {SablierV2FlashLoan} to the receiver.
        expectCallToTransfer({ to: address(goodFlashLoanReceiver), amount: amount });

        // Expect `amount+fee` of assets to be transferred back from the receiver.
        uint256 returnAmount = amount + fee;
        expectCallToTransferFrom({ from: address(goodFlashLoanReceiver), to: address(flashLoan), amount: returnAmount });

        // Expect a {FlashLoan} event to be emitted.
        vm.expectEmit({ emitter: address(flashLoan) });
        emit FlashLoan({
            initiator: users.admin,
            receiver: goodFlashLoanReceiver,
            asset: DEFAULT_ASSET,
            amount: amount,
            feeAmount: fee,
            data: data
        });

        // Execute the flash loan.
        bool response = flashLoan.flashLoan({
            receiver: goodFlashLoanReceiver,
            asset: address(DEFAULT_ASSET),
            amount: amount,
            data: data
        });

        // Assert that the returned response is `true`.
        assertTrue(response, "flashLoan response");

        // Assert that the protocol fee has been recorded.
        uint128 actualProtocolRevenues = flashLoan.protocolRevenues(DEFAULT_ASSET);
        uint128 expectedProtocolRevenues = initialProtocolRevenues + uint128(fee);
        assertEq(actualProtocolRevenues, expectedProtocolRevenues, "protocolRevenues");
    }
}
