module nft_protocol::ob_kiosk {
    use nft_protocol::ob_transfer_request::{Self, TransferRequest};
    use std::type_name::{Self, TypeName};
    use sui::dynamic_field::{Self as df};
    use sui::kiosk::{Self, Kiosk, uid_mut as ext};
    use sui::object::{Self, ID, UID, uid_to_address};
    use sui::table::{Self, Table};
    use sui::transfer::{public_share_object};
    use sui::tx_context::{TxContext, sender};
    use sui::vec_set::{Self, VecSet};

    // === Errors ===

    /// Trying to access an NFT that is not in the kiosk
    const EMissingNft: u64 = 1;
    /// NFT is already listed exclusively
    const ENftAlreadyExclusivelyListed: u64 = 2;
    /// NFT is already listed
    const ENftAlreadyListed: u64 = 3;
    /// Trying to withdraw profits and sender is not owner
    const EPermissionlessDepositsDisabled: u64 = 4;
    /// The provided Kiosk is not an OriginByte extension
    const EKioskNotOriginByteVersion: u64 = 5;
    /// The ID provided does not match the Kiosk
    const EIncorrectKioskId: u64 = 6;
    /// Trying to withdraw profits and sender is not owner
    const ENotOwner: u64 = 7;
    /// The transfer is not authorized for the given entity
    const ENotAuthorized: u64 = 8;
    /// Error for operations which demand that the kiosk owner is set to
    /// `PermissionlessAddr`
    const EKioskNotPermissionless: u64 = 9;
    /// The NFT type does not match the desired type
    const ENftTypeMismatch: u64 = 10;

    // === Constants ===

    /// If the owner of the kiosk is set to this address, all methods which
    /// would normally verify that the owner is the signer are permissionless.
    ///
    /// This is useful for wrapping kiosk functionality in a smart contract.
    /// Create a new permissionless kiosk with `new_permissionless`.
    const PermissionlessAddr: address = @0xb;

    // === Structs ===

    /// Inner accounting type.
    /// Stored under `NftRefsDfKey` as a dynamic field.
    ///
    /// Holds info about NFT listing which is used to determine if an entity
    /// is allowed to redeem the NFT.
    struct NftRef has store, drop {
        /// Entities which can use their `&UID` to redeem the NFT.
        ///
        /// We use address to be more versatile since `ID` can be converted to
        /// address.
        /// This way we support signers to be auths.
        auths: VecSet<address>,
        /// If set to true, then `listed_with` must have length of 1 and
        /// listed_for must be "none".
        is_exclusively_listed: bool,
        /// Kiosk is heterogeneous
        nft_type: TypeName,
    }

    /// Configures how deposits without owner cap are limited
    /// Stored under `DepositSettingDfKey` as a dynamic field.
    struct DepositSetting has store, drop {
        /// Enables depositing any collection, bypassing enabled deposits
        enable_any_deposit: bool,
        /// Collections which can be deposited into the `Safe`
        collections_with_enabled_deposits: VecSet<TypeName>,
    }

    // === Dynamic field keys ===

    /// For `Kiosk::id` value `Table<ID, NftRef>`
    struct NftRefsDfKey has store, copy, drop {}
    /// For `Kiosk::id` value `KioskOwnerCap`
    struct KioskOwnerCapDfKey has store, copy, drop {}
    /// For `Kiosk::id` value `DepositSetting`
    struct DepositSettingDfKey has store, copy, drop {}
    /// For `TransferRequest::metadata` value `TypeName`
    struct AuthTransferRequestDfKey has store, copy, drop {}

    // === Instantiators ===

    /// Calls `new`
    public fun create_for_sender(ctx: &mut TxContext) {
        public_share_object(new(ctx));
    }

    /// All functions which would normally verify that the owner is the signer
    /// are calleable.
    /// This means that the kiosk MUST be wrapped.
    /// Otherwise, anyone could call those functions.
    public fun new_permissionless(_ctx: &mut TxContext): Kiosk {
        // let kiosk = new(ctx);

        // let cap = pop_cap(&mut kiosk);
        // let nft = kiosk::set_owner_custom(&mut kiosk, &cap, PermissionlessAddr);
        // set_cap(&mut kiosk, cap);

        // kiosk

        abort(0) // TODO: wait for new Sui version

    }

