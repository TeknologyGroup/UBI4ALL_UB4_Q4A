// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library UBI4ALLStorage {
    struct Layout {
        address treasuryWallet;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("ubi4all.contracts.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function setWallets(address _treasuryWallet, address, address, address, address, address) internal {
        Layout storage l = layout();
        l.treasuryWallet = _treasuryWallet;
    }

    function getWallets(Layout storage l) internal view returns (address treasury, address, address, address, address, address) {
        return (l.treasuryWallet, address(0), address(0), address(0), address(0), address(0));
    }
}