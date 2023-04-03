#[test_only]
module nft_protocol::test_royalty {
    use sui::transfer;
    use sui::test_scenario::{Self, ctx};

    use nft_protocol::collection;
    use nft_protocol::royalty::{Self, RoyaltyDomain};

    struct Foo has drop {}
    struct Witness has drop {}

    const CREATOR: address = @0xA1C04;

    #[test]
    fun add_royalty() {
        let scenario = test_scenario::begin(CREATOR);

        let collection = collection::create(Witness {}, ctx(&mut scenario));

        let royalty = royalty::from_address(CREATOR, ctx(&mut scenario));
        royalty::add_proportional_royalty(&mut royalty, 100);
        royalty::add_constant_royalty(&mut royalty, 100);
        royalty::add_royalty_domain(
            Witness {},
            &mut collection,
            royalty,
        );

        collection::assert_domain<Foo, RoyaltyDomain>(&collection);

        transfer::public_share_object(collection);

        test_scenario::end(scenario);
    }
}