    /// Changes the owner of a kiosk to the given address.
    /// This is only possible if the kiosk is currently permissionless.
    /// Ie. the old owner is `PermissionlessAddr`.
    ///
    /// Note that we don't support changing ownership of a kiosk that's not
    /// permissionless.
    /// The address that is set as the owner of the kiosk is the address that
    /// will remain the owner forever.
    public fun set_permissionless_to_permissioned(_self: &mut Kiosk, _user: address) {
        // assert!(kiosk::owner(self) == PermissionlessAddr, EKioskNotPermissionless);
        // let cap = pop_cap(self);
        // let nft = kiosk::set_owner_custom(self, &cap, user);
        // set_cap(self, cap);

        abort(0) // TODO: wait for new Sui version
    }

    /// Creates a new Kiosk in the OB ecosystem.
    /// By default, all deposits are allowed permissionlessly.
    ///
    /// The scope of deposits can be controlled with
    /// - `restrict_deposits` to allow only owner to deposit;
    /// - `enable_any_deposit` to again set deposits to be permissionless;
    /// - `disable_deposits_of_collection` to prevent specific collection to
    ///     deposit (ignored if all deposits enabled)
    /// - `enable_deposits_of_collection` to again specific collection to deposit
    ///     (useful in conjunction with restricting all deposits)
    ///
    /// Note that those collections which have restricted deposits will NOT be
    /// allowed to be transferred to the kiosk even on trades.
    public fun new(ctx: &mut TxContext): Kiosk {
        let (kiosk, kiosk_cap) = kiosk::new(ctx);
        let kiosk_ext = ext(&mut kiosk);

        df::add(kiosk_ext, KioskOwnerCapDfKey {}, kiosk_cap);
        df::add(kiosk_ext, NftRefsDfKey {}, table::new<ID, NftRef>(ctx));
        df::add(kiosk_ext, DepositSettingDfKey {}, DepositSetting {
            enable_any_deposit: true,
            collections_with_enabled_deposits: vec_set::empty(),
        });

        kiosk
    }

    // === Deposit to the Kiosk ===

    public fun deposit<T: key + store>(self: &mut Kiosk, nft: T) {
        assert_can_deposit<T>(self);
        deposit_(self, nft);
    }

