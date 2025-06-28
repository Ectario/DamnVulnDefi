# Notes

In `FreeRiderRecoveryManager.sol`:

    function onERC721Received(address, address, uint256 _tokenId, bytes memory _data)
            external
            override
            nonReentrant
            returns (bytes4)
        {
            if (msg.sender != address(nft)) {
                revert CallerNotNFT();
            }

            if (tx.origin != beneficiary) {
                revert OriginNotBeneficiary();
            }

            if (_tokenId > 5) {
                revert InvalidTokenID(_tokenId);
            }

            if (nft.ownerOf(_tokenId) != address(this)) {
                revert StillNotOwningToken(_tokenId);
            }

            if (++received == 6) {
                address recipient = abi.decode(_data, (address));
                payable(recipient).sendValue(bounty);
            }

            return IERC721Receiver.onERC721Received.selector;
    }

wtf the pre-increment?

The `onERC721Received` function looks fine but that `++received` pre-increment feels kinda sus at first. Like, looks like I could maybe just spam it to hit 6 and trigger the payout. But nah — the check on `msg.sender != address(nft)` blocks that. Only real transfers from the NFT contract can hit this function.

Reentrancy?
giving NFT before using price (in `FreeRiderNFTMarketplace`):

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller using cached token
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }


Nop! even better: 

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller using cached token
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

The real mess is in _buyOne(). They transfer the NFT before paying the seller, and then they use `ownerOf(tokenId)` after the transfer to figure out who to send the ETH to... which is now the buyer. So basically, I can buy the NFT with `msg.value` and get that ETH sent straight back to me. It's just a free mint at that point. And if I run this through `buyMany()`, I can do it in a loop and pick up multiple NFTs while the contract keeps refunding me every time. No value actually leaves my account.

Now we need a flash loan like thing from uniswap, let's google it; hello you: https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps (and you https://medium.com/buildbear/flash-swap-5bcdbd9aaa14)

So, even if I don’t have enough ETH up front, this is still totally exploitable with a flash loan. Uniswap v2 flash swaps let me borrow WETH, unwrap it to ETH, and run the whole buy + refund loop in a single tx. Then I just collect the bounty (from the onERC721Received trigger when I hit 6 NFTs), wrap the ETH back into WETH, repay the flash loan, and walk away with the bounty as profit. I don’t need to put up any ETH of my own — it’s just a matter of packaging the attack cleanly.