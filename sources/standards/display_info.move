/// Module of the `DisplayInfo`
module nft_protocol::display_info {
    use std::ascii::String;

    use sui::object::UID;
    use sui::dynamic_field as df;

    use nft_protocol::utils::{
        assert_with_witness, assert_with_consumable_witness, UidType
    };
    use nft_protocol::consumable_witness::{Self as cw, ConsumableWitness};

    /// No field object `DisplayInfo` defined as a dynamic field.
    const EUNDEFINED_DISPLAY_INFO_FIELD: u64 = 1;

    /// Field object `DisplayInfo` already defined as dynamic field.
    const EDISPLAY_INFO_FIELD_ALREADY_EXISTS: u64 = 2;

    struct DisplayInfo has store {
        name: String,
        description: String,
    }

    /// Witness used to authenticate witness protected endpoints
    struct Witness has drop {}

    /// Key struct used to store DisplayInfo in dynamic fields
    struct DisplayInfoKey has store, copy, drop {}


    // === Insert with ConsumableWitness ===


    /// Adds `DisplayInfo` as a dynamic field with key `DisplayInfoKey`.
    ///
    /// Endpoint is protected as it relies on safetly obtaining a
    /// `ConsumableWitness` for the specific type `T` and field `DisplayInfo`.
    ///
    /// #### Panics
    ///
    /// Panics if `object_uid` does not correspond to `object_type.id`,
    /// in other words, it panics if `object_uid` is not of type `T`.
    public fun add_display_info<T: key>(
        consumable: ConsumableWitness<T>,
        object_uid: &mut UID,
        object_type: UidType<T>,
        name: String,
        description: String,
    ) {
        assert_has_not_display_info(object_uid);
        assert_with_consumable_witness(object_uid, object_type);

        let display_info = new(name, description);

        cw::consume<T, DisplayInfo>(consumable, &mut display_info);
        df::add(object_uid, DisplayInfoKey {}, display_info);
    }


    // === Get for call from external Module ===


    /// Creates new `DisplayInfo`
    public fun new(name: String, description: String): DisplayInfo {
        DisplayInfo { name, description }
    }

    // === Field Borrow Functions ===


    /// Borrows immutably the `DisplayInfo` field.
    ///
    /// #### Panics
    ///
    /// Panics if dynamic field with `DisplayInfoKey` does not exist.
    public fun borrow_display_info(
        object_uid: &UID,
    ): &DisplayInfo {
        // `df::borrow` fails if there is no such dynamic field,
        // however asserting it here allows for a more straightforward
        // error message
        assert_has_display_info(object_uid);
        df::borrow(object_uid, DisplayInfoKey {})
    }

    /// Borrows Mutably the `DisplayInfo` field.
    ///
    /// Endpoint is protected as it relies on safetly obtaining a
    /// `ConsumableWitness` for the specific type `T` and field `DisplayInfo`.
    ///
    /// #### Panics
    ///
    /// Panics if dynamic field with `DisplayInfoKey` does not exist.
    ///
    /// Panics if `object_uid` does not correspond to `object_type.id`,
    /// in other words, it panics if `object_uid` is not of type `T`.
    public fun borrow_display_info_mut<T: key>(
        consumable: ConsumableWitness<T>,
        object_uid: &mut UID,
        object_type: UidType<T>
    ): &mut DisplayInfo {
        // `df::borrow` fails if there is no such dynamic field,
        // however asserting it here allows for a more straightforward
        // error message
        assert_has_display_info(object_uid);
        assert_with_consumable_witness(object_uid, object_type);

        let display_info = df::borrow_mut<DisplayInfoKey, DisplayInfo>(
            object_uid,
            DisplayInfoKey {}
        );
        cw::consume<T, DisplayInfo>(consumable, display_info);

        display_info
    }


    // === Writer Functions ===


