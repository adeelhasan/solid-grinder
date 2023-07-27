// SPDX-License-Identifier: Unlicense

// MODIFIED VERSION FROM https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
pragma solidity >=0.8.0 <0.9.0;

library BytesLib {
    function concat(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for { let cc := add(_postBytes, 0x20) } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } { mstore(mc, mload(cc)) }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(
                0x40,
                and(
                    add(add(end, iszero(add(length, mload(_preBytes)))), 31),
                    not(31) // Round down to the nearest 32 bytes.
                )
            )
        }

        return tempBytes;
    }

    function concatStorage(bytes storage _preBytes, bytes memory _postBytes) internal {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes.slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                // Since the new array still fits in the slot, we just need to
                // update the contents of the slot.
                // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                sstore(
                    _preBytes.slot,
                    // all the modifications to the slot are inside this
                    // next block
                    add(
                        // we can just add to the slot contents because the
                        // bytes we want to change are the LSBs
                        fslot,
                        add(
                            mul(
                                div(
                                    // load the bytes from memory
                                    mload(add(_postBytes, 0x20)),
                                    // zero all bytes to the right
                                    exp(0x100, sub(32, mlength))
                                ),
                                // and now shift left the number of bytes to
                                // leave space for the length in the slot
                                exp(0x100, sub(32, newlength))
                            ),
                            // increase length by the double of the memory
                            // bytes length
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                // The stored value fits in the slot, but the combined value
                // will exceed it.
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes.slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                // The contents of the _postBytes array start 32 bytes into
                // the structure. Our first read should obtain the `submod`
                // bytes that can fit into the unused space in the last word
                // of the stored array. To get this, we read 32 bytes starting
                // from `submod`, so the data we read overlaps with the array
                // contents by `submod` bytes. Masking the lowest-order
                // `submod` bytes allows us to add that value directly to the
                // stored value.

                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(
                    sc,
                    add(
                        and(fslot, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00),
                        and(mload(mc), mask)
                    )
                )

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } { sstore(sc, mload(mc)) }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes.slot)
                // Start copying to the last used word of the stored array.
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                // Copy over the first `submod` bytes of the new data as in
                // case 1 above.
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))

                for {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } { sstore(sc, mload(mc)) }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } { mstore(mc, mload(cc)) }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_bytes.length >= _start + 1, "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint256 _start) internal pure returns (uint16) {
        require(_bytes.length >= _start + 2, "toUint16_outOfBounds");
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_bytes.length >= _start + 3, "toUint24_outOfBounds");
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint256 _start) internal pure returns (uint32) {
        require(_bytes.length >= _start + 4, "toUint32_outOfBounds");
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint40(bytes memory _bytes, uint256 _start) internal pure returns (uint40) {
        require(_bytes.length >= _start + 5, "toUint40_outOfBounds");
        uint40 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x5), _start))
        }

        return tempUint;
    }

    function toUint48(bytes memory _bytes, uint256 _start) internal pure returns (uint48) {
        require(_bytes.length >= _start + 6, "toUint48_outOfBounds");
        uint48 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x6), _start))
        }

        return tempUint;
    }

    function toUint56(bytes memory _bytes, uint256 _start) internal pure returns (uint56) {
        require(_bytes.length >= _start + 7, "toUint54_outOfBounds");
        uint56 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x7), _start))
        }

        return tempUint;
    }

    function toUint64(bytes memory _bytes, uint256 _start) internal pure returns (uint64) {
        require(_bytes.length >= _start + 8, "toUint64_outOfBounds");
        uint64 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x8), _start))
        }

        return tempUint;
    }

    function toUint72(bytes memory _bytes, uint256 _start) internal pure returns (uint72) {
        require(_bytes.length >= _start + 9, "toUint72_outOfBounds");
        uint72 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x9), _start))
        }

        return tempUint;
    }

    function toUint80(bytes memory _bytes, uint256 _start) internal pure returns (uint80) {
        require(_bytes.length >= _start + 10, "toUint80_outOfBounds");
        uint80 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xa), _start))
        }

        return tempUint;
    }

    function toUint88(bytes memory _bytes, uint256 _start) internal pure returns (uint88) {
        require(_bytes.length >= _start + 11, "toUint88_outOfBounds");
        uint88 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xb), _start))
        }

        return tempUint;
    }

    function toUint96(bytes memory _bytes, uint256 _start) internal pure returns (uint96) {
        require(_bytes.length >= _start + 12, "toUint96_outOfBounds");
        uint96 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xc), _start))
        }

        return tempUint;
    }

    function toUint104(bytes memory _bytes, uint256 _start) internal pure returns (uint104) {
        require(_bytes.length >= _start + 13, "toUint104_outOfBounds");
        uint104 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xd), _start))
        }

        return tempUint;
    }

    function toUint112(bytes memory _bytes, uint256 _start) internal pure returns (uint112) {
        require(_bytes.length >= _start + 14, "toUint112_outOfBounds");
        uint112 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xe), _start))
        }

        return tempUint;
    }

    function toUint120(bytes memory _bytes, uint256 _start) internal pure returns (uint120) {
        require(_bytes.length >= _start + 15, "toUint120_outOfBounds");
        uint120 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xf), _start))
        }

        return tempUint;
    }

    function toUint128(bytes memory _bytes, uint256 _start) internal pure returns (uint128) {
        require(_bytes.length >= _start + 16, "toUint128_outOfBounds");
        uint128 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x10), _start))
        }

        return tempUint;
    }

    function toUint136(bytes memory _bytes, uint256 _start) internal pure returns (uint136) {
        require(_bytes.length >= _start + 17, "toUint136_outOfBounds");
        uint136 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x11), _start))
        }

        return tempUint;
    }

    function toUint144(bytes memory _bytes, uint256 _start) internal pure returns (uint144) {
        require(_bytes.length >= _start + 18, "toUint144_outOfBounds");
        uint144 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x12), _start))
        }

        return tempUint;
    }

    function toUint152(bytes memory _bytes, uint256 _start) internal pure returns (uint152) {
        require(_bytes.length >= _start + 19, "toUint152_outOfBounds");
        uint152 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x13), _start))
        }

        return tempUint;
    }

    function toUint160(bytes memory _bytes, uint256 _start) internal pure returns (uint160) {
        require(_bytes.length >= _start + 20, "toUint160_outOfBounds");
        uint160 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x14), _start))
        }

        return tempUint;
    }
    
    function toUint168(bytes memory _bytes, uint256 _start) internal pure returns (uint168) {
        require(_bytes.length >= _start + 21, "toUint168_outOfBounds");
        uint168 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x15), _start))
        }

        return tempUint;
    }

    function toUint176(bytes memory _bytes, uint256 _start) internal pure returns (uint176) {
        require(_bytes.length >= _start + 22, "toUint176_outOfBounds");
        uint176 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x16), _start))
        }

        return tempUint;
    }

    function toUint184(bytes memory _bytes, uint256 _start) internal pure returns (uint184) {
        require(_bytes.length >= _start + 23, "toUint184_outOfBounds");
        uint184 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x17), _start))
        }

        return tempUint;
    }

    function toUint192(bytes memory _bytes, uint256 _start) internal pure returns (uint192) {
        require(_bytes.length >= _start + 24, "toUint192_outOfBounds");
        uint192 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x18), _start))
        }

        return tempUint;
    }

    function toUint200(bytes memory _bytes, uint256 _start) internal pure returns (uint200) {
        require(_bytes.length >= _start + 25, "toUint200_outOfBounds");
        uint200 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x19), _start))
        }

        return tempUint;
    }

    function toUint208(bytes memory _bytes, uint256 _start) internal pure returns (uint208) {
        require(_bytes.length >= _start + 26, "toUint208_outOfBounds");
        uint208 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1a), _start))
        }

        return tempUint;
    }

    function toUint216(bytes memory _bytes, uint256 _start) internal pure returns (uint216) {
        require(_bytes.length >= _start + 27, "toUint216_outOfBounds");
        uint216 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1b), _start))
        }

        return tempUint;
    }

    function toUint224(bytes memory _bytes, uint256 _start) internal pure returns (uint224) {
        require(_bytes.length >= _start + 28, "toUint224_outOfBounds");
        uint224 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1c), _start))
        }

        return tempUint;
    }

    function toUint232(bytes memory _bytes, uint256 _start) internal pure returns (uint232) {
        require(_bytes.length >= _start + 29, "toUint232_outOfBounds");
        uint232 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1d), _start))
        }

        return tempUint;
    }


    function toUint240(bytes memory _bytes, uint256 _start) internal pure returns (uint240) {
        require(_bytes.length >= _start + 30, "toUint240_outOfBounds");
        uint240 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1e), _start))
        }

        return tempUint;
    }

    function toUint248(bytes memory _bytes, uint256 _start) internal pure returns (uint248) {
        require(_bytes.length >= _start + 31, "toUint248_outOfBounds");
        uint248 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1f), _start))
        }

        return tempUint;
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint256 _start) internal pure returns (bytes32) {
        require(_bytes.length >= _start + 32, "toBytes32_outOfBounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            // if lengths don't match the arrays are not equal
            switch eq(length, mload(_postBytes))
            case 1 {
                // cb is a circuit breaker in the for loop since there's
                //  no said feature for inline assembly loops
                // cb = 1 - don't breaker
                // cb = 0 - break
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for { let cc := add(_postBytes, 0x20) }
                // the next line is the loop condition:
                // while(uint256(mc < end) + cb == 2)
                eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // if any of these checks fails then arrays are not equal
                    if iszero(eq(mload(mc), mload(cc))) {
                        // unsuccess:
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }

    function equalStorage(bytes storage _preBytes, bytes memory _postBytes) internal view returns (bool) {
        bool success = true;

        assembly {
            // we know _preBytes_offset is 0
            let fslot := sload(_preBytes.slot)
            // Decode the length of the stored array like in concatStorage().
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)

            // if lengths don't match the arrays are not equal
            switch eq(slength, mlength)
            case 1 {
                // slength can contain both the length and contents of the array
                // if length < 32 bytes so let's prepare for that
                // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        // blank the last byte which is the length
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            // unsuccess:
                            success := 0
                        }
                    }
                    default {
                        // cb is a circuit breaker in the for loop since there's
                        //  no said feature for inline assembly loops
                        // cb = 1 - don't breaker
                        // cb = 0 - break
                        let cb := 1

                        // get the keccak hash to get the contents of the array
                        mstore(0x0, _preBytes.slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        // the next line is the loop condition:
                        // while(uint256(mc < end) + cb == 2)
                        for {} eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                // unsuccess:
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }
}