    public fun deposit_as_owner<T: key + store>(
        self: &mut Kiosk, nft: T, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);
        deposit_(self, nft);
    }

    fun deposit_<T: key + store>(self: &mut Kiosk, nft: T) {
        // inner accounting
        let nft_id = object::id(&nft);
        let refs = nft_refs_mut(self);
        table::add(refs, nft_id, NftRef {
            auths: vec_set::empty(),
            is_exclusively_listed: false,
            nft_type: type_name::get<T>(),
        });

        // place underlying NFT to kiosk
        let cap = pop_cap(self);
        kiosk::place(self, &cap, nft);
        set_cap(self, cap);
    }

    // === Withdraw from the Kiosk ===

    /// Authorizes given entity to take given NFT out.
    /// The entity must prove with their `&UID` in `transfer_delegated` or
    /// must be the signer in `transfer_signed`.
    ///
    /// Use the `object::id_to_address` to authorize entities which only live
    /// on chain.
    public fun auth_transfer(
        self: &mut Kiosk,
        nft_id: ID,
        entity: address,
        ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);

        let refs = nft_refs_mut(self);
        let ref = table::borrow_mut(refs, nft_id);
        assert_ref_not_exclusively_listed(ref);
        vec_set::insert(&mut ref.auths, entity);
    }

    /// Authorizes ONLY given entity to take given NFT out.
    /// No one else (including the owner) can perform a transfer.
    ///
    /// The entity must prove with their `&UID` in `transfer_delegated`.
    ///
    /// Only the given entity can then delist their listing.
    /// This is a dangerous action to be used only with audited contracts
    /// because the NFT is locked until given entity agrees to release it.
    public fun auth_exclusive_transfer(
        self: &mut Kiosk,
        nft_id: ID,
        entity_id: &UID,
        ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);

        let refs = nft_refs_mut(self);
        let ref = table::borrow_mut(refs, nft_id);
        assert_not_listed(ref);
        vec_set::insert(&mut ref.auths, uid_to_address(entity_id));
        ref.is_exclusively_listed = true;
    }

    /// Can be called by an entity that has been authorized by the owner to
    /// withdraw given NFT.
    ///
    /// Returns a builder to the calling entity.
    /// The entity then populates it with trade information of which fungible
    /// tokens were paid.
    ///
    /// The builder then _must_ be transformed into a hot potato `TransferRequest`
    /// which is then used by logic that has access to `TransferPolicy`.
    ///
    /// Can only be called on kiosks in the OB ecosystem.
    ///
    /// We adhere to the deposit rules of the target kiosk.
    /// If we didn't, it'd be pointless to even have them since a spammer
    /// could simply simulate a transfer and select any target.
    public fun transfer_delegated<T: key + store>(
        source: &mut Kiosk,
        target: &mut Kiosk,
        nft_id: ID,
        entity_id: &UID,
        ctx: &mut TxContext,
    ): TransferRequest<T> {
        let (nft, builder) = withdraw_nft(source, nft_id, entity_id, ctx);
        deposit(target, nft);
        builder
    }

    /// Similar to `transfer_delegated` but instead of proving origin with
    /// `&UID` we check that the entity is the signer.
    ///
    /// This will always work if the signer is the owner of the kiosk.
    public fun transfer_signed<T: key + store>(
        source: &mut Kiosk,
        target: &mut Kiosk,
        nft_id: ID,
        ctx: &mut TxContext,
    ): TransferRequest<T> {
        let (nft, builder) = withdraw_nft_signed(source, nft_id, ctx);
        deposit(target, nft);
        builder
    }

    /// We allow withdrawing NFTs for some use cases.
    /// If an NFT leaves our kiosk ecosystem, we can no longer guarantee
    /// royalty enforcement.
    /// Therefore, creators might not allow entities which enable withdrawing
    /// NFTs to trade their collection.
    ///
    /// You almost certainly want to use `transfer_delegated`.
    ///
    /// Handy for migrations.
    public fun withdraw_nft<T: key + store>(
        self: &mut Kiosk,
        nft_id: ID,
        entity_id: &UID,
        ctx: &mut TxContext,
    ): (T, TransferRequest<T>) {
        withdraw_nft_(self, nft_id, uid_to_address(entity_id), ctx)
    }

    /// Similar to `withdraw_nft` but the entity is a signer instead of UID.
    /// The owner doesn't can always initiate a withdraw.
    ///
    /// A withdraw can be prevented with an allowlist.
    public fun withdraw_nft_signed<T: key + store>(
        self: &mut Kiosk,
        nft_id: ID,
        ctx: &mut TxContext,
    ): (T, TransferRequest<T>) {
        withdraw_nft_(self, nft_id, sender(ctx), ctx)
    }

    /// After authorization that the call is permitted, gets the NFT.
    fun withdraw_nft_<T: key + store>(
        self: &mut Kiosk,
        nft_id: ID,
        originator: address,
        ctx: &mut TxContext,
    ): (T, TransferRequest<T>) {
        check_entity_and_pop_ref(self, originator, nft_id, ctx);

        let cap = pop_cap(self);
        let nft = kiosk::take<T>(self, &cap, nft_id);
        set_cap(self, cap);

        (nft, ob_transfer_request::new(nft_id, originator, ctx))
    }

    /// If both kiosks are owned by the same user, then we allow free transfer.
    public fun transfer_between_owned<T: key + store>(
        source: &mut Kiosk,
        target: &mut Kiosk,
        nft_id: ID,
        ctx: &mut TxContext,
    ) {
        assert_permission(source, ctx);
        assert!(kiosk::owner(source) != PermissionlessAddr, ENotAuthorized);
        assert!(kiosk::owner(source) == kiosk::owner(target), ENotOwner);

        let refs = df::borrow_mut(ext(source), NftRefsDfKey {});
        let ref = table::remove(refs, nft_id);
        assert_ref_not_exclusively_listed(&ref);

        let cap = pop_cap(source);
        let nft = kiosk::take<T>(source, &cap, nft_id);
        set_cap(source, cap);

        deposit_(target, nft);
    }

    /// Proves access to given type `Auth`.
    /// Useful in conjunction with witness-like types.
    /// Trading contracts proves themselves with `Auth` instead of UID.
    /// This makes it easier to implement allowlists since we can globally
    /// allow a contract to trade.
    /// Allowlist could also be implemented with a UID but that would require
    /// that the trading contracts maintain a global object.
    /// In some cases this is doable, in other it's inconvenient.
    public fun set_transfer_request_auth<T, Auth>(
        req: &mut TransferRequest<T>,
        _auth: &Auth,
    ) {
        let metadata = ob_transfer_request::metadata_mut(req);
        df::add(metadata, AuthTransferRequestDfKey {}, type_name::get<Auth>());
    }

    public fun get_transfer_request_auth<T>(
        req: &mut TransferRequest<T>,
    ): &TypeName {
        let metadata = ob_transfer_request::metadata_mut(req);
        df::borrow(metadata, AuthTransferRequestDfKey {})
    }

    // === Delisting of NFTs ===

    /// Removes _all_ entities from access to the NFT.
    /// Cannot be performed if the NFT is exclusively listed.
    public fun delist_nft_as_owner(
        self: &mut Kiosk, nft_id: ID, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);

        let refs = nft_refs_mut(self);
        let ref = table::borrow_mut(refs, nft_id);
        assert_ref_not_exclusively_listed(ref);
        ref.auths = vec_set::empty();
    }

    /// Removes a specific NFT from access to the NFT.
    /// Cannot be performed if the NFT is exclusively listed.
    public fun remove_auth_transfer_as_owner(
        self: &mut Kiosk, nft_id: ID, entity: address, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);

        let refs = nft_refs_mut(self);
        let ref = table::borrow_mut(refs, nft_id);
        assert_ref_not_exclusively_listed(ref);
        vec_set::remove(&mut ref.auths, &entity);
    }

    /// This is the only path to delist an exclusively listed NFT.
    public fun remove_auth_transfer(
        self: &mut Kiosk, nft_id: ID, entity: &UID,
    ) {
        let entity = uid_to_address(entity);

        let refs = nft_refs_mut(self);
        let ref = table::borrow_mut(refs, nft_id);
        vec_set::remove(&mut ref.auths, &entity);
        ref.is_exclusively_listed = false; // no-op if it wasn't
    }

    // === Configure deposit settings ===

    /// Only owner or allowlisted collections can deposit.
    public entry fun restrict_deposits(
        self: &mut Kiosk, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);
        let settings = deposit_setting_mut(self);
        settings.enable_any_deposit = false;
    }

    /// No restriction on deposits.
    public entry fun enable_any_deposit(
        self: &mut Kiosk, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);
        let settings = deposit_setting_mut(self);
        settings.enable_any_deposit = true;
    }

    /// The owner can restrict deposits into the `Kiosk` from given
    /// collection.
    ///
    /// However, if the flag `DepositSetting::enable_any_deposit` is set to
    /// true, then it takes precedence.
    public entry fun disable_deposits_of_collection<C>(
        self: &mut Kiosk, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);
        let settings = deposit_setting_mut(self);
        let col_type = type_name::get<C>();
        vec_set::remove(&mut settings.collections_with_enabled_deposits, &col_type);
    }

    /// The owner can enable deposits into the `Kiosk` from given
    /// collection.
    ///
    /// However, if the flag `Kiosk::enable_any_deposit` is set to
    /// true, then it takes precedence anyway.
    public entry fun enable_deposits_of_collection<C>(
        self: &mut Kiosk, ctx: &mut TxContext,
    ) {
        assert_permission(self, ctx);
        let settings = deposit_setting_mut(self);
        let col_type = type_name::get<C>();
        vec_set::insert(&mut settings.collections_with_enabled_deposits, col_type);
    }

    // === Assertions and getters ===

    /// Immutably borrow an item from the `Kiosk`.
    public fun borrow<T: key + store>(_self: &mut Kiosk, _nft_id: ID): &T {
        // let cap = pop_cap(self);
        // let nft = kiosk::borrow(self, cap, nft_id);
        // set_cap(self, cap);

        // nft

        abort(0) // TODO: wait for new Sui version
    }

    public fun nft_type(self: &mut Kiosk, nft_id: ID): &TypeName {
        let refs = nft_refs_mut(self);
        let ref = table::borrow(refs, nft_id);
        &ref.nft_type
    }

    public fun is_ob_kiosk(self: &mut Kiosk): bool {
        df::exists_(ext(self), NftRefsDfKey {})
    }

    public fun can_deposit<T>(self: &mut Kiosk): bool {
        let settings = deposit_setting_mut(self);

        settings.enable_any_deposit ||
            vec_set::contains(
                &settings.collections_with_enabled_deposits,
                &type_name::get<T>(),
            )
    }

    public fun assert_nft_type<T>(self: &mut Kiosk, nft_id: ID) {
        assert!(nft_type(self, nft_id) == &type_name::get<T>(), ENftTypeMismatch);
    }

    public fun assert_can_deposit<T>(self: &mut Kiosk) {
        assert!(can_deposit<T>(self), EPermissionlessDepositsDisabled);
    }

    public fun assert_owner_address(self: &Kiosk, owner: address) {
        assert!(kiosk::owner(self) == owner, ENotOwner);
    }

    /// Either the kiosk is permissionless, or the sender is the owner.
    public fun assert_permission(self: &Kiosk, ctx: &mut TxContext) {
        let owner = kiosk::owner(self);
        assert!(owner == PermissionlessAddr || owner == sender(ctx), ENotOwner);
    }

    public fun assert_has_nft(self: &Kiosk, nft_id: ID) {
        assert!(kiosk::has_item(self, nft_id), EMissingNft)
    }

    public fun assert_not_exclusively_listed<I: key + store>(
        self: &mut Kiosk, nft_id: ID
    ) {
        let refs = df::borrow(ext(self), NftRefsDfKey {});
        let ref = table::borrow(refs, nft_id);
        assert_ref_not_exclusively_listed(ref);
    }

    public fun assert_is_ob_kiosk(self: &mut Kiosk) {
        assert!(is_ob_kiosk(self), EKioskNotOriginByteVersion);
    }

    public fun assert_kiosk_id(self: &Kiosk, id: ID) {
        assert!(object::id(self) == id, EIncorrectKioskId);
    }

    fun assert_ref_not_exclusively_listed(ref: &NftRef) {
        assert!(!ref.is_exclusively_listed, ENftAlreadyExclusivelyListed);
    }

    fun assert_not_listed(ref: &NftRef) {
        assert!(vec_set::size(&ref.auths) == 0, ENftAlreadyListed);
    }

    fun check_entity_and_pop_ref(
        self: &mut Kiosk, entity: address, nft_id: ID, ctx: &mut TxContext,
    ) {
        let refs = nft_refs_mut(self);
        // NFT is being transferred - destroy the ref
        let ref: NftRef = table::remove(refs, nft_id);
        // sender is signer
        // OR
        // entity MUST be included in the map
        assert!(
            sender(ctx) == entity || vec_set::contains(&ref.auths, &entity),
            ENotAuthorized,
        );
    }

    fun deposit_setting_mut(self: &mut Kiosk): &mut DepositSetting {
        df::borrow_mut(ext(self), DepositSettingDfKey {})
    }

    fun nft_refs_mut(self: &mut Kiosk): &mut Table<ID, NftRef> {
        df::borrow_mut(ext(self), NftRefsDfKey {})
    }

    fun pop_cap(self: &mut Kiosk): kiosk::KioskOwnerCap {
        df::remove(ext(self), KioskOwnerCapDfKey {})
    }

    fun set_cap(self: &mut Kiosk, cap: kiosk::KioskOwnerCap) {
        df::add(ext(self), KioskOwnerCapDfKey {}, cap);
    }
}