    /// Changes name string in the object field `DisplayInfo` of the object type `T`.
    ///
    /// Endpoint is protected as it relies on safetly obtaining a
    /// `ConsumableWitness` for the specific type `T` and field `DisplayInfo`.
    ///
    /// #### Panics
    ///
    /// Panics if dynamic field with `DisplayInfoKey` does not exist.
    ///
    /// Panics if `object_uid` does not correspond to `object_type.id`,
    /// in other words, it panics if `object_uid` is not of type `T`.
    public fun change_name<T: key>(
        consumable: ConsumableWitness<T>,
        object_uid: &mut UID,
        object_type: UidType<T>,
        new_name: String,
    ) {
        // `df::borrow` fails if there is no such dynamic field,
        // however asserting it here allows for a more straightforward
        // error message
        assert_has_display_info(object_uid);
        assert_with_consumable_witness(object_uid, object_type);

        let display_info = borrow_mut_internal(object_uid);

        cw::consume<T, DisplayInfo>(consumable, display_info);
        display_info.name = new_name;
    }


    /// Changes description string in the object field `DisplayInfo` of the object type `T`.
    ///
    /// Endpoint is protected as it relies on safetly obtaining a
    /// `ConsumableWitness` for the specific type `T` and field `DisplayInfo`.
    ///
    /// #### Panics
    ///
    /// Panics if dynamic field with `DisplayInfoKey` does not exist.
    ///
    /// Panics if `object_uid` does not correspond to `object_type.id`,
    /// in other words, it panics if `object_uid` is not of type `T`.
    public fun change_description<T: key>(
        consumable: ConsumableWitness<T>,
        object_uid: &mut UID,
        object_type: UidType<T>,
        new_description: String,
    ) {
        // `df::borrow` fails if there is no such dynamic field,
        // however asserting it here allows for a more straightforward
        // error message
        assert_has_display_info(object_uid);
        assert_with_consumable_witness(object_uid, object_type);

        let display_info = borrow_mut_internal(object_uid);

        cw::consume<T, DisplayInfo>(consumable, display_info);
        display_info.description = new_description;
    }


    // === Getter Functions & Static Mutability Accessors ===


    /// Borrows underlying `DisplayInfo` name string.
    public fun get_name(
        display_info: &DisplayInfo,
    ): &String {
        &display_info.name
    }

    /// Borrows underlying `DisplayInfo` description string.
    public fun get_description(
        display_info: &DisplayInfo,
    ): &String {
        &display_info.description
    }

    /// Mutably borrows underlying `DisplayInfo` name string.
    ///
    /// Endpoint is unprotected as it relies on safetly obtaining a mutable
    /// reference to `DisplayInfo`.
    public fun get_name_mut(
        display_info: &mut DisplayInfo,
    ): &String {
        &mut display_info.name
    }

    /// Mutably borrows underlying `DisplayInfo` description string.
    ///
    /// Endpoint is unprotected as it relies on safetly obtaining a mutable
    /// reference to `DisplayInfo`.
    public fun get_description_mut(
        display_info: &mut DisplayInfo,
    ): &String {
        &mut display_info.description
    }


    // === Private Functions ===


    /// Borrows Mutably the `DisplayInfo` field.
    ///
    /// For internal use only.
    fun borrow_mut_internal(
        object_uid: &mut UID,
    ): &mut DisplayInfo {
        df::borrow_mut<DisplayInfoKey, DisplayInfo>(
            object_uid,
            DisplayInfoKey {}
        )
    }

    // === Assertions & Helpers ===


    /// Checks that a given Object has a dynamic field with `DisplayInfoKey`
    public fun has_display_info(
        object_uid: &UID,
    ): bool {
        df::exists_(object_uid, DisplayInfoKey {})
    }

    public fun assert_has_display_info(object_uid: &UID) {
        assert!(has_display_info(object_uid), EUNDEFINED_DISPLAY_INFO_FIELD);
    }

    public fun assert_has_not_display_info(object_uid: &UID) {
        assert!(!has_display_info(object_uid), EDISPLAY_INFO_FIELD_ALREADY_EXISTS);
    }
}
