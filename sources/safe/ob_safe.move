/// This contract uses the following witnesses:
/// I: Inner Type of the Safe
/// E: Entinty Witness of the entity request transfer authorisation
/// C: NFT Type of a given NFT in the Safe
module nft_protocol::ob_safe {
    use std::option::{Self, Option};
    use std::type_name::TypeName;

    use sui::vec_set::{Self, VecSet};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{share_object, transfer};


    use nft_protocol::nft::{Self, Nft};
    use nft_protocol::transfer_allowlist::Allowlist;
    use nft_protocol::nft_safe::{Self, NftSafe, OwnerCap};

    struct Witness has drop {}

    struct OriginByte has key, store {
        id: UID,
        // TODO: This can be removed if we remove the logical owner
        owner: Option<address>,
        /// Enables depositing any collection, bypassing enabled deposits
        enable_any_deposit: bool,
        /// Collections which can be deposited into the `Safe`
        collections_with_enabled_deposits: VecSet<TypeName>,
    }

    struct DepositEvent has copy, drop {
        safe: ID,
        nft: ID,
    }

    struct TransferEvent has copy, drop {
        safe: ID,
        nft: ID,
    }

    public fun new(ctx: &mut TxContext): (NftSafe<OriginByte>, OwnerCap) {
        let inner = OriginByte {
            id: object::new(ctx),
            // Note: This may be unsafe, since the caller can inject the wrong
            // owner address
            owner: option::none(),
            enable_any_deposit: true,
            collections_with_enabled_deposits: vec_set::empty(),
        };

        nft_safe::new(inner, ctx)
    }

    /// Instantiates a new shared object `Safe<OriginByte>` and transfer
    /// `OwnerCap` to the tx sender.
    public entry fun create_for_sender(ctx: &mut TxContext) {
        let inner = OriginByte {
            id: object::new(ctx),
            owner: option::some(tx_context::sender(ctx)),
            enable_any_deposit: true,
            collections_with_enabled_deposits: vec_set::empty(),
        };

        let (safe, cap) = nft_safe::new(inner, ctx);

        share_object(safe);
        transfer(cap, tx_context::sender(ctx));
    }

    /// Creates a new `Safe<OriginByte>` shared object and returns the authority capability
    /// that grants authority over this safe.
    public fun create_safe(ctx: &mut TxContext): OwnerCap {
        let inner = OriginByte {
            id: object::new(ctx),
            // Note: This may be unsafe, since the caller can inject the wrong
            // owner address
            owner: option::none(),
            enable_any_deposit: true,
            collections_with_enabled_deposits: vec_set::empty(),
        };

        let (safe, cap) = nft_safe::new(inner, ctx);

        share_object(safe);
        cap
    }

    public fun auth_transfer<Auth: drop, E: drop>(
        self: &mut NftSafe<OriginByte>,
        owner_cap: &OwnerCap,
        nft_id: ID,
        entity_id: &UID,
        // TODO: separate API
        _entity_witness: E,
        _authority: Auth,
        _allowlist: &Allowlist,
    ) {
        nft_safe::auth_transfer(self, owner_cap, nft_id, entity_id, Witness {});
    }

    public fun auth_exclusive_transfer<Auth: drop, E: drop>(
        self: &mut NftSafe<OriginByte>,
        owner_cap: &OwnerCap,
        nft_id: ID,
        entity_id: &UID,
        // TODO: separate API
        _entity_witness: E,
        _authority: Auth,
        _allowlist: &Allowlist,
    ) {
        nft_safe::auth_transfer(self, owner_cap, nft_id, entity_id, Witness {});
    }

    /// Transfer an NFT into the `Safe`.
    public fun deposit_nft<T: key + store>(
        self: &mut NftSafe<OriginByte>,
        nft: T,
    ) {
        nft_safe::deposit_nft(self, nft, Witness {});
    }

    /// Use a transfer auth to get an NFT out of the `Safe`.
    public fun transfer_nft_to_recipient<Auth: drop, E: drop, C: key + store>(
        self: &mut NftSafe<OriginByte>,
        nft_id: ID,
        recipient: address,
        entity_id: &UID,
        // TODO: separate API
        _entity_witness: E,
        authority: Auth,
        allowlist: &Allowlist,
    ) {
        let nft = nft_safe::get_nft<OriginByte, Witness, Nft<C>>(
            self,
            nft_id,
            entity_id,
            Witness {},
        );

        // // TODO: Consider deprecating logical owner
        nft::change_logical_owner(&mut nft, recipient, authority, allowlist);

        transfer(nft, recipient)
    }


    public fun transfer_nft_to_safe<Auth: drop, E: drop, C: key + store>(
        source: &mut NftSafe<OriginByte>,
        target: &mut NftSafe<OriginByte>,
        nft_id: ID,
        entity_id: &UID,
        // TODO: separate API
        _entity_witness: E,
        _authority: Auth,
        _allowlist: &Allowlist,
    ) {
        let nft = nft_safe::get_nft<OriginByte, Witness, Nft<C>>(
            source,
            nft_id,
            entity_id,
            Witness {},
        );

        // TODO: Consider deprecating logical owner
        // TODO: Uncomment this loc
        // nft::change_logical_owner(&mut nft, option::borrow(&target.inner.owner), authority, allowlist);

        deposit_nft(target, nft);
    }

    public fun delist_nft<Auth: drop, E: drop>(
        self: &mut NftSafe<OriginByte>,
        owner_cap: &OwnerCap,
        nft_id: ID,
        entity_id: &UID,
        // TODO: separate API
        _entity_witness: E,
        _authority: Auth,
        _allowlist: &Allowlist,
    ) {
        nft_safe::delist_nft(
            self,
            owner_cap,
            nft_id,
            entity_id,
            Witness {}
        );
    }

    // // === Getters ===

    // TODO: We need to be consistent, do we use T or C?
    public fun borrow_nft<C: key + store>(self: &NftSafe<OriginByte>, nft_id: ID): &C {
        nft_safe::borrow_nft(self, nft_id)
    }

    public fun has_nft<T: key + store>(self: &NftSafe<OriginByte>, nft_id: ID): bool {
        nft_safe::has_nft<OriginByte, T>(self, nft_id)
    }

    // Getter for OwnerCap's Safe ID
    public fun owner_cap_safe(cap: &OwnerCap): ID {
        nft_safe::owner_cap_safe(cap)
    }

    public fun nft_object_type(self: &NftSafe<OriginByte>, nft_id: ID): TypeName {
        nft_safe::nft_object_type(self, nft_id)
    }
}
