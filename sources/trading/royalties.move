module nft_protocol::royalties {
    //! To enable custom royalty functionality with current Move design, we need
    //! to create a system in which collection's own implementation can use
    //! priviledge to access the NFT payments, yet anyone can call the royalty
    //! logic to finish their trade.
    //!
    //! An instance of collection's struct `W` (not the one-time-witness!)
    //! enables it to extract funds from `TradePayment`. After it calculates the
    //! royalty from the NFT payment, it then transfers the rest to the
    //! beneficiary address, be it the NFT seller or a marketplace/wallet.
    //!
    //! The trading contracts can design their commission schemes such that the
    //! marketplaces and/or wallets are incentivized to resolve the settlements.
    //! That avoids extra txs sent by the user, because the client
    //! implementation will be such that they include everything in one batched
    //! tx if possible, or have automation.

    use nft_protocol::utils;
    use std::option::{Self, Option};
    use sui::balance::{Self, Balance};
    use sui::coin;
    use sui::object::{Self, ID, UID};
    use sui::transfer::{transfer, share_object};
    use sui::tx_context::TxContext;

    /// `W` is the collection's witness (not the one time witness!) which
    /// helps us ensure that the right royalty collection logic is operating
    /// on this receipt.
    ///
    /// 1. `C`ollection one-time-witness
    /// 2. Collection's `W`itness
    /// 3. `F`ungible `T`oken
    struct TradePayment<phantom C, phantom W, phantom FT> has key {
        id: UID,
        amount: Balance<FT>,
        /// The address where the amount should be transferred to.
        /// This could be either the payment for the seller or a marketplace's
        /// commision.
        beneficiary: address,
        /// Optionally we enable grouping of payments, e.g. if there are
        /// multiple payments for one NFT (such as commission.), it might be
        /// useful for the royalty collection logic to distinguish such
        /// scenario.
        trade: Option<ID>,
    }

    /// # Important
    /// `W` is not the collection's one-time-witness, but collection auth token
    /// witness.
    public entry fun create<C, W, FT>(
        amount: Balance<FT>,
        beneficiary: address,
        ctx: &mut TxContext,
    ) {
        create_<C, W, FT>(amount, beneficiary, option::none(), ctx)
    }

    /// # Important
    /// `W` is not the collection's one-time-witness, but collection auth token
    /// witness.
    public entry fun create_with_trade<C, W, FT>(
        amount: Balance<FT>,
        beneficiary: address,
        trade: ID,
        ctx: &mut TxContext,
    ) {
        create_<C, W, FT>(amount, beneficiary, option::some(trade), ctx)
    }

    public fun balance<C, W, FT>(payment: &TradePayment<C, W, FT>): &Balance<FT> {
        &payment.amount
    }

    /// Only the designated witness can access the balance.
    ///
    /// Typically, this would be a witness exported from the collection contract
    /// and it would access the balance to calculate the royalty in its custom
    /// implementation.
    public fun balance_mut<C, W: drop, FT>(
        _witness: W,
        payment: &mut TradePayment<C, W, FT>,
    ): &mut Balance<FT> {
        &mut payment.amount
    }

    public fun beneficiary<C, W, FT>(payment: &TradePayment<C, W, FT>): address {
        payment.beneficiary
    }

    public fun transfer_remaining_to_beneficiary<C, W: drop, FT>(
        _witness: W,
        payment: &mut TradePayment<C, W, FT>,
        ctx: &mut TxContext,
    ) {
        let amount = balance::value(&payment.amount);
        if (amount > 0) {
            transfer(
                coin::take(
                    &mut payment.amount,
                    amount,
                    ctx,
                ),
                payment.beneficiary
            );
        }
    }

    fun create_<C, W, FT>(
        amount: Balance<FT>,
        beneficiary: address,
        trade: Option<ID>,
        ctx: &mut TxContext,
    ) {
        utils::assert_witnesses_of_same_package<C, W>();
        share_object(TradePayment<C, W, FT> {
            id: object::new(ctx),
            amount,
            beneficiary,
            trade,
        });
    }
}
