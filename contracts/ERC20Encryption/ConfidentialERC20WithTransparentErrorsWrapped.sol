// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConfidentialERC20WithTransparentErrors} from "./ConfidentialERC20WithTransparentErrors.sol";
import "fhevm/lib/TFHE.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IConfidentialERC20Wrapped} from "@httpz-contracts/token/ERC20/IConfidentialERC20Wrapped.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract ConfidentialERC20WithTransparentErrorsWrapped is
    ConfidentialERC20WithTransparentErrors,
    IConfidentialERC20Wrapped,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20Metadata;

    /// @notice Returned if the maximum decryption delay is higher than 1 day.
    error MaxDecryptionDelayTooHigh();

    /// @notice ERC20 token that is wrapped.
    IERC20Metadata public immutable ERC20_TOKEN;

    /// @notice Tracks whether the account can move funds.
    mapping(address account => bool isRestricted) public isAccountRestricted;

    /// @notice Tracks the unwrap request to a unique request id.
    mapping(uint256 requestId => UnwrapRequest unwrapRequest) public unwrapRequests;

    constructor(string memory name_, string memory symbol_, address erc20_, uint256 maxDecryptionDelay_)
        ConfidentialERC20WithTransparentErrors(name_, symbol_)
    {
        ERC20_TOKEN = IERC20Metadata(erc20_);
        /// @dev The maximum delay is set to 1 day.
        if (maxDecryptionDelay_ > 1 days) {
            revert MaxDecryptionDelayTooHigh();
        }
    }

    /**
     * @notice         Unwrap ConfidentialERC20 tokens to standard ERC20 tokens.
     * @param amount   Amount to unwrap.
     */
    function unwrap(uint64 amount) public virtual {
        _canTransferOrUnwrap(msg.sender);

        /// @dev Once this function is called, it becomes impossible for the sender to move any token.
        isAccountRestricted[msg.sender] = true;
        ebool canUnwrap = TFHE.le(amount, _balances[msg.sender]);

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(canUnwrap);

        uint256 requestId =
            Gateway.requestDecryption(cts, this.callbackUnwrap.selector, 0, block.timestamp + 100, false);

        unwrapRequests[requestId] = UnwrapRequest({account: msg.sender, amount: amount});
    }

    /**
     * @notice         Wrap ERC20 tokens to an encrypted format.
     * @param amount   Amount to wrap.
     */
    function wrap(uint256 amount) public virtual {
        ERC20_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        uint256 amountAdjusted = amount / (10 ** (ERC20_TOKEN.decimals() - decimals()));

        if (amountAdjusted > type(uint64).max) {
            revert AmountTooHigh();
        }

        uint64 amountUint64 = uint64(amountAdjusted);

        _unsafeMint(msg.sender, amountUint64);
        _totalSupply += amountUint64;

        emit Wrap(msg.sender, amountUint64);
    }

    /**
     * @notice            Callback function for the gateway.
     * @param requestId   Request id.
     * @param canUnwrap   Whether it can be unwrapped.
     */
    function callbackUnwrap(uint256 requestId, bool canUnwrap) public virtual nonReentrant onlyGateway {
        UnwrapRequest memory unwrapRequest = unwrapRequests[requestId];

        if (canUnwrap) {
            /// @dev It does a supply adjustment.
            uint256 amountUint256 = unwrapRequest.amount * (10 ** (ERC20_TOKEN.decimals() - decimals()));

            try ERC20_TOKEN.transfer(unwrapRequest.account, amountUint256) {
                _unsafeBurn(unwrapRequest.account, unwrapRequest.amount);
                _totalSupply -= unwrapRequest.amount;
                emit Unwrap(unwrapRequest.account, unwrapRequest.amount);
            } catch {
                emit UnwrapFailTransferFail(unwrapRequest.account, unwrapRequest.amount);
            }
        } else {
            emit UnwrapFailNotEnoughBalance(unwrapRequest.account, unwrapRequest.amount);
        }

        delete unwrapRequests[requestId];
        delete isAccountRestricted[unwrapRequest.account];
    }

    function _canTransferOrUnwrap(address account) internal virtual {
        if (isAccountRestricted[account]) {
            revert CannotTransferOrUnwrap();
        }
    }

    function _transferNoEvent(address from, address to, euint64 amount, ebool isTransferable)
        internal
        virtual
        override
    {
        _canTransferOrUnwrap(from);
        super._transferNoEvent(from, to, amount, isTransferable);
    }

    function _unsafeBurn(address account, uint64 amount) internal {
        euint64 newBalanceAccount = TFHE.sub(_balances[account], amount);
        _balances[account] = newBalanceAccount;
        TFHE.allowThis(newBalanceAccount);
        TFHE.allow(newBalanceAccount, account);
        emit Transfer(account, address(0), _PLACEHOLDER);
    }
}
