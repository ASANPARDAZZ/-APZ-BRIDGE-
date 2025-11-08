// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract APZBridgeEthereum is ReentrancyGuard, Ownable {
    // Events
    event TokensLocked(
        address indexed user,
        uint256 amount,
        string destinationChain,
        address destinationAddress
    );
    
    event TokensUnlocked(
        address indexed user,
        uint256 amount,
        string sourceChain
    );

    // Structs
    struct BridgeTransaction {
        address user;
        uint256 amount;
        string destinationChain;
        address destinationAddress;
        uint256 timestamp;
        bool completed;
    }

    // State variables
    mapping(bytes32 => BridgeTransaction) public transactions;
    mapping(address => bool) public validators;
    uint256 public minBridgeAmount;
    uint256 public maxBridgeAmount;
    uint256 public bridgeFee; // in basis points (100 = 1%)
    
    IERC20 public apzToken;

    constructor(address _apzToken) {
        apzToken = IERC20(_apzToken);
        minBridgeAmount = 1 ether;
        maxBridgeAmount = 100000 ether;
        bridgeFee = 10; // 0.1%
        
        // Add deployer as initial validator
        validators[msg.sender] = true;
    }

    // Lock tokens for bridging to APZ Chain
    function lockTokens(
        uint256 amount,
        string calldata destinationChain,
        address destinationAddress
    ) external nonReentrant {
        require(amount >= minBridgeAmount, "Amount too low");
        require(amount <= maxBridgeAmount, "Amount too high");
        require(bytes(destinationChain).length > 0, "Invalid chain");
        require(destinationAddress != address(0), "Invalid address");

        // Calculate bridge fee
        uint256 fee = (amount * bridgeFee) / 10000;
        uint256 amountAfterFee = amount - fee;

        // Transfer tokens from user to bridge
        require(
            apzToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Create transaction record
        bytes32 txHash = keccak256(
            abi.encodePacked(
                msg.sender,
                amount,
                destinationChain,
                destinationAddress,
                block.timestamp
            )
        );

        transactions[txHash] = BridgeTransaction({
            user: msg.sender,
            amount: amountAfterFee,
            destinationChain: destinationChain,
            destinationAddress: destinationAddress,
            timestamp: block.timestamp,
            completed: false
        });

        emit TokensLocked(
            msg.sender,
            amountAfterFee,
            destinationChain,
            destinationAddress
        );
    }

    // Unlock tokens from APZ Chain (only validators)
    function unlockTokens(
        address user,
        uint256 amount,
        string calldata sourceChain,
        bytes32 sourceTxHash,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(validators[msg.sender], "Only validators");
        require(_verifySignatures(user, amount, sourceChain, sourceTxHash, signatures), "Invalid signatures");

        // Transfer tokens to user
        require(
            apzToken.transfer(user, amount),
            "Transfer failed"
        );

        emit TokensUnlocked(user, amount, sourceChain);
    }

    // Validator management
    function addValidator(address validator) external onlyOwner {
        validators[validator] = true;
    }

    function removeValidator(address validator) external onlyOwner {
        validators[validator] = false;
    }

    // Fee management
    function setBridgeFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "Fee too high"); // Max 1%
        bridgeFee = newFee;
    }

    // Internal signature verification
    function _verifySignatures(
        address user,
        uint256 amount,
        string memory sourceChain,
        bytes32 sourceTxHash,
        bytes[] memory signatures
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(user, amount, sourceChain, sourceTxHash)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address[] memory signers = new address[](signatures.length);
        for (uint i = 0; i < signatures.length; i++) {
            address signer = _recoverSigner(ethSignedMessageHash, signatures[i]);
            if (!validators[signer]) {
                return false;
            }
            // Check for duplicate signatures
            for (uint j = 0; j < i; j++) {
                if (signers[j] == signer) {
                    return false;
                }
            }
            signers[i] = signer;
        }

        return signatures.length >= 2; // Require at least 2 signatures
    }

    function _recoverSigner(bytes32 messageHash, bytes memory signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        return ecrecover(messageHash, v, r, s);
    }

    function _splitSignature(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(signature.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;
    }
}
