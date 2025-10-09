#[starknet::contract]
mod Registry {
    use ans::errors;
    use ans::interface::{IERC20Dispatcher, IERC20DispatcherTrait, IRegistry};
    use core::num::traits::zero::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    pub const DEFAULT_SUFFIX: felt252 = 'ans';

    #[storage]
    struct Storage {
        name_to_address: Map<felt252, Map<felt252, ContractAddress>>,
        address_to_name: Map<ContractAddress, felt252>,
        register_fee_in_bn: u256,
        fee_receiver: ContractAddress,
        asset_for_fee: ContractAddress,
    }

    #[abi(embed_v0)]
    impl RegistryImpl of IRegistry<ContractState> {
        fn register(ref self: ContractState, name: felt252, suffix: felt252) {
            assert(name.is_non_zero(), errors::ZERO_PREFIX);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);

            self.not_registered(name, suffix);

            let caller = get_caller_address();
            self.take_fees(caller);
            self.name_to_address.entry(suffix).write(name, caller);
            self.address_to_name.write(caller, name);
        }

        fn retrieve_address_from_name(
            self: @ContractState, name: felt252, suffix: felt252,
        ) -> ContractAddress {
            self.name_to_address.entry(suffix).read(name)
        }

        fn retrieve_name_from_address(self: @ContractState, addr: ContractAddress) -> felt252 {
            self.address_to_name.read(addr)
        }
    }

    #[generate_trait]
    impl RegistryInternal of RegistryInternalTrait {
        fn not_registered(self: @ContractState, name: felt252, suffix: felt252) {
            let result = self.name_to_address.entry(suffix).read(name);
            assert(result.is_zero(), errors::ALREADY_REGISTERED_NAME);
        }

        fn take_fees(ref self: ContractState, sender: ContractAddress) {
            let amount = self.register_fee_in_bn.read();
            let this = get_contract_address();
            let asset_addr = self.asset_for_fee.read();
            let dispatcher = IERC20Dispatcher { contract_address: asset_addr };
            dispatcher.transferFrom(sender, this, amount);
        }
    }
}
